#!/usr/bin/env bash
# Downloads the Windows ARM64 toolchain into DIR (default ./toolchain): llvm-mingw for this
# machine, sse2neon next to this repository's x86 compat headers, the case-fixed import library
# names the runtime's #pragma comment(lib) lines ask for and, on aarch64, CMake and Ninja
# (ArmadaOS has neither) in DIR/bin. Versions and hashes are in upstream.json. Needs only curl,
# tar, xz and python3, so it also runs on ArmadaOS.
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
if [ "$host" = aarch64 ]; then
    mkdir -p "$tc/bin"
    if [ "$(cat "$tc/cmake/.version" 2>/dev/null)" != "$(field cmake version)" ]; then
        fetch "$(field cmake aarch64 url)" "$(field cmake aarch64 sha256)" "$tc/downloads/cmake.tar.gz"
        rm -rf "$tc/cmake" && mkdir -p "$tc/cmake"
        tar -xzf "$tc/downloads/cmake.tar.gz" -C "$tc/cmake" --strip-components=1
        field cmake version > "$tc/cmake/.version"
        rm -f "$tc/downloads/cmake.tar.gz"
    fi
    if [ "$(cat "$tc/ninja.version" 2>/dev/null)" != "$(field ninja version)" ]; then
        fetch "$(field ninja aarch64 url)" "$(field ninja aarch64 sha256)" "$tc/downloads/ninja.zip"
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("ninja", sys.argv[2])' "$tc/downloads/ninja.zip" "$tc/bin"
        chmod +x "$tc/bin/ninja"
        field ninja version > "$tc/ninja.version"
        rm -f "$tc/downloads/ninja.zip"
    fi
    for t in cmake ctest; do ln -sfn "../cmake/bin/$t" "$tc/bin/$t"; done
fi
echo "Toolchain ready in $tc"
