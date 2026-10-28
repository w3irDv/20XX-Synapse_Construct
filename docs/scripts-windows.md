# Synapse AI-only ISO builder for Windows

`Build-SynapseIso.ps1` takes a Super Smash Bros. Melee **NTSC 1.02** ISO, either vanilla or a mod built on
it (hybrid.64, Akaneia, SSBM ACE, or another GALE01 mod that passes the eligibility checks), and writes a
new ISO that runs the Synapse CPU AI: the AI engine, the CPU config menu (Z + D-Up), the CPU-type selector
(D-pad), the DI / SDI / tech / Nana reactions, and the 20XX CPU rules (CPUs L-cancel, never taunt, Captain
Falcon never rapid-jabs, Sheik/Zelda never transform; each one switchable on the config menu's `<20XX CPU RULES>`
page). Your original ISO is never modified.

How the builder judges an ISO (which ISOs can be used, untested ISOs, added content, checking a built ISO, exit
codes): [`BUILD_DETAILS.md`](BUILD_DETAILS.md).

## Requirements

- Windows 10 or 11. Nothing to install: the script uses the PowerShell that comes with Windows (5.1),
  or PowerShell 7 if you have it.
- The `scripts` folder of the release: `scripts\windows` (the script) **and** `scripts\common` (its data) next to it.
  Keep that structure: the script reads `..\common`. The scripts zip on the Releases page has exactly that.
- An uncompressed ISO (`.iso` / `.gcm`) of one of the bases below. Use your copy **without** Synapse: an ISO this
  tool already built is refused (check B1). 20XX is not supported (it already uses a code location the AI needs).

  | Base | Notes |
  |---|---|
  | vanilla Melee NTSC 1.02 | Tournament Mode keeps working |
  | hybrid.64, either v3.2 build (Slippi, or the vanilla build whose game ID is `GHME01`) | the output is ~4.5 MB larger than the source |
  | Akaneia, SSBM ACE v2.0.0, and the m-ex mods SSBM Custom Stages Expansion 0.91, SSBM ULTRA v2.4 CSE 0.91 and Arcade Melee Demo 2.0 | |
  | another GALE01 1.02 ISO | built only if it passes every compatibility check, after the script asks you (see below) |

  Compressed images (`.nkit.iso`, `.rvz`, `.ciso`, `.wbfs`) must first be converted to a plain ISO with
  Dolphin (right-click the game → Convert File… → ISO).
- Free disk space: about the size of the ISO plus 64 MB, on the drive of the output.

## Run it

**Easiest:** drag your ISO onto `Build-SynapseIso.cmd`. The new ISO is written next to it as
`<name>.aionly.iso`.

**From a terminal** (PowerShell or Command Prompt), in the `scripts\windows` folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-SynapseIso.ps1 -SourceIso "D:\Games\Melee.iso"
```

`-ExecutionPolicy Bypass` lets this one script run without changing your system's policy. Quote paths
that contain spaces or commas.

The script prints one `[PASS]` / `[FAIL]` / `[INFO]` line per check (technical details, useful when you
ask for help), then a summary with the output path, the plan it used, the **content headroom** (see
"Adding stages or characters") and a short boot checklist. **The last lines, under `== Recap`,
say in ordinary language what happened and what to do next** — read those first.

## Parameters

| Parameter | Meaning |
|---|---|
| `-SourceIso <path>` | the source ISO: vanilla or a supported mod, without Synapse (required, except with `-CheckBuilt` or `-AddKnownBase`) |
| `-OutputIso <path>` | where to write the result; default `<source folder>\<source name>.aionly.iso` |
| `-Profile auto\|vanilla\|hybrid64\|mex` | default `auto`: chosen from the ISO. Forcing a profile that contradicts a recognised ISO is refused |
| `-AllowUnknownBase` | build an ISO this release hasn't been tested with, if it passes every check, without asking (for scripts) |
| `-CheckOnly` | run every check and show the plan; write nothing |
| `-Force` | overwrite an existing output |
| `-Common <dir>` | the release data folder; default `..\common` |
| `-CheckBuilt <path>` | check an ISO this release already built (e.g. after adding content); writes nothing; can only be combined with `-Common` |
| `-AddKnownBase <path> -BuiltIso <path>` | add a compatible, boot-tested ISO to `..\common\known_dols.local.tsv` (see "Adding a tested ISO on this machine"); can be combined with `-Profile` and `-Common` |

## Exit codes

The exit codes are the same for every front end: [`BUILD_DETAILS.md` 6](BUILD_DETAILS.md#6-exit-codes).

## Examples

```powershell
# vanilla -> D:\Games\Melee.aionly.iso
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\Melee.iso"

