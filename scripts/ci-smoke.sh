#!/usr/bin/env bash
# CI without the game: builds the ps3recomp runtime and every hand-written source of inFAMOUS
# Reborn for Windows ARM64 against ps3recomp's synthetic "smoke" title instead of the lifted
# game, then links them, allowing only the symbols that the generated game code defines.
#
#   scripts/ci-smoke.sh SRC TOOLCHAIN
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/scripts/common.sh"
src="$(cd "$1" && pwd)"
tc="$(cd "$2" && pwd)"
fake="$src/.ci-recompiled"
build="$src/infamous-recomp/build-arm64"

rm -rf "$fake" && mkdir -p "$fake"
python3 -I "$src/ps3recomp/tools/make_smoke_elf.py" --header "$fake/ppu_recomp.h"
# the game's patched ppu_recomp.h defines this; the smoke header does not
sed -i 's/^#pragma once$/#pragma once\n#define PPU_INJECT_BASE_C 0x20000000u/' "$fake/ppu_recomp.h"
cp "$src/ps3recomp/runtime/ppu/tests/smoke/smoke_recomp.c" "$fake/"

IF_PPU_REGCACHE=OFF IF_TARGETS=ps3recomp_runtime "$repo/scripts/build-game.sh" "$src" "$tc" "$fake"
# trainer.cpp calls lifted game functions by name: it only compiles against the real lifted code
mapfile -t objs < <(ninja -C "$build" -t targets all | sed -n 's/^\(CMakeFiles\/inFamousRecomp\.dir\/[^:]*\.obj\):.*/\1/p' | grep -v '/trainer\.cpp\.obj$')
echo "Compiling ${#objs[@]} game sources"
ninja -C "$build" -j "$(build_jobs)" "${objs[@]}"

m="$tc/llvm-mingw/bin"
"$m/aarch64-w64-mingw32-clang++" -o "$build/smoke-link.exe" "${objs[@]/#/$build/}" "$build/ps3recomp_sdk/libps3recomp_runtime.a" \
    -static -L"$tc/libcase" -ldbghelp -luser32 -lgdi32 -lwinmm -ldxguid -lws2_32 -lxinput -lole32 -lbcrypt \
    -ladvapi32 -lshell32 -luuid -lcomdlg32 -Wl,-Xlink=/force:unresolved > "$build/smoke-link.log" 2>&1 || {
    cat "$build/smoke-link.log"; exit 1; }
sed -n 's/.*undefined symbol: //p' "$build/smoke-link.log" | sort -u > "$build/smoke-unresolved.txt"
# defined by the generated code: lifted functions, the trainer, SPU plugin table, LOD hooks
bad=$(grep -vE '^(func_[0-9A-Fa-f]+|infamous_trainer_[a-z_]+|spu_plug_lookup|g_lodx_[a-z_]+)$' "$build/smoke-unresolved.txt" || true)
if [ -n "$bad" ]; then
    echo "error: symbols missing from the Windows ARM64 build that the game code does not provide:" >&2
    echo "$bad" >&2
    exit 1
fi
check_arm64_pe "$build/smoke-link.exe"
echo "Imports:"
"$m/llvm-objdump" -p "$build/smoke-link.exe" | sed -n 's/.*DLL Name: //p' | grep -vi '^api-ms-win-crt' | sort -f | tr '\n' ' '
echo
echo "Smoke build OK ($(wc -l < "$build/smoke-unresolved.txt") generated-code symbols left unresolved, as expected)"
