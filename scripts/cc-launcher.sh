#!/usr/bin/env bash
# Compiler launcher for the Windows ARM64 build (CMAKE_<LANG>_COMPILER_LAUNCHER).
# inFAMOUS Reborn's CMake files add x86 code generation flags in many places (-msse4.1, -mavx2, ...).
# NEON is part of the ARM64 base ISA, so they are simply dropped here instead of patching every site.
cc=$1; shift
args=()
for a in "$@"; do
    case "$a" in
        -msse*|-mssse3|-mavx*|-mfma|-mbmi|-mbmi2|-mlzcnt|-mmovbe|-mpopcnt|-mf16c|-mpclmul|-maes|-mtune=*|-march=x86-64*|-march=haswell|-march=native) ;;
        *) args+=("$a") ;;
    esac
done
exec "$cc" "${args[@]}"
