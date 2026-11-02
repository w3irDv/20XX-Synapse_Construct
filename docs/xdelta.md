# Synapse xdelta patches (Full package)

`synapse-xdelta-<version>.zip` (on the [Releases](https://github.com/w3irDv/20XX-Synapse_Engine/releases) page)
turns a Melee ISO you already have into the **Synapse Full** build, with nothing to install. A script recognises your
ISO, asks which build you want, applies the patch with the bundled `xdelta3` and checks the result. Your ISO is never
changed; the new one is written next to it.

The patches only work on the exact ISOs below. For anything else (another version of a mod, or a mod you added
stages or characters to) use the [Synapse Builder](builder.md): it reads the ISO itself and handles any eligible mod.

## Supported ISOs

Each one exactly as its mod distributes it (the mod's own patch applied to a clean Melee NTSC 1.02):

| ISO | MD5 | Where it comes from |
|---|---|---|
| Melee NTSC 1.02 (vanilla) | `0e63d4223b01d9aba596259dc155a174` | your own dump of the game |
| hybrid.64 v3.2 (Slippi build) | `4010968baa7197dc58c2ba337f3bdc2c` | hybrid.64's `PATCH_Slippi.xdelta` |
| hybrid.64 v3.2 (vanilla build) | `736609b48086cb33476cf627cb24f427` | hybrid.64's `PATCH_vanilla.xdelta` |
| Silly Melee v1.01 | `4c2d0559365533b252cad8caf406a94e` | `Silly Melee v1.01 GALE01.xdelta` |
| SSBM ACE v2.0.0 | `1f4a4faeb35f486c7d56b467b20cc54c` | ACE's v2.0 patcher |
| SSBM ACE v2.0.1 | `436b346bc5e698909cb50953032c22ce` | ACE's v2.0.1 builder |
| Akaneia v1.0.1 | `8252729b0d37999fcb39534f68010d80` | the Akaneia 1.0.1 builder |

Not supported: 20XX, compressed images (`.rvz`, `.nkit.iso`, `.ciso`, `.wbfs`: in Dolphin, right-click the game >
**Convert File…** > **ISO** first), and an ISO that already has Synapse (the script says so).

## The two builds

| Choice | For | Output |
|---|---|---|
| **1) Dolphin or a console, any screen** (default) | Dolphin, a GameCube, or a Wii on a CRT | `<name>.full.iso` |
| **2) Wii on a flat screen** | a real Wii on an LCD / flat screen: adds **Force 480p** and tauKhan's **Polling Drift + Full Visual Buffer fix** (removes polling drift and one frame of visual lag); both always on | `<name>.full.wii-non-crt.iso` |

What the Full package contains and how to use it in game: the [front page](../README.md) and [CONTROLS](CONTROLS.md).

## Windows

1. Extract the whole zip.
2. Drag your ISO onto **`windows\Synapse-Patch.bat`**. Or double-click it, drag the ISO into the window and press
   Enter.
3. Answer 1 or 2 (Enter = 1). Wait for **Done**, then press a key.

If SmartScreen says "Windows protected your PC": **More info** > **Run anyway**. From a command prompt:

```bat
windows\Synapse-Patch.bat -WiiNonCrt "D:\isos\hybrid.64.iso"
```

## Linux

x86-64 with glibc 2.34 or newer (Ubuntu 22.04, Debian 12, Fedora 35, SteamOS 3 or later). Extract the zip, then in a
terminal:

```bash
cd synapse-xdelta-<version>/linux
./synapse-patch.sh /path/to/your.iso
```

Or run `./synapse-patch.sh` alone and drag the ISO into the terminal. If the bundled `xdelta3` can't run on your
system, install `xdelta3` from your package manager (`sudo apt install xdelta3`); the script then uses it.

## macOS

Tested on macOS 14 on an Apple silicon Mac. The Intel binary is included but hasn't been run on an Intel Mac.

Double-click **`macos/Synapse-Patch.command`** and choose your ISO. The first time, macOS shows a warning and doesn't
open it (the files aren't signed): right-click it > **Open** > **Open**. If macOS still refuses it (likely on macOS 15 or later),
run `xattr -dr com.apple.quarantine <the extracted folder>` in Terminal once, then double-click it again. The script removes the download quarantine from its own
`xdelta3` and picks the Apple silicon or Intel binary. From Terminal: `cd macos` then
`sh synapse-patch.sh /path/to/your.iso`.

## Options

| Windows | Linux / macOS | Effect |
|---|---|---|
| `-Full` | `--full` | build 1, no question |
| `-WiiNonCrt` | `--wii-non-crt` | build 2, no question |
| `-Force` | `--force` | overwrite an existing output ISO |

Exit codes: `0` done · `1` usage or cancelled · `2` release files missing or ISO unreadable · `3` ISO not supported
(unknown, compressed, or already Synapse) · `4` output already exists, or not enough disk space · `5` `xdelta3` failed,
or the result isn't the expected one (it is then deleted).

## Troubleshooting

| Message | What to do |
|---|---|
| "This ISO isn't one the patches support" | Check its MD5 against the table above. A different MD5 means another version or a modified copy: re-apply the mod's own patch to a clean 1.02, or use the Synapse Builder |
| "already a Synapse build" | Patch the original ISO, not the output |
| "compressed disc image" | Convert it to ISO in Dolphin first |
| "xdelta3 failed" / "not the expected one" | The zip is damaged or incomplete: download and extract it again (check it with `SHA256SUMS.txt`) |
| "Not enough free space" | The output is as big as the ISO (0.6–1.7 GB) |
| Linux: "xdelta3 can't run on this system" | Install `xdelta3` with your package manager |

The patch never contains any part of the mods themselves: it only holds the bytes Synapse adds or moves, which is why
each one is a few tens of KB.