# hybrid.64, choosing the output name
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\hybrid.64.iso" -OutputIso "D:\Dolphin\hybrid.64.ai.iso"

# Akaneia or SSBM ACE (same procedure)
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\akaneia.iso" -Force
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\SSBM ACE Build v2.0.0.iso"

# is this ISO supported? (writes nothing)
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\some mod.iso" -CheckOnly

# another GALE01 ISO: the script asks before building it; then boot-test it
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\some mod.iso"

# the same, without the question (scripts)
.\Build-SynapseIso.ps1 -SourceIso "D:\Games\some mod.iso" -AllowUnknownBase

# re-check an ISO built earlier, after adding stages/characters to it
.\Build-SynapseIso.ps1 -CheckBuilt "D:\Games\Melee.aionly.iso"

# after a successful boot test: add that ISO to the tested list on this machine
.\Build-SynapseIso.ps1 -AddKnownBase "D:\Games\some mod.iso" -BuiltIso "D:\Games\some mod.aionly.iso"
```

(Inside a PowerShell window where scripts are blocked, prefix each with
`powershell -NoProfile -ExecutionPolicy Bypass -File`.)

## Boot check

In Dolphin (for the closest match to a console: Config → Advanced → enable MMU, disable Fastmem):

1. VS mode, set a CPU to type 4 (any level): it attacks and wavedashes.
2. Hold Z and press D-Up to open the CPU config menu; the D-pad changes the CPU type (a message shows it).
3. On vanilla, Tournament Mode still starts from the main menu.

Every in-match control (CPU types, 20XX subtypes, practice toggles, the config menu and all its settings) is
explained in [`../CONTROLS.md`](CONTROLS.md).

For an ISO this release hasn't been tested with, this boot check is required before relying on it.

## Adding stages or characters

Adding content enlarges the disc's file table, which on **vanilla** and **hybrid.64** lowers the memory
limit the AI is placed under. The summary prints the remaining **content headroom**: about 2.5 KB
(~100 files) on vanilla, ~15 KB (~600 files) on hybrid.64, unlimited on Akaneia / ACE.

1. Add all your stages, characters and other files **first**.
2. Keep a copy of that modded, **un-injected** ISO.
3. Run this script on it.
4. If you change the built ISO later (more content, another tool), run `-CheckBuilt` on it. If check K7
   fails, the ISO would hang at boot: re-run the script on your kept copy (with the new content added
   there). If even that copy is refused, the base has too much content for the AI on vanilla / hybrid.64.

An ISO that was already injected can't be injected again (check B1); always start from the un-injected copy.

## ISOs this release hasn't been tested with

Many Melee mods change the game's own code (the part the script calls the "DOL"). This release was tested
on vanilla, hybrid.64 (both v3.2 builds: Slippi, and the vanilla build `GHME01`), Akaneia, SSBM ACE v2.0.0 and the m-ex mods SSBM Custom Stages Expansion 0.91, SSBM ULTRA v2.4 CSE 0.91 and Arcade Melee Demo 2.0. For any other mod, the script runs every compatibility
check, prints a `== REPORT` block (see below), and then:

- if the ISO **isn't** compatible: says why and stops (exit code 4). Nothing is built, and there is no
  way to force it. The 20XX Hack Pack is recognised and refused this way: it already has the 20XX AI;
- if it **looks compatible** and you started the script yourself (double-click, drag-and-drop or a console): asks **`Build it anyway, as profile <profile>? [y/N]`**, where the profile is its guess from the ISO's game code
  and files (vanilla, hybrid64 or mex; it warns first when those clues disagree).
  Answer `y` to build it; anything else stops (exit code 4), builds nothing and says so (no report: there
  is nothing to report);
- if it looks compatible but no question can be asked (a script, a pipeline, `-CheckOnly`): stops (exit
  code 4). Add `-AllowUnknownBase` to build it without the question.

Building never adds the ISO to the list of tested ISOs: see "Adding a tested ISO on this machine".
The checks prove the AI can be **installed** safely; they can't prove that the mod's own code and the AI
get along during a match. So:

- **always boot-test** the result before relying on it (see "Boot check"), and also try a few of the mod's
  own features;
- keep the original ISO;
- if something misbehaves, it's most likely a conflict between that mod and Synapse, not your setup.

Example (a mod that looks compatible, when the question was declined or couldn't be asked):

```text
== Recap
>> This ISO's game code was changed by the mod you're using, and this release hasn't been tested with it.
   It looks compatible. To build it anyway, run it again and answer y to the question (or add
   -AllowUnknownBase), then test the result in Dolphin before relying on it.
