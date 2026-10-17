# Minimal build: AI-only ISOs with no toolchain

> **Excerpt.** This is §8 of the specification of the release builders: the part their output cites (`REF_MINIMAL_BUILD.md 8.2`, `REF_MINIMAL_BUILD.md 8.4`, `REF_MINIMAL_BUILD.md 8.5`). References to other sections are to the full specification, which stays with the project sources. You don't need it to use the builders: the README next to each script covers the boot check, `-CheckBuilt` and `-AddKnownBase`.

## 8. Any other ISO: is it eligible, and for which profile?

A procedure written for one base is valid on another ISO only if every assumption baked into the
section holds there. The section assumes, and the checks below verify:

- the stock entry it chains to (B1, B5),
- a free text slot and a free, bss-resident load address (B2–B4),
- the 10 hook sites hold their stock instructions, because the stub writes `b <payload>` over them and
  the payloads replay the original instruction (B6),
- the game functions the overlays call and the code around each hook are the vanilla bytes (B10),
- for `mex`: the m-ex reserved cave exists and is free (B7); for `vanilla` / `hybrid64`: the arena top
  below the ceiling is free (B9),
- the ISO structure can be patched (S1, S6).

### 8.1 The eligibility procedure

1. **G1–G5** (§6 S1). A non-GameCube container (`.nkit.iso`, `.rvz`, `.wbfs`, `.ciso`) fails G2: convert
   it to a plain ISO with Dolphin ("Convert File…") first. A non-`GALE01` or non-rev-2 image is not
   supported (all hook addresses and the payload are NTSC 1.02 only).
2. **Known DOL?** SHA-256 in `known_dols.tsv` → the base is one of the tested ones, whatever the rest of
   the ISO is (other files, other FST size): take its profile. The DOL is the only thing the payload
   depends on, plus the FST size for static profiles (B9 still runs).
3. **Unknown DOL** → classify (§8.2), then run B1–B10 for that profile. All pass → **eligible, unproven**:
   build after the `y/N` prompt (or with `--allow-unknown-base`), boot-test before relying on it (§10),
   then optionally record it on this machine with `--add-known-base` (§9.5). Any fail → **ineligible**:
   the scripts refuse (no option forces it), and the report says which assumption broke.

### 8.2 Classifying an unknown DOL

Structural marks only, never a hash: m-ex ISOs come in many variants (Akaneia, ACE, ULTRA, Arcade… with
different DOLs). With the stock entry, the scripts first look for two names in the FST name table (it starts
at 12 × entry count; each name is NUL-terminated) and print them as `disc marks: MxDt.dat yes|no (m-ex data
file), AI_Engine.bin yes|no (20XX AI file)`. The Linux / macOS scripts dump the table with `od -tx1`, squeeze
the whitespace and match the whole NUL-delimited bytes, so GNU, BSD and busybox `od` all work.

| Observation | Profile |
|---|---|
| entry `0x8000522C`, m-ex cave all zero | `mex`. **Low confidence** (an `[INFO]` line, and a warning before the prompt) unless `MxDt.dat` is on the disc and `AI_Engine.bin` is not |
| entry `0x8000522C`, m-ex cave **not** all zero, `AI_Engine.bin` on the disc | none: the 20XX Hack Pack, which already runs the 20XX AI. S2 fails with the `S2-20XX` plain words (use the Swap, I7) |
| entry `0x8000522C`, m-ex cave **not** all zero, no `AI_Engine.bin`, B9 passes | `vanilla`. **Low confidence** if `MxDt.dat` is on the disc |
| entry `0x8000522C`, m-ex cave not zero, B9 fails | `vanilla` family, but B9 fails (too big an FST for the static layout): ineligible. The scripts classify it `vanilla` and let B9 (and any other check) report why |
| entry `0x80484800`, a loaded text section at `0x80484800` ending ≤ `0x80486600` | `hybrid64` |
| any other entry | none: another loader owns the boot (a Synapse build, a Cave build, another DOL mod) |

### 8.3 Measured examples (2026-10-02; disc marks 2026-10-07)

