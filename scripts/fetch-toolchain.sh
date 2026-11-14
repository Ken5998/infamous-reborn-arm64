#!/usr/bin/env bash
# Downloads the Windows ARM64 toolchain into DIR (default ./toolchain): llvm-mingw for this
# machine, sse2neon next to this repository's x86 compat headers, and the case-fixed import
# library names the runtime's #pragma comment(lib) lines ask for. Versions and hashes are in
# upstream.json.
#
#   scripts/fetch-toolchain.sh [DIR]
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/scripts/common.sh"
tc="${1:-$PWD/toolchain}"
mkdir -p "$tc"
tc="$(cd "$tc" && pwd)"

case "$(uname -m)" in
    aarch64|arm64) host=aarch64 ;;
    x86_64|amd64) host=x86_64 ;;
    *) echo "error: no llvm-mingw build for $(uname -m)" >&2; exit 1 ;;
esac
ver="$(field llvm_mingw version)"
if [ "$(cat "$tc/llvm-mingw/.version" 2>/dev/null)" != "$ver-$host" ]; then
    tarball="$tc/downloads/llvm-mingw-$ver-$host.tar.xz"
    fetch "$(field llvm_mingw "$host" url)" "$(field llvm_mingw "$host" sha256)" "$tarball"
    rm -rf "$tc/llvm-mingw" "$tc/llvm-mingw.tmp"
    mkdir -p "$tc/llvm-mingw.tmp"
    tar -xJf "$tarball" -C "$tc/llvm-mingw.tmp" --strip-components=1
    mv "$tc/llvm-mingw.tmp" "$tc/llvm-mingw"
    echo "$ver-$host" > "$tc/llvm-mingw/.version"
    rm -f "$tarball"
fi
"$tc/llvm-mingw/bin/aarch64-w64-mingw32-clang" --version | head -1

# x86 intrinsic headers -> sse2neon
inc="$tc/x86compat"
mkdir -p "$inc"
fetch "$(field sse2neon url)" "$(field sse2neon sha256)" "$inc/sse2neon.h"
cp -f "$repo"/compat/x86/*.h "$inc/"

# #pragma comment(lib, "Synchronization.lib") -> libsynchronization.a (Linux file names are case sensitive)
lib="$tc/libcase"
mkdir -p "$lib"
for n in Synchronization; do
    ln -sfn "$tc/llvm-mingw/aarch64-w64-mingw32/lib/lib$(echo "$n" | tr '[:upper:]' '[:lower:]').a" "$lib/lib$n.a"
done
echo "Toolchain ready in $tc"