```

## Reporting a tested ISO

When you build an untested ISO, the script prints a block like this:

```text
== REPORT (untested ISO: copy this block when you report how it went)
  release data : a8547298cad6
  iso          : SSBM 0.91 ULTRA v2.4.iso (1438710620 B)
  game code    : SHA-256 540d05520d716a4570ae9aad78616f65d441a3978dd607f5c3104dfb449b7b4a (not in known_dols.tsv)
  profile      : mex
  checks       : all passed
  plan         : P2
  exit code    : 0
  boot test    : <fill in: boots? CPU at type 4 attacks and wavedashes? Z+D-Up menu opens? the mod's own features still work?>
```

After your boot test, fill in the last line. Then, if you can, please open an issue at
<https://github.com/w3irDv/20XX-Synapse_Engine/issues/new> titled `Tested ISO: mod_name` and paste the block. Thank you! A mod reported
working can be added to the list of tested ISOs in the next release, so other players won't be asked
about it. Reports of failures are just as useful.

## Adding a tested ISO on this machine

Once a build of an untested ISO has passed the boot check, you can add it to the tested list on this
machine. Run this from a console (it asks a question):

```powershell
.\Build-SynapseIso.ps1 -AddKnownBase "D:\Games\some mod.iso" -BuiltIso "D:\Games\some mod.aionly.iso"
```

`-AddKnownBase` takes the **original** ISO (without Synapse) and `-BuiltIso` the one built from it and
boot-tested. Nothing is added unless:

1. the original passes every compatibility check again (an incompatible ISO can never be added);
2. the built ISO passes `-CheckBuilt`;
3. the built ISO's game code is exactly what this release builds from the original (so the ISO you tested
   really came from it, unchanged);
4. you answer `y` to **`Did the built ISO pass that boot test? [y/N]`**.

The entry goes to `..\common\known_dols.local.tsv`, a file of this machine's own additions. The release's
`known_dols.tsv` and `SHA256SUMS` are never changed. From then on, building from that ISO asks nothing:
it is reported as a known base "(added locally)", and the new game code is checked byte for byte, as for
the tested ISOs. To undo it, delete the line (or the file). Please still report the ISO (see "Reporting a
tested ISO"), so it can be added for everyone in a later release.

## Troubleshooting

| Message | What to do |
|---|---|
| "running scripts is disabled on this system" | use `Build-SynapseIso.cmd`, or `powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-SynapseIso.ps1 …` |
| "Windows protected your PC" / "Open File – Security Warning" on a file from the internet | choose **Run** (or **More info → Run anyway**); or, before extracting, right-click the downloaded `.zip` → **Properties** → tick **Unblock** |
| `[FAIL] G2 GameCube magic` | the file is compressed or not a GameCube image: convert it to ISO with Dolphin |
| `[FAIL] G3 game ID …` | not Melee NTSC 1.02 (PAL and 1.00/1.01 aren't supported) |
| `[FAIL] B1 … already carries the Synapse … section` | the ISO was already built by this tool; use the original |
| `[FAIL] B6 hook taken` | another mod already uses a code location the AI needs (20XX does): not supported |
| `[FAIL] B9 static ceiling` | too much added content for vanilla / hybrid.64 (see above) |
| exit 4, "unknown DOL" | a modded ISO this release wasn't tested on: see "ISOs this release hasn't been tested with" |
| `release file corrupted or edited` | re-download / re-copy the whole `scripts` folder; don't edit `common\` |
| `not enough disk space` | free space on the output drive, or choose another `-OutputIso` |
| `cannot open … for writing` | an antivirus is scanning the new file; run again, or write to another folder |
