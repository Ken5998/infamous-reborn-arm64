#!/usr/bin/env bash
# Configures and builds inFamousRecomp.exe for Windows ARM64 with llvm-mingw.
#
#   scripts/build-game.sh SRC TOOLCHAIN [RECOMP_DIR]
#
# SRC         the prepared inFAMOUS Reborn checkout (scripts/prepare.sh)
# TOOLCHAIN   the folder scripts/fetch-toolchain.sh filled
# RECOMP_DIR  the lifted PPU code (default SRC/infamous-recomp/recompiled, written by the installer)
#
# The build goes to SRC/infamous-recomp/build-arm64. IF_JOBS sets the parallel compiler jobs,
# IF_TARGETS a list of ninja targets instead of the whole game (CI).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/scripts/common.sh"
[ $# -ge 2 ] || { echo "usage: $0 SRC TOOLCHAIN [RECOMP_DIR]" >&2; exit 2; }
src="$(cd "$1" && pwd)"
tc="$(cd "$2" && pwd)"
recomp="${3:-$src/infamous-recomp/recompiled}"
build="$src/infamous-recomp/build-arm64"
export IF_TOOLCHAIN="$tc"

flags="-fms-extensions $IF_ARCH_FLAGS"
# x86 SIMD code paths compile through sse2neon (compat/x86); the runtime picks its SSE4.1 paths
flags+=" -D__SSE__ -D__SSE2__ -D__SSE3__ -D__SSSE3__ -D__SSE4_1__ -D__SSE4_2__"
flags+=" -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -I$tc/x86compat"
link="-static -L$tc/libcase"

cmake -S "$src/infamous-recomp" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$repo/cmake/aarch64-w64-mingw32.cmake" \
    -DIF_TOOLCHAIN="$tc" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" \
    -DCMAKE_EXE_LINKER_FLAGS="$link" \
    -DCMAKE_C_COMPILER_LAUNCHER="$repo/scripts/cc-launcher.sh" \
    -DCMAKE_CXX_COMPILER_LAUNCHER="$repo/scripts/cc-launcher.sh" \
    -DPORT_SPU_AVX2=OFF -DPORT_PPU_AVX2=OFF -DPORT_CPU_AUTO=OFF -DPORT_CPU_CHECK=OFF \
    -DPORT_PPU_REGCACHE="${IF_PPU_REGCACHE:-ON}" -DPORT_PPU_MEMLEAN=ALL \
    -DPORT_REQUIRE_SDL3=ON \
    -DRECOMP_DIR="$recomp" \
    -DPS3RECOMP_DIR="$src/ps3recomp" \
    -DPython3_EXECUTABLE="$(command -v python3)"

# shellcheck disable=SC2086
ninja -C "$build" -j "$(build_jobs)" ${IF_TARGETS:-}
[ -n "${IF_TARGETS:-}" ] || check_arm64_pe "$build/inFamousRecomp.exe"
