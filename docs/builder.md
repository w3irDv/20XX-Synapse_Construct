# Synapse Builder

The Synapse Builder takes a Super Smash Bros. Melee **NTSC 1.02** ISO, vanilla or a mod built on it, and writes a
new ISO that runs the **Synapse CPU AI**. It is one program per operating system, with nothing to install: everything
it needs is inside it. Your original ISO is never changed, and no ISO is ever included.

It comes as two executables that do the same job:

- **`synapse-gui`**: a window. Pick an ISO, pick a package, press **Build**.
- **`synapse-cli`**: the same from a terminal, for scripts and for adding a tested ISO (see "Adding a tested ISO on this
  machine").

The in-match controls (CPU selector, CPU config menu) are explained in [`CONTROLS.md`](CONTROLS.md)
How the builder judges an ISO (which ISOs can be used, untested ISOs, added content, checking a built ISO, exit
codes): [`BUILD_DETAILS.md`](BUILD_DETAILS.md).
In the download both files are next to this one.

## The two packages

| Package | What the ISO gets | Output name |
|---|---|---|
| **AI-only** (default) | the Synapse AI engine, the CPU config menu (**Z + D-Up**), the CPU-type selector (D-pad), the DI / SDI / tech / Nana reactions, and the 20XX CPU rules (CPUs L-cancel, never taunt, Captain Falcon never rapid-jabs, Sheik / Zelda never transform; each switchable in the menu). On Akaneia / ACE also a fix for a CPU crash with added fighters | `<name>.aionly.iso` |
| **Full** | everything in AI-only, plus the **GLOBAL CONFIGURATION** menu and every community feature baked in, each switched on or off **in game** (options saved to the memory card): UCF 0.84, Flash Red on a failed L-cancel, Z-Jump (P1 / P2), true widescreen, the Arcade Melee camera, hitbox display, random stage music, CSS Stars, the character and stage random pools; on m-ex the stage select also reopens on its last page. Each base keeps what it already has (for example Akaneia / ACE keep their own UCF) | `<name>.full.iso` |
| **Full, real Wii on an LCD / flat screen** | Full plus **Force 480p** (boots straight into 480p) and **Polling-Drift** (removes polling drift and one frame of visual lag). Only for a real Wii on a non-CRT screen: on Dolphin or a CRT use plain Full. These two can't be switched off in game | `<name>.full.wii-non-crt.iso` |

## Supported ISOs

Start from your copy **without** Synapse: an ISO this builder already built is refused. 20XX is not supported (it
already has the 20XX AI).

| Base | AI-only | Full |
|---|---|---|
| vanilla Melee NTSC 1.02 | yes | yes |
| hybrid.64 v3.2 (Slippi build, or the vanilla build with game ID `GHME01`) | yes | yes, from the exact ISO this release lists |
| Akaneia, SSBM ACE v2.0.0, SSBM Custom Stages Expansion 0.91, SSBM ULTRA v2.4 CSE 0.91, Arcade Melee Demo 2.0 | yes | yes |
| Silly Melee | yes | yes, from the exact ISO this release lists (Silly keeps its own widescreen, flash and music, so those menu rows are hidden) |
| another GALE01 1.02 mod | if it passes every compatibility check, after you confirm (see "ISOs this release hasn't been tested with") | the same, when the mod is vanilla-like or m-ex |

Compressed images (`.nkit.iso`, `.rvz`, `.ciso`, `.wbfs`) must first be converted to a plain ISO with Dolphin
(right-click the game → Convert File… → ISO). The output needs about the size of the ISO in free disk space
(0.5–1.7 GB).

## Using the window (synapse-gui)

1. **Source ISO**: press **Browse…**, or type / paste the path, or drop the ISO onto the window.
2. **Package**: **AI-only** or **Full**. With Full, tick **Real Wii on an LCD / flat screen** only for that setup.
3. **Output folder** (optional): where the new ISO goes; empty = next to the source. The **Output ISO** line shows the
   full name it will get.
4. **Check** runs every check and writes nothing; **Build** checks and builds. The log below shows one `[PASS]` /
   `[FAIL]` / `[INFO]` line per check (technical, useful when you ask for help). The result shows in **green** (done) or
   **red** (stopped), and the lines starting with **»** say in ordinary language what happened and what to do next:
   read those first.
5. If the output already exists, the builder asks **Replace?**. If the ISO isn't one this release was tested with but
   passes every check, it asks whether to build it anyway (see below).
6. **Check built ISO…** checks an ISO this builder made earlier, for example after you added content to it. It writes
   nothing.

The window remembers the last folders you used.

## Using the console (synapse-cli)

```text
synapse-cli build <source.iso> [--full [--wii-non-crt]] [--out <iso>] [--profile <p>]
                  [--allow-unknown-base] [--check-only] [--force]
synapse-cli check-built <iso>
synapse-cli add-known-base <original.iso> --built <built.iso> [--profile <p>]
synapse-cli --version
```

| Option | Meaning |
|---|---|
| `--full` | the Full package; default AI-only |
| `--wii-non-crt` | with `--full`: the real-Wii-on-a-flat-screen variant |
| `--out <iso>` | the output ISO; default next to the source, named as in "The two packages" |
| `--profile <p>` | for an untested ISO only: force the kind of base instead of the guess (AI-only: `vanilla`, `hybrid64`, `mex`; Full: `vanilla`, `mex`). Contradicting a recognised ISO is refused |
| `--allow-unknown-base` | build an untested but compatible ISO without asking (for scripts); boot-test the result |
| `--check-only` | run every check and show the plan; write nothing |
| `--force` | replace an existing output |

Run without arguments, it prints this list and the folder where it keeps this machine's own additions.

Examples:

```text
synapse-cli build "D:\Games\Melee.iso"                            -> D:\Games\Melee.aionly.iso
synapse-cli build "D:\Games\SSBM ACE Build v2.0.0.iso" --full     -> ...\SSBM ACE Build v2.0.0.full.iso
synapse-cli build ~/games/melee.iso --full --wii-non-crt --out ~/wii/melee.iso
synapse-cli build "D:\Games\some mod.iso" --check-only            is it supported? (writes nothing)
synapse-cli check-built "D:\Games\Melee.aionly.iso"               re-check after adding content
```

### Exit codes

The exit codes are the same for every front end: [`BUILD_DETAILS.md` 6](BUILD_DETAILS.md#6-exit-codes).

## Boot check

In Dolphin (closest to a console: Config → Advanced → enable MMU, disable Fastmem):

1. VS mode, set a CPU to type 4 (any level): it attacks and wavedashes.
2. Hold **Z** and press **D-Up**: the CPU config menu opens. Z + D-Left / D-Right changes the CPU type (a message shows
   it).
3. Full: the GLOBAL CONFIGURATION page lists the features. On vanilla, Tournament Mode still starts.

**Dolphin Gecko codes:** a Gecko code you enabled in Dolphin for GALE01 applies to **every** GALE01 ISO, a Synapse
ISO too, and overrides the feature built in (it can even crash a mod). Turn them off for Synapse ISOs (right-click the
game → Properties → Gecko Codes).

## ISOs this release hasn't been tested with

Many mods change the game's own code. For an ISO this release wasn't tested with, the builder runs every compatibility
check and then:

- **not compatible**: says why and stops (exit 4). There is no way to force it.
- **looks compatible**: asks whether to build it anyway, with its guess of the kind of base. Answer yes to build it;
  no builds nothing. In a script nobody can answer, so it stops unless you add `--allow-unknown-base`.

The checks prove the AI can be **installed** safely, not that the mod's code and the AI get along in a match. Always
boot-test the result (see "Boot check"), try a few of the mod's own features, and keep the original ISO.

### Reporting a tested ISO

After building an untested ISO, the builder shows a **REPORT** block (the window has a **Copy report** button):

```text
== REPORT (untested ISO: copy this block when you report how it went)
  release data : 13d3d184ff70
  iso          : SSBM 0.91 ULTRA v2.4.iso (1438710620 B)
  game code    : SHA-256 540d0552… (not in known_dols.tsv)
  profile      : mex
  checks       : all passed
  plan         : P2
  exit code    : 0
  boot test    : <fill in: boots? CPU at type 4 attacks and wavedashes? Z+D-Up menu opens? the mod's own features still work?>
```

Fill in the `boot test` line after your boot test, then please open an issue at
<https://github.com/w3irDv/20XX-Synapse_Engine/issues/new> titled `Tested ISO: mod_name` and paste the block. A mod
reported working can join the tested list in the next release. Reports of failures are just as useful. Thank you!

### Adding a tested ISO on this machine

Once a build of an untested ISO has passed your boot check, you can add it to this machine's tested list, so it isn't
asked about again and its builds are checked byte for byte. From a terminal (it asks you to confirm the boot test):

```text
synapse-cli add-known-base "D:\Games\some mod.iso" --built "D:\Games\some mod.aionly.iso"
```

The first path is the **original** ISO, the second the one built from it and boot-tested (AI-only or Full: the
builder recognises which). Nothing is added unless the original passes every check again, the built ISO passes
`check-built`, the built ISO is exactly what this builder makes from the original, and you answer `y`. The entry goes
to a file of this machine's own (`known_dols.local.tsv` for AI-only, `known_dols.full.local.tsv` for Full) in the
settings folder:

| OS | Settings folder |
|---|---|
| Windows | `%APPDATA%\Synapse` |
| Linux | `$XDG_CONFIG_HOME/synapse`, else `~/.config/synapse` |

Setting `SYNAPSE_CONFIG_DIR` uses another folder. To undo an addition, delete its line (or the file). The window
keeps its last folders there too (`gui_settings.txt`).

## Adding stages or characters

Adding content enlarges the disc's file table, which on **vanilla**, **hybrid.64** and **Silly** lowers the memory
limit the AI is placed under. The result line shows the remaining **content headroom** (unlimited on m-ex).

1. Add all your stages, characters and other files **first**, and keep a copy of that ISO **without** Synapse.
2. Build from it.
3. If you change the built ISO later, run **Check built ISO…** (or `check-built`) on it. If check **K7** fails, the
   ISO would freeze at boot: build again from your kept copy with the new content added there.

An ISO that was already built can't be built again; always start from the copy without Synapse.

## Per operating system

**Windows 10 / 11 (x64).** Run `synapse-gui.exe`. The executables aren't signed yet, so Windows may say "Windows
protected your PC": choose **More info → Run anyway** (or, before extracting, right-click the `.zip` → Properties →
tick **Unblock**). Run `synapse-cli.exe` from PowerShell or Command Prompt.

**Linux (x86-64).** Any distribution with glibc 2.17 or newer (2014 onwards). After extracting, if needed:
`chmod +x synapse-gui synapse-cli`, then run `./synapse-gui`. **Browse…** opens your desktop's file dialog through
the XDG desktop portal, or `zenity` if there is no portal; with neither, the window says so, and typing or pasting the
path always works. Dragging an ISO onto the window hasn't been tested on Linux yet.

**macOS.** Not in this release.

## Troubleshooting

| Problem | What to do |
|---|---|
| "Windows protected your PC" | see "Per operating system" |
| the window doesn't open, or opens black / crashes (graphics driver) | start it with another renderer: set `WGPU_BACKEND` to `gl` (or `dx12` on Windows, `vulkan` on Linux) and start it again. Windows uses DX12, then OpenGL, by default |
| **Browse…** shows "No file chosen. If no dialog appeared…" | no file dialog is available (Linux without a portal or zenity): type or paste the path |
| `[FAIL] G2 GameCube magic` | the file is compressed or not a GameCube image: convert it to ISO with Dolphin |
| `[FAIL] G3 game ID …` | not Melee NTSC 1.02 (PAL and 1.00 / 1.01 aren't supported) |
| `[FAIL] B1 …` (already carries Synapse) | the ISO was already built: use the original |
| `[FAIL] B6 …` (hook taken) | another mod already uses a code location the AI needs (20XX does): not supported |
| `[FAIL] B9 …` (static ceiling) | too much added content for this base (see "Adding stages or characters") |
| Full refused on hybrid.64 / Silly ("needs one of the exact ISOs") | start from the original release of that mod, or build AI-only |
| `release file corrupted` (exit 2) | download the builder again |
| not enough disk space (exit 5) | free space on the output drive, or choose another output folder |
| `cannot open … for writing` | an antivirus may be scanning the new file: try again, or write to another folder |
| you need more detail for a bug report | run `synapse-cli` with the same ISO and options (it prints the whole log), or, on Linux, start the window from a terminal with `RUST_LOG=debug` |
