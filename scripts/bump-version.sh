#!/bin/bash
# Usage: bash scripts/bump-version.sh <new-version>   e.g. 0.5.4
# Sets MARKETING_VERSION, increments BUILD_NUMBER, updates the README title,
# and adds an empty CHANGELOG section to fill in before merging.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: bump-version.sh <new-version>}"
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 1.2.3" >&2; exit 2
fi
source version.env
if [[ "$NEW" == "$MARKETING_VERSION" ]]; then
    echo "Already at $NEW" >&2; exit 2
fi
NEXT_BUILD=$((BUILD_NUMBER + 1))
sed -i.bak -e "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$NEW/" \
    -e "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$NEXT_BUILD/" version.env
sed -i.bak -e "1s/^# Float — .*/# Float — $NEW/" README.md
if ! grep -q "^## $NEW\$" CHANGELOG.md; then
    awk -v v="$NEW" 'NR==1{print; print ""; print "## " v; print ""; print "- "; next} {print}' \
        CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
fi
rm -f version.env.bak README.md.bak
echo "Bumped to $NEW (build $NEXT_BUILD). Fill in CHANGELOG.md, then merge into main to release."
