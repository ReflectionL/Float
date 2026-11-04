#!/bin/bash
# Usage: bash scripts/package-dmg.sh
# Packages build/Float.app (built with FLOAT_RELEASE_TAG) into
# dist/Float-<version>.dmg plus a `<sha256>  <name>` checksum file, the asset
# names the in-app updater looks for.
set -euo pipefail
cd "$(dirname "$0")/.."
source version.env
APP="build/Float.app"
DMG="dist/Float-$MARKETING_VERSION.dmg"
CHECKSUM="$DMG.sha256"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$MARKETING_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :FloatReleaseTag' "$APP/Contents/Info.plist")" = "$MARKETING_VERSION" \
    || { echo "Build with FLOAT_RELEASE_TAG=v$MARKETING_VERSION first" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/float-dmg.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
ditto "$APP" "$STAGING/Float.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
rm -f -- "$DMG" "$CHECKSUM"
hdiutil create -quiet -volname "Float" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"
printf '%s  %s\n' "$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)" "$(basename "$DMG")" > "$CHECKSUM"
echo "$DMG"
echo "$CHECKSUM"
