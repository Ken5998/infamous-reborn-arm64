#!/usr/bin/env bash
# Builds inFAMOUS Reborn for the handheld from your own inFamous disc (PS3, European release
# BCES00220), start to finish: the Windows ARM64 toolchain, inFAMOUS Reborn with this repository's
# patches, the game files from the disc, the decrypted executable, the recompiled code, the game,
# and an entry in Steam that runs it with Steam's ARM64 Proton. Made for the handheld itself
# (ArmadaOS on the Retroid Pocket 6, or any aarch64 Linux with Steam). IF_ADD_TO_STEAM=0 leaves
# Steam alone.
#
#   scripts/build.sh SOURCE [DIR]
#
# SOURCE  your disc image (.iso; an encrypted 1:1 dump needs its .dkey next to it), or the game
#         folder that holds PS3_GAME, or - to reuse the game files an earlier build copied
# DIR     where everything goes (default ~/.local/share/inFAMOUSReborn-arm64); about 15 GB free
#         is needed while building
#
# The executable on the disc (EBOOT.BIN) is encrypted; if the game folder has no decrypted
# EBOOT.elf next to it, RPCS3 (its aarch64 AppImage, downloaded once) decrypts it.
#
# Run it again after updating this repository: finished steps are skipped when nothing they depend
# on changed, and the game build recompiles only the files a change touches. Nothing made here may
# be published (it is built from your copy of the game).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/scripts/common.sh"
[ $# -ge 1 ] && { [ "$1" = - ] || [ -e "$1" ]; } || { echo "usage: $0 ISO|GAME_DIR|- [DIR]" >&2; exit 2; }
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "error: build on the handheld (aarch64 Linux)" >&2; exit 1 ;;
esac
source_arg="$1"
[ "$source_arg" = - ] || source_arg="$(cd "$(dirname "$source_arg")" && pwd)/$(basename "$source_arg")"
dir="${2:-$HOME/.local/share/inFAMOUSReborn-arm64}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

# The build takes hours: keep the handheld awake while it runs and keep a log (build.log) to share.
if [ -z "${IF_BUILD_CHILD:-}" ]; then
    export IF_BUILD_CHILD=1
    echo "Log: $dir/build.log"
    if command -v systemd-inhibit >/dev/null &&
        systemd-inhibit --what=sleep:idle --who=inFAMOUS --why=check true 2>/dev/null; then
        systemd-inhibit --what=sleep:idle --who="inFAMOUS Reborn build" --why="Building the game" \
            "$0" "$@" 2>&1 | tee "$dir/build.log"
    else
        "$0" "$@" 2>&1 | tee "$dir/build.log"
    fi
    exit "${PIPESTATUS[0]}"
fi
tc="$dir/toolchain"
src="$dir/inFAMOUSreborn"
tools="$dir/tools"
stamps="$dir/.stamps"
mkdir -p "$stamps" "$tools"
done_with() { [ -f "$stamps/$1" ] && [ "$(cat "$stamps/$1")" = "$2" ]; }
mark() { echo "$2" > "$stamps/$1"; }

for t in git python3 curl tar xz; do
    command -v "$t" >/dev/null || { echo "error: $t is missing" >&2; exit 1; }
done

step "Toolchain"
"$repo/scripts/fetch-toolchain.sh" "$tc"
export PATH="$tc/bin:$PATH"

prepare_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" "$repo"/patches/upstream/*.patch)"
if done_with prepare "$prepare_key" && [ -d "$src/.git" ]; then
    echo "inFAMOUS Reborn already prepared - skipping."
else
    step "inFAMOUS Reborn and this repository's patches"
    "$repo/scripts/prepare.sh" "$dir"
    mark prepare "$prepare_key"
fi

# inFAMOUS Reborn's own installer (MIT) reads the disc and regenerates the code: built from the
# pinned checkout with cargo when there is one, else the build this repository's CI made of it.
tag="$(installer_tag)"
inst="$tools/infamous-$tag"
if [ ! -x "$inst" ]; then
    step "inFAMOUS Reborn's installer"
    if command -v cargo >/dev/null; then
        (cd "$src/installer" && cargo build --release --locked --no-default-features --bin infamous-installer)
        cp "$src/installer/target/release/infamous-installer" "$inst.part"
    else
        curl -fL --retry 3 -o "$inst.part" \
            "https://github.com/Ken5998/infamous-reborn-arm64/releases/download/$tag/infamous-installer-linux-arm64"
    fi
    chmod +x "$inst.part" && mv "$inst.part" "$inst"
fi

game="$dir/game"
if [ "$source_arg" = - ]; then
    [ -d "$game/PS3_GAME" ] || { echo "error: no game files in $game yet: give your disc image or game folder" >&2; exit 1; }
elif [ -d "$source_arg" ]; then
    [ -d "$source_arg/PS3_GAME" ] || { echo "error: $source_arg has no PS3_GAME folder" >&2; exit 1; }
    game="$source_arg"
else
    iso_key="$source_arg $(stat -c '%s %Y' "$source_arg")"
    if [ -d "$game/PS3_GAME" ] && done_with extract "$iso_key"; then
        echo "Game files already copied from the disc image - skipping."
    else
        step "Copying the game files from $source_arg (a few minutes)"
        rm -rf "$game"
        "$inst" extract-iso --iso "$source_arg" --out "$game"
        [ -d "$game/PS3_GAME" ] || { echo "error: the image has no PS3_GAME folder - is it a PS3 game disc?" >&2; exit 1; }
        mark extract "$iso_key"
    fi
fi

rpcs3_args=()
if [ ! -f "$game/PS3_GAME/USRDIR/EBOOT.elf" ]; then
    step "RPCS3, to decrypt the game's executable"
    rp="$tools/rpcs3"
    if [ ! -x "$rp/squashfs-root/AppRun" ]; then
        info="$(curl -fsSL "$(field rpcs3 api)")"
        url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["latest_build"]["linux"]["download"])' "$info")"
        sum="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["latest_build"]["linux"]["checksum"].lower())' "$info")"
        mkdir -p "$rp"
        curl -fL --retry 3 -o "$rp/rpcs3.AppImage" "$url"
        [ "$(sha256sum "$rp/rpcs3.AppImage" | cut -d' ' -f1)" = "$sum" ] || { echo "error: the RPCS3 download is damaged" >&2; exit 1; }
        chmod +x "$rp/rpcs3.AppImage"
        (cd "$rp" && ./rpcs3.AppImage --appimage-extract >/dev/null && rm -f rpcs3.AppImage)
    fi
    cat > "$rp/rpcs3" <<SH
