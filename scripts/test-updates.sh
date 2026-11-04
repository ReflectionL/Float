#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests .build/clang-module-cache
xcrun swiftc -swift-version 6 -parse-as-library \
    -target "$(uname -m)-apple-macosx15.0" \
    -module-cache-path "$PWD/.build/clang-module-cache" \
    Sources/WorkThreadTimeline/AppIdentity.swift \
    Sources/WorkThreadTimeline/ReleaseVersion.swift \
    Sources/WorkThreadTimeline/UpdateController.swift \
    Sources/WorkThreadTimeline/UpdateInstaller.swift \
    Tests/UpdateTests.swift -o .build/tests/update-tests
.build/tests/update-tests
