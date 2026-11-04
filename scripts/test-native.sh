#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests .build/clang-module-cache
xcrun swiftc -swift-version 6 -parse-as-library \
    -target "$(uname -m)-apple-macosx15.0" \
    -module-cache-path "$PWD/.build/clang-module-cache" \
    Sources/WorkThreadTimeline/NativeThreadDrag.swift \
    Sources/WorkThreadTimeline/EditingBoundary.swift \
    Tests/NativeInteractionTests.swift -o .build/tests/native-interaction-tests
.build/tests/native-interaction-tests
