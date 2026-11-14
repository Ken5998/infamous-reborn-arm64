# Shared by the build scripts (sourced). Needs $repo (this checkout).

# The Windows ARM64 build targets ARMv8.2 (every handheld this is for: SD865 and newer) with the
# CRC and crypto extensions, which sse2neon uses for the SSE4.2 CRC32 and AES intrinsics.
IF_ARCH_FLAGS="-march=armv8.2-a+crc+crypto+dotprod"

step() { printf '\n==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
key() { cat "$@" | sha256sum | cut -d' ' -f1; }   # key FILE...: a hash of their contents
field() {  # field KEY... : a value from upstream.json
    python3 -c 'import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]: v = v[k]
print(v)' "$repo/upstream.json" "$@"
}
fetch() {  # fetch URL SHA256 FILE: download once, verified
    local url=$1 sum=$2 out=$3
    if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$sum" ]; then return 0; fi
    mkdir -p "$(dirname "$out")"
    curl -fL --retry 3 --connect-timeout 30 -o "$out.part" "$url"
    [ "$(sha256sum "$out.part" | cut -d' ' -f1)" = "$sum" ] ||
        { echo "error: $url does not match its hash in upstream.json" >&2; rm -f "$out.part"; exit 1; }
    mv "$out.part" "$out"
}

build_jobs() {  # IF_JOBS, else one per CPU thread, at most one per 3 GB of memory (lifted PPU files are big)
    if [ -n "${IF_JOBS:-}" ]; then echo "$IF_JOBS"; return; fi
    local mem_gb jobs
    mem_gb=$(( $(sed -n 's/^MemTotal: *\([0-9]*\) kB/\1/p' /proc/meminfo) / 1048576 ))
    jobs=$(( mem_gb / 3 ))
    [ "$jobs" -le "$(nproc)" ] || jobs="$(nproc)"
    [ "$jobs" -ge 1 ] || jobs=1
    echo "$jobs"
}

check_arm64_pe() {  # a PE file for ARM64 (machine 0xAA64)
    [ -f "$1" ] || { echo "error: $1 was not built" >&2; exit 1; }
    python3 - "$1" <<'PY' || { echo "error: $1 is not a Windows ARM64 program" >&2; exit 1; }
import struct, sys
b = open(sys.argv[1], 'rb').read(4096)
pe = struct.unpack_from('<I', b, 0x3C)[0]
assert b[pe:pe + 4] == b'PE\0\0' and struct.unpack_from('<H', b, pe + 4)[0] == 0xAA64
PY
    echo "OK $1 (Windows ARM64)"
}
