#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests .build/clang-module-cache
xcrun swiftc -swift-version 6 -parse-as-library \
    -target "$(uname -m)-apple-macosx15.0" \
    -module-cache-path "$PWD/.build/clang-module-cache" \
    Sources/WorkThreadTimeline/WorkThread.swift \
    Sources/WorkThreadTimeline/WorkspacePersistence.swift \
    Sources/WorkThreadTimeline/WorkspaceArchive.swift \
    Sources/WorkThreadTimeline/NativeThreadDrag.swift \
    Sources/WorkThreadTimeline/WorkspaceStore.swift \
    Tests/Phase2Tests.swift -o .build/tests/phase2-tests
TEST_DIR="$(mktemp -d "$PWD/.build/tests/run.XXXXXX")"
.build/tests/phase2-tests unit "$TEST_DIR/unit.store"
.build/tests/phase2-tests write "$TEST_DIR/restart.store"
.build/tests/phase2-tests read "$TEST_DIR/restart.store"
.build/tests/phase2-tests verify "$TEST_DIR/restart.store"
.build/tests/phase2-tests corrupt "$TEST_DIR/corrupt.store"
.build/tests/phase2-tests safety "$TEST_DIR/safety.store"
.build/tests/phase2-tests migration "$TEST_DIR/migration.store"
.build/tests/phase2-tests undo "$TEST_DIR/undo.store"
printf '\nAll core tests passed. Test stores: %s\n' "$TEST_DIR"
