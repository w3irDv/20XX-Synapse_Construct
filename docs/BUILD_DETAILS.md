# Synapse build details

How the Synapse builders judge an ISO and what they guarantee. It applies to the **Synapse Builder** (`synapse-gui`,
`synapse-cli`) and to the **AI-only scripts** (`windows/`, `linux/`, `macos/`), which follow the same rules. Their output cites
the sections below as `BUILD_DETAILS.md 2`, `BUILD_DETAILS.md 3`, and so on. You don't need this page to build an ISO:
each README covers the everyday use.

Option names differ per front end:

| Meaning | `synapse-cli` | Windows script | Linux and macOS scripts |
|---|---|---|---|
| build an untested ISO without the question | `--allow-unknown-base` | `-AllowUnknownBase` | `--allow-unknown-base` |
| check only, write nothing | `--check-only` | `-CheckOnly` | `--check-only` |
| check an ISO built earlier | `check-built <iso>` | `-CheckBuilt <iso>` | `--check-built <iso>` |
| add a tested ISO on this machine | `add-known-base <iso> --built <built iso>` | `-AddKnownBase <iso> -BuiltIso <built iso>` | `--add-known-base <iso> --built-iso <built iso>` |
| force the kind of base | `--profile <name>` | `-Profile <name>` | `--profile <name>` |

In the window, **Check** is the check-only run and **Check built ISO…** is `check-built`.

## 1. Which ISOs can be used

- **Super Smash Bros. Melee NTSC 1.02** (game ID `GALE01`, revision 2): vanilla, or a mod built on it. PAL and
  versions 1.00 / 1.01 are not supported: every address the AI patches is NTSC 1.02 only. The one exception is
  hybrid.64's vanilla build (game ID `GHME01`), accepted only as the exact ISO this release lists.
- A **plain** disc image (`.iso` / `.gcm`). Compressed images (`.nkit.iso`, `.rvz`, `.ciso`, `.wbfs`) must first be
  converted: in Dolphin, right-click the game → Convert File… → ISO.
- Your copy **without** Synapse. An ISO a builder already built is refused: always start from the original.
- **Not the 20XX Hack Pack**: it already runs the 20XX AI and its own CPU menus, so it is recognised and refused.

**Tested ISOs** (the builder knows their game code exactly): vanilla 1.02; hybrid.64 v3.2 (the Slippi build and the
vanilla build `GHME01`); Akaneia; SSBM ACE v2.0.0; SSBM Custom Stages Expansion 0.91; SSBM ULTRA v2.4 CSE 0.91; Arcade
Melee Demo 2.0; Silly Melee v1.01. A tested ISO is recognised by its game code alone, so the same mod with other
stages or characters added is still recognised (see 4).

**Any other ISO** is *untested*: the builder checks whether Synapse can be installed on it (see 2 and 3). The
**Full** package needs more than the AI-only one: on an untested ISO, Full is only offered when it is recognised as
vanilla-like or as an m-ex mod (Akaneia-style); a mod recognised as hybrid.64-like or Silly-like gets AI-only.

## 2. How the base is recognised

Synapse adds its code as a new part of the game's executable, and where it goes depends on the kind of base. The
builder calls that kind the **profile**:

| Profile | Bases |
|---|---|
| `vanilla` | vanilla 1.02 and mods that keep its layout (Silly Melee has a profile of its own for Full) |
| `hybrid64` | hybrid.64 |
| `mex` | m-ex mods: Akaneia, SSBM ACE and the other m-ex based mods |

A **tested** ISO's profile comes from its game code. For an **untested** ISO the builder guesses it from structural
clues, never from a checksum (m-ex mods come in many variants):

- how the game starts up (a mod that changes the start-up code the way hybrid.64 does is `hybrid64`; any other
  start-up change means another loader owns the boot, and the ISO is refused);
- whether the memory area m-ex reserves is empty (`mex`) or holds code (`vanilla`-like);
- two files on the disc: `MxDt.dat` (m-ex's data file) and `AI_Engine.bin` (20XX's AI file, which means the 20XX Hack
  Pack). The builder prints both as `disc marks: …`. When these clues disagree with the guess, it says the guess has
  **low confidence** and warns you before asking.

After the guess, it runs every check for that profile: the start-up code, a free slot for the new part, the ten
places the AI hooks still holding the stock game code, the game functions the AI calls being unchanged, and enough
memory for it (see 4). If one fails, the ISO is refused and the output says which check failed and why, in plain words
at the end (`== Recap`). There is no option to force a refused ISO.

You can force the profile; if the ISO is tested and you force another one, the builder refuses (exit 1).

## 3. Untested ISOs and the boot test

When an untested ISO passes every check, the builder:

1. prints a `== REPORT` block (the release data, the ISO name and size, its game code checksum, the profile, the
   checks, the plan and the exit code);
2. asks **whether to build it anyway**. Answer yes to build it; no builds nothing (exit 4). In a script, where nobody
   can answer, it stops (exit 4) unless you add the option that builds without the question (table above).

