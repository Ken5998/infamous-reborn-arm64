# inFAMOUS Reborn on ARM64

Work in progress: [inFAMOUS Reborn](https://github.com/whompay/inFAMOUSreborn), the static
recompilation of the PlayStation 3 version of inFamous, on ARM64 handhelds like the Retroid
Pocket 6 with ArmadaOS.

The plan is a launcher that builds the game on the device from your own disc (European release,
`BCES00220`) as a Windows ARM64 program and runs it natively with Steam's ARM64 Proton, with
Direct3D 12 through vkd3d-proton on Turnip. No game code or data is stored here.

## Trying the build (preview)

There is no launcher yet. On the handheld, in Desktop Mode, open a terminal:

```sh
git clone https://github.com/Ken5998/infamous-reborn-arm64
cd infamous-reborn-arm64
bash scripts/build.sh ~/path/to/inFAMOUS.iso
```

You need:

- your own inFamous disc image, European release `BCES00220` (an encrypted 1:1 dump works with its
  `.dkey` file next to it, with the same name);
- Proton Experimental (ARM64) or GE-Proton aarch64 in Steam (Proton 11.0 (ARM64) does not start
  ARM64 programs);
- about 15 GB free and a few hours with the handheld plugged in. The script keeps it awake, skips
  finished steps when run again and writes everything to
  `~/.local/share/inFAMOUSReborn-arm64/build.log`.

When it is done, inFAMOUS is in the Steam library. Start it from there, so the controls work.

`tools/probe` checks a device first (Proton, memory, Direct3D 12) without the game.

See [NOTICE](NOTICE) for credits and licences.
