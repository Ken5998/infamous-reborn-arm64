#!/usr/bin/env bash
# Gets inFAMOUS Reborn at the commit in upstream.json into WORK/inFAMOUSreborn and applies this
# repository's patches (patches/upstream). Run again after updating this repository: the checkout
# is reset to the pinned commit first, so it never mixes old and new patches. The game files the
# installer generates there (recompiled code, SPU programs, assets) are untracked and are kept.
#
#   scripts/prepare.sh WORK
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/scripts/common.sh"
[ $# -eq 1 ] || { echo "usage: $0 WORK" >&2; exit 2; }
mkdir -p "$1"
src="$(cd "$1" && pwd)/inFAMOUSreborn"
url="$(field infamous repo)"
commit="$(field infamous commit)"

if [ ! -d "$src/.git" ]; then
    git init -q "$src"
    git -C "$src" remote add origin "$url"
fi
git -C "$src" remote set-url origin "$url"
if ! git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$src" fetch -q --depth 1 origin "$commit"
fi
# back to the pinned commit; untracked files (the generated game code) stay where they are
git -C "$src" -c advice.detachedHead=false checkout -q -f "$commit"
git -C "$src" reset -q --hard "$commit"
for p in "$repo"/patches/upstream/*.patch; do
    [ -e "$p" ] || continue
    echo "Applying $(basename "$p")"
    git -C "$src" apply --whitespace=nowarn "$p"
done
echo "inFAMOUS Reborn $commit ready in $src"