| ISO | DOL known? | Classified | Fails | Verdict |
|---|---|---|---|---|
| `Melee.EnJa.v1.02.iso` | ✅ vanilla | `vanilla` | — | eligible (tested) |
| `akaneia.iso`, `SSBM ACE Build v2.0.0.iso` | ✅ m-ex | `mex` | — | eligible (tested) |
| `akaneia.ext.iso` (another Akaneia build, bigger FST) | ✅ m-ex | `mex` | — | eligible (same DOL; dynamic stub absorbs the FST change) |
| `hybrid.64.iso` | ✅ hybrid64 | `hybrid64` | — | eligible (tested) |
| `SSBM Custom Stages Expansion 0.91.iso` | ✅ m-ex (same DOL as Akaneia / ACE) | `mex` | — | eligible (tested) |
| `ARCADE_MELEE-DEMO_2.0.iso`, `SSBM ULTRA v2.4 CSE 0.91.iso` | ✅ m-ex (own DOLs, tested mods) | `mex` (m-ex cave zero, `MxDt.dat`) | — | eligible (tested) |
| `Silly Melee.iso` (v1.01) | ✅ vanilla (own DOL, tested mod) | `vanilla` (cave holds code, no disc marks) | — | eligible (tested: Phase 1 T0–T6) |
| `hybrid.64.vanilla.iso` (v3.2 vanilla build, `GHME01`; 2026-10-15) | ✅ vanilla (own DOL, tested mod, `game_id` `GHME01`) | — (G3 accepts it only as the listed DOL) | — | eligible (tested: release scripts reproduce its golden ISO, `e30c761d…` on release data `fb50a7ad1cf5`; Dolphin `-AllFeatures` boot test) |
| a `GHME01` ISO that isn't the listed DOL (e.g. an injected copy) | ❌ | — | G3 (`G3id`) | refused |
| `SSBM, 20XXHP 5.0.2.iso` | ❌ | none (`AI_Engine.bin`: 20XX) | S2 (`S2-20XX`). Classified `vanilla` it would also fail B6 and B10 (7 of the 8 reaction-cave hooks taken by 20XX's own caves) and B9 (ceiling `0x817F4440`) | ineligible: use the Swap (I7) |
| any `.aionly.iso` / `.fullpackage.iso` | ❌ | — | B1 (entry already `0x80484800`/`0x80486600`) | ineligible: already injected |

### 8.4 What eligibility does not prove

The checks prove the **injection** is structurally sound. They don't prove the base's own code leaves
the AI's runtime assumptions intact (fighter struct layout, CPU dispatch, the arena below the ceiling
not being used by the base's own late allocations). For an unknown DOL, the §10 boot test (CPU type 4
attacks, menu opens, selector works) is the acceptance criterion.

### 8.5 ISOs with added content (new stages, characters, files)

Adding stages, characters or other files normally changes **only disc files and the FST**, not the boot
DOL (Akaneia and ACE have different rosters and the same DOL). So the DOL checks (S2, S3 B1–B8, B10) are
unaffected and a known base stays known. Two things change:

**1. The FST grows, so the static ceiling drops (§5.4).** The static profiles end at `0x817F60A4` and need
`align32(FST max size) ≤ 0x7F40` (32,576 B). Each added file costs about 24 B of FST (a 12-B entry plus
its name and NUL; measured average 24.7 B on vanilla, 23.5 B on hybrid.64; long names cost more):

| Base | FST now (aligned) | Headroom | ≈ files that can be added |
|---|---|---|---|
| vanilla | 30,016 B | 2,560 B | **~100** |
| hybrid.64 | 17,504 B | 15,072 B | ~600 |
| m-ex (Akaneia, ACE) | any | no static limit | unlimited: the dynamic stub places the payload under the live ceiling at boot |

Past the limit, B9 fails and the build is refused (exit 3); it never produces a broken ISO. Going past it
on a vanilla-family DOL needs a new profile with a boot-computed placement like m-ex's, which in turn
needs a new fixed home for the A4 block (every `cfg_base` scans only `0x8032E980`, `0x80191500`,
`0x817F6000`), i.e. rebuilt engine, caves and overlays, not just a new section (§11.3).

**2. The ISO layout changes.** S6 adapts: if the files were re-packed right after the FST (GCRebuilder,
`gc_fst rebuild`), P2 finds no room and P3 moves the DOL to the end. A placement always exists; the only
cost is an image larger than a physical disc (§6 S6).

**Order matters:**

| Scenario | Result |
|---|---|
| add content **first**, then run the procedure | ✅ safe: every check runs on the final ISO |
| add content **after** the injection, on `vanilla` / `hybrid64` | ⚠️ **can fail to boot**: if the FST crosses the limit, the stub copies the payload over the structure at `[0x800000F4]` and the game hangs in `OSInit` (the documented module-struct panic). Nothing in the build can see this. Run `--check-built` (§9.4) after any change |
| add content after the injection, on `mex` | ✅ for the payload (dynamic placement), unless the tool also rewrote the DOL (next row) |
| a tool rewrites the boot DOL after the injection (m-ex Tool installing or updating m-ex, MCM-style code injection, an ISO rebuild from an extracted *original* DOL) | the Synapse section may be silently gone, or a hook site taken: `--check-built` reports it. Re-inject from your copy without Synapse |
| a content mod that also changes the DOL (stage-select expansions, 20XX-style code) | the DOL is unknown: S2/§8 run the full eligibility checks; refused if a hook site is taken |
| heavy content that needs more heap | **not checked statically**: the payload takes ~31 KB of arena (vanilla/hybrid) or ~27.5 KB (m-ex), so a base already near its heap limit can run out of memory in a match. Boot-test with the largest stages/characters (§10) |

**Recommended workflow:** add all content → keep a copy of that modded, un-injected ISO → run the
procedure on it → after any later change, run `--check-built` on the result, and if it fails, re-inject
from the kept copy (an injected ISO is refused as a source, B1). The build report (S9) prints the
remaining FST headroom so the user knows the budget before adding more.

Added characters on m-ex run the 20XX brain as a vanilla character: DK by default, or the pick of the config menu's
`ADDED FIGHTERS PLAY AS` row (the engine's `nvchars` clamp): a behaviour property of the engine, not of this procedure.
