#!/bin/bash
# Usage: bash scripts/release-notes.sh <version>
# Prints the CHANGELOG.md section for <version> (without its heading).
set -euo pipefail
cd "$(dirname "$0")/.."
awk -v v="$1" '
    $0 == "## " v { found = 1; next }
    found && /^## / { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d'
