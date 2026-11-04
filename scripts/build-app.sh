#!/bin/bash
set -euo pipefail

# Usage: bash scripts/build-app.sh [--qa] [--open] [--universal]
#   --qa         build "Float QA.app" with an isolated store
#   --open       open the app after building
#   --universal  build an arm64 + x86_64 binary (used for releases)
cd "$(dirname "$0")/.."
# shellcheck source=../version.env
source version.env
QA=0
OPEN=0
ARCHS=("$(uname -m)")
for arg in "$@"; do
    case "$arg" in
        --qa) QA=1 ;;
        --open) OPEN=1 ;;
        --universal) ARCHS=(arm64 x86_64) ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
mkdir -p .build/release .build/clang-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
# Compile directly so the prototype needs only Command Line Tools, not Xcode
# or a working SwiftPM manifest runtime.
SWIFT_FLAGS=(-D PRODUCTION)
APP_NAME="Float"
APP_ID="local.xline.WorkThreadTimeline"
if [[ "$QA" == 1 ]]; then
    SWIFT_FLAGS=(-D UI_TEST)
    APP_NAME="Float QA"
    APP_ID="local.xline.WorkThreadTimeline.QA"
fi
SLICES=()
for arch in "${ARCHS[@]}"; do
    xcrun swiftc "${SWIFT_FLAGS[@]}" -swift-version 6 -O -parse-as-library \
        -target "$arch-apple-macosx15.0" \
        -module-cache-path "$PWD/.build/clang-module-cache" \
        Sources/WorkThreadTimeline/*.swift \
        -o ".build/release/WorkThreadTimeline-$arch"
    SLICES+=(".build/release/WorkThreadTimeline-$arch")
done
xcrun lipo -create "${SLICES[@]}" -output .build/release/WorkThreadTimeline
BIN_DIR="$PWD/.build/release"
APP_DIR="$PWD/build/$APP_NAME.app"
if [[ ! -f Resources/AppIcon.icns || Resources/AppIcon.png -nt Resources/AppIcon.icns || scripts/build-icon.sh -nt Resources/AppIcon.icns ]]; then
    bash scripts/build-icon.sh
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/WorkThreadTimeline" "$APP_DIR/Contents/MacOS/WorkThreadTimeline.new"
mv -f "$APP_DIR/Contents/MacOS/WorkThreadTimeline.new" "$APP_DIR/Contents/MacOS/WorkThreadTimeline"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>WorkThreadTimeline</string>
    <key>CFBundleIdentifier</key><string>local.xline.WorkThreadTimeline</string>
    <key>CFBundleName</key><string>Float</string>
    <key>CFBundleDisplayName</key><string>Float</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP_DIR/Contents/Info.plist"
if [[ "$QA" == 1 ]]; then
    /usr/libexec/PlistBuddy -c "Add :XlineQAStorePath string $PWD/.build/ui-qa/workspace.store" "$APP_DIR/Contents/Info.plist"
fi
codesign --force --sign - "$APP_DIR"
touch "$APP_DIR"
printf '\nBuilt: %s\n' "$APP_DIR"
if [[ "$OPEN" == 1 ]]; then
    open "$APP_DIR"
fi