#!/bin/sh
# RPCS3 without a window, for --decrypt
QT_QPA_PLATFORM=offscreen exec "$rp/squashfs-root/AppRun" "\$@"
SH
    chmod +x "$rp/rpcs3"
    rpcs3_args=(--rpcs3 "$rp/rpcs3")
fi

regen_key="$prepare_key $(key "$inst") $(stat -c '%s %Y' "$game/PS3_GAME/USRDIR/EBOOT.BIN")"
if done_with regen "$regen_key"; then
    echo "Game code already regenerated - skipping."
else
    step "Regenerating the game code from your disc (an hour or more on a handheld)"
    "$inst" install --root "$src" --game "$game" --python python3 --jobs "$(nproc)" --no-build -y "${rpcs3_args[@]}"
    mark regen "$regen_key"
fi

step "Building inFAMOUS for Windows ARM64 (hours on a handheld)"
"$repo/scripts/build-game.sh" "$src" "$tc"

step "Putting the game together"
build="$src/infamous-recomp/build-arm64"
sdl="$tools/sdl3-$(field sdl3 sha256 | cut -c1-12).zip"
fetch "$(field sdl3 url)" "$(field sdl3 sha256)" "$sdl"
python3 -c 'import sys, zipfile; open(sys.argv[3], "wb").write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' \
    "$sdl" "$(field sdl3 dll)" "$build/SDL3.dll"
python3 -I "$repo/scripts/write-launch.py" "$src" "$dir" "$game"
step "Setting up Proton for inFAMOUS"
"$dir/infamous.sh" --init-prefix || echo "Warning: Proton could not set up its prefix yet; the first start tries again."

steam=no
if [ "${IF_ADD_TO_STEAM:-1}" = 1 ]; then
    step "Adding inFAMOUS to Steam"
    if python3 -I "$repo/scripts/add-to-steam.py" "$dir"; then
        steam=yes
    else
        echo "Warning: inFAMOUS was not added to Steam; scripts/add-to-steam.py tries again."
    fi
fi

echo
echo "Done at $(date +%H:%M:%S)! inFAMOUS is in $dir."
if [ "$steam" = yes ]; then
    echo "Play it from Steam (\"inFAMOUS\" in the library): the handheld's controls reach it only from there."
else
    echo "Play it from Steam (scripts/add-to-steam.py adds it) so the controls work, or run $dir/infamous.sh."
fi
