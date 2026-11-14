#!/usr/bin/env bash
# Runs infamous-probe.exe (and the ARM64EC build of it) with every ARM64 Proton Steam has installed and
# writes one report: infamous-probe-report.txt next to this script. Paste that file in the thread.
# Run it in Desktop Mode (Konsole) with Steam closed or open, it does not matter.
set -u
here=$(cd "$(dirname "$0")" && pwd)
report="$here/infamous-probe-report.txt"
exec > >(tee "$report") 2>&1

echo "== infamous-probe report $(date -u '+%F %T UTC')"
echo "== system"
uname -a
grep -m1 -E '^PRETTY_NAME' /etc/os-release 2>/dev/null
free -m | sed -n 1,2p
nproc
grep -m1 -i 'model name\|^CPU part' /proc/cpuinfo 2>/dev/null
command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName|driverInfo|apiVersion' | head -8

steam_roots=()
for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
    [ -d "$d/steamapps" ] && steam_roots+=("$(readlink -f "$d")")
done
mapfile -t steam_roots < <(printf '%s\n' "${steam_roots[@]}" | sort -u)
client="${steam_roots[0]:-$HOME/.local/share/Steam}"

echo "== Proton builds"
protons=()
for r in "${steam_roots[@]}"; do
    for p in "$r"/steamapps/common/Proton* "$r"/compatibilitytools.d/*; do
        [ -x "$p/proton" ] || continue
        lib="$p/files/lib/wine"
        archs=$(ls -d "$lib"/*-windows 2>/dev/null | xargs -rn1 basename | tr '\n' ' ')
        echo "-- $p"
        echo "   wine PE dirs: ${archs:-none}"
        for sub in dxvk vkd3d-proton; do
            [ -d "$lib/$sub" ] && echo "   $sub: $(ls "$lib/$sub" | tr '\n' ' ')"
        done
        [ -f "$p/version" ] && echo "   version: $(cat "$p/version")"
        case "$archs" in *aarch64-windows*|*arm64ec-windows*) protons+=("$p") ;; esac
    done
done
[ ${#protons[@]} -gt 0 ] || { echo "No ARM64 Proton found (no aarch64-windows folder in any Proton)."; exit 1; }

for p in "${protons[@]}"; do
    name=$(basename "$p" | tr ' ' '_')
    pfx="$HOME/.local/share/infamous-probe/pfx-$name"
    mkdir -p "$pfx"
    for exe in infamous-probe.exe infamous-probe-arm64ec.exe; do
        [ -f "$here/$exe" ] || continue
        echo "== $exe with $(basename "$p")"
        rm -f "$here/infamous-probe.log"
        ( cd "$here" && STEAM_COMPAT_CLIENT_INSTALL_PATH="$client" STEAM_COMPAT_DATA_PATH="$pfx" \
              PROTON_LOG=1 PROTON_LOG_DIR="$here" timeout 180 "$p/proton" run "$here/$exe" ) > "$here/run.out" 2>&1
        echo "exit code $?"
        if [ -f "$here/infamous-probe.log" ]; then cat "$here/infamous-probe.log"
        else echo "(no infamous-probe.log: the exe did not start)"; tail -n 40 "$here/run.out"; fi
        log=$(ls -t "$here"/steam-*.log 2>/dev/null | head -1)
        if [ -n "$log" ]; then
            echo "-- Proton log, interesting lines"
            grep -aiE 'err:|fixme:d3d12|vkd3d|dxvk|c0000135|c000007b|Could not load|not found|aarch64|arm64' "$log" | grep -av 'fixme:ntdll' | head -n 40
            rm -f "$log"
        fi
    done
done
echo "== end (report saved to $report)"