The checks prove the AI can be **installed** safely. They can't prove the mod's own code and the AI get along during
a match: how the mod changed the fighters, the CPU logic or the memory it uses later. For an untested ISO, the **boot
test** is the real acceptance:

1. In Dolphin (closest to a console: Config → Advanced → enable MMU, disable Fastmem), start VS mode with a CPU set
   to type 4, any level: it attacks and wavedashes.
2. Hold **Z** and press **D-Up**: the CPU config menu opens. Z + D-Left / D-Right changes the CPU type.
3. Try a few of the mod's own features; on vanilla-like mods, Tournament Mode still starts.

Then, please **report it**: fill in the `boot test` line of the REPORT block, open an issue on this repository titled
`Tested ISO: mod_name` and paste the block, so the ISO can be added to the tested list for everyone. Until then you
can **add it on your machine** (the "add a tested ISO" option, table above): it takes the original ISO and the one
built from it, re-checks both, asks whether the boot test passed, and records the original's game code on this
machine (the Builder: in your user settings folder; the scripts: `known_dols.local.tsv` next to the release data).
Later builds from that ISO are then treated as tested; the release's own list is never changed.

## 4. Adding stages or characters

Adding stages, characters or other files normally changes only the disc's files and its file table, not the game
code. So a tested ISO stays tested when you add content to it. One thing changes: the **file table grows**.

- On **m-ex** mods (Akaneia, ACE, …) that doesn't matter: the AI is placed below the memory limit measured at start-up.
- On **vanilla-like** mods and **hybrid.64** the AI is placed at a fixed address below that limit, and a bigger file
  table lowers the limit. Each added file costs about 24 bytes. For the AI-only package that leaves room for about
  **100 added files on vanilla** and **600 on hybrid.64**; the Full package is larger, so it leaves less. The builder
  prints the remaining **content headroom** after every build and check.

Past the limit the build is **refused** (exit 3): it never writes an ISO that can't boot. But content added **after**
building is not checked by anything:

| What you do | Result |
|---|---|
| add content **first**, then build | safe: every check runs on the final ISO |
| add content **after** building, on vanilla-like or hybrid.64 | **may freeze at start-up** if the file table crossed the limit. Run the check of 5 |
| add content after building, on m-ex | fine for the AI, unless the tool also rewrote the game code (next row) |
| a tool rewrites the game code after building (the m-ex Tool installing or updating m-ex, a code injector, a rebuild from an extracted original executable) | Synapse may be silently gone or broken. Run the check of 5; rebuild from your copy without Synapse |
| a mod that needs a lot more memory (very large stages or characters) | not checked: the AI uses about 31 KB (vanilla-like, hybrid.64) or 27.5 KB (m-ex) of memory. Boot-test with the largest content |

**The safe order:** add all your content → keep a copy of that ISO **without** Synapse → build from it → after any
later change to the built ISO, check it (5); if the check fails, build again from the kept copy with the new content
added there. If even that copy is refused, the base has too much content for the AI.

Added characters on m-ex play with the 20XX AI as a vanilla character: Donkey Kong by default, or the one chosen in
the config menu's `ADDED FIGHTERS PLAY AS` row.

## 5. Checking an ISO built earlier

The check-built run reads an ISO a builder produced, writes nothing, and says whether it still boots with Synapse
after whatever happened to it since (content added, re-packed, another tool). It reports:

| Check | Fails when |
|---|---|
| K1 | the file is not a readable Melee NTSC 1.02 image |
| K2 | the Synapse part of the game code is gone, or damaged (another tool rewrote the game code), or the ISO wasn't built by this release |
| K3 | another tool changed how the game starts up, so Synapse no longer loads |
| K4 | part of the game code Synapse starts from was removed (hybrid.64) |
| K5 | another mod now changes one of the places the AI hooks |
| K6 | m-ex: something now uses the memory area Synapse needs |
| K7 | vanilla-like and hybrid.64: **the file table grew past the limit, so the ISO will freeze at start-up** (see 4) |
| K8 | *(information, not a failure)* the game code differs from what the builder wrote; K2–K6 decide whether that matters |

It also prints the profile, the current file table size and the remaining content headroom (unlimited on m-ex).
Exit 0 when K1–K7 pass, 3 when one fails, 2 when the file can't be read.

## 6. Exit codes

The same on every front end:

| Code | Meaning |
|---|---|
| 0 | done and verified (check only: the ISO can be built; check-built: it still boots) |
| 1 | usage error: an option not understood, a forced profile that contradicts a tested ISO, an output that already exists without the replace option |
| 2 | the release data is damaged or incomplete, or an input can't be read |
| 3 | the ISO can't be used (wrong game or version, already built, a check failed); or check-built found a problem; or adding a tested ISO was refused |
| 4 | untested ISO, not built: not compatible, or you didn't answer yes (or nobody could be asked and the build-without-question option wasn't given) |
| 5 | not enough free disk space for the new ISO (it needs about the size of the source ISO) |
| 6 | writing or the read-back verification failed; the incomplete output was deleted |
