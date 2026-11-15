#!/usr/bin/env python3
"""Writes DIST/infamous.sh, the script Steam starts: it sets inFAMOUS Reborn's launch settings
(installer/infamous.toml [launch] env, then config/rp6.env), finds Steam's ARM64 Proton and runs
inFamousRecomp.exe with it in its own prefix (DIST/prefix).

    scripts/write-launch.py SRC DIST GAME

SRC is the prepared checkout, DIST the install folder, GAME the game folder (with PS3_GAME).
"""
import shlex
import sys
import tomllib
from pathlib import Path

repo = Path(__file__).resolve().parent.parent


def winpath(p: Path) -> str:
    return "Z:" + str(p).replace("/", "\\")


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    src, dist, game = (Path(a).resolve() for a in argv[1:])
    manifest = tomllib.loads((src / "installer" / "infamous.toml").read_text(encoding="utf-8"))
    launch = manifest["launch"]
    env = dict(launch.get("env", {}))
    for line in (repo / "config" / "rp6.env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    port = src / manifest["layout"]["port"]
    exe = port / "build-arm64" / "inFamousRecomp.exe"
    elf = game / "PS3_GAME" / "USRDIR" / "EBOOT.elf"
    q = shlex.quote
    lines = [
        "#!/usr/bin/env bash",
        "# Starts inFAMOUS Reborn with Steam's ARM64 Proton. Written by scripts/write-launch.py: rebuilding",
        "# replaces it. Your own settings go in the game's pause menu > Settings, or in infamous.env here",
        "# (KEY=VALUE lines, read last).",
        f"dist={q(str(dist))}",
        f"port={q(str(port))}",
        f"exe={q(str(exe))}",
        f"elf={q(winpath(elf))}",
        "",
        "# IF_PROTON (a Proton folder or its proton script) wins. Otherwise a Proton with ARM64 Windows",
        "# libraries: Proton Experimental first, then GE-Proton, then any other. Proton 11.0 (ARM64) does not",
        "# start ARM64 programs (error 53), so it comes last.",
        "find_proton() {",
        '    if [ -n "${IF_PROTON:-}" ]; then echo "$IF_PROTON"; return; fi',
        "    local p name rank best= best_rank=9",
        '    for p in "$HOME"/.local/share/Steam/steamapps/common/Proton* "$HOME"/.steam/steam/steamapps/common/Proton* \\',
        '             "$HOME"/.local/share/Steam/compatibilitytools.d/* "$HOME"/.steam/steam/compatibilitytools.d/*; do',
        '        [ -x "$p/proton" ] && [ -d "$p/files/lib/wine/aarch64-windows" ] || continue',
        "        name=${p##*/}",
        '        case "$name" in',
        "            *Experimental*) rank=0 ;;",
        "            GE-Proton*) rank=1 ;;",
        '            "Proton 11.0"*) rank=3 ;;',
        "            *) rank=2 ;;",
        "        esac",
        '        if [ "$rank" -lt "$best_rank" ] || { [ "$rank" -eq "$best_rank" ] && [[ "$name" > "${best##*/}" ]]; }; then',
        "            best=$p best_rank=$rank",
        "        fi",
        "    done",
        '    echo "$best"',
        "}",
        "proton_dir=$(find_proton)",
        '[ -n "$proton_dir" ] || { echo "No ARM64 Proton found: install Proton from Steam (or set IF_PROTON)" >&2; exit 1; }',
        '[ -d "$proton_dir" ] && proton=$proton_dir/proton || { proton=$proton_dir; proton_dir=$(dirname "$proton"); }',
        "",
    ]
    lines += [f"export {k}={q(str(v))}" for k, v in env.items()]
    lines += [
        '[ -f "$dist/infamous.env" ] && set -a && . "$dist/infamous.env" && set +a',
        "",
        'export STEAM_COMPAT_DATA_PATH="$dist/prefix"',
        'mkdir -p "$STEAM_COMPAT_DATA_PATH"',
        'if [ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" ]; then',
        '    for s in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do',
        '        [ -d "$s/steamapps" ] && { export STEAM_COMPAT_CLIENT_INSTALL_PATH="$s"; break; }',
        "    done",
        "fi",
        "",
        "# A new Proton prefix can fail the first program it starts while it is still being set up, so set",
        "# it up with a no-op first (build.sh does this once with --init-prefix).",
        'init_prefix() {',
        '    local try',
        '    for try in 1 2; do',
        '        [ -f "$STEAM_COMPAT_DATA_PATH/pfx/system.reg" ] && [ -f "$STEAM_COMPAT_DATA_PATH/version" ] && return 0',
        '        echo "Setting up the Proton prefix (attempt $try)" >&2',
        '        "$proton" run cmd.exe /c exit 0 >/dev/null 2>&1',
        "    done",
        '    [ -f "$STEAM_COMPAT_DATA_PATH/pfx/system.reg" ]',
        "}",
        'if [ "${1:-}" = --init-prefix ]; then init_prefix; exit; fi',
        'init_prefix || echo "Warning: the Proton prefix in $STEAM_COMPAT_DATA_PATH is not set up; trying anyway" >&2',
        "",
        'cd "$port" || exit 1',
        'echo "inFAMOUS Reborn with $(basename "$proton_dir")" >&2',
        "# Proton starts the game without std handles: the game opens its own logs (PORT_STDOUT/PORT_STDERR,",
        "# upstream's play.out.log/play.err.log) and Proton's own output goes to proton.log.",
        f"export PORT_STDOUT={q(winpath(port / launch.get('stdout', 'play.out.log')))}",
        f"export PORT_STDERR={q(winpath(port / launch.get('stderr', 'play.err.log')))}",
        '"$proton" waitforexitandrun "$exe" "$elf" > proton.log 2>&1',
        "rc=$?",
        '[ "$rc" != 53 ] || echo "$(basename "$proton_dir") could not start inFAMOUS (error 53): install Proton Experimental (ARM64) or GE-Proton aarch64, or set IF_PROTON in $dist/infamous.env" >&2',
        'exit "$rc"',
        "",
    ]
    out = dist / "infamous.sh"
    out.write_text("\n".join(lines), encoding="utf-8")
    out.chmod(0o755)
    print(f"Wrote {out} ({len(env)} launch settings)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
