# Synapse AI-only release

Turns a Super Smash Bros. Melee NTSC 1.02 ISO, vanilla or a mod built on it, into one that runs the Synapse CPU AI (engine,
CPU config menu, CPU-type selector, DI/SDI/tech/Nana reactions, and the 20XX CPU rules: CPUs L-cancel, never taunt,
Captain Falcon never rapid-jabs, Sheik/Zelda never transform, each switchable in the menu). You need the original ISO and this
folder; nothing else is installed. The ISO itself is never included.

Supported bases: vanilla NTSC 1.02, hybrid.64, Akaneia, SSBM ACE v2.0.0, and the m-ex mods SSBM Custom Stages Expansion 0.91, SSBM ULTRA v2.4 CSE 0.91 and Arcade Melee Demo 2.0;
other GALE01 mods if they pass the eligibility checks. Start from your copy without Synapse (an already-built ISO is refused); 20XX is not
supported.

| Folder | Content | Status |
|---|---|---|
| [`CONTROLS.md`](CONTROLS.md) | **in-match controls for players**: the CPU selector (D-pad) and the CPU config menu (Z + D-Up) | ready |
| `common/` | precompiled sections and tables shared by every OS | ready |
| [`REF_MINIMAL_BUILD.md`](REF_MINIMAL_BUILD.md) | **how the builders judge an ISO**, for the curious and for modders: which ISOs are eligible, how the profile is guessed, what the checks can't prove, and the limit on added content (an excerpt of the builders' specification; their output cites it, e.g. "REF_MINIMAL_BUILD.md 8.2") | ready |
| `windows/` | `Build-SynapseIso.ps1` (PowerShell 5.1+ / 7), `Build-SynapseIso.cmd` (double-click / drag-and-drop wrapper), [`README.md`](windows/README.md) | **ready** (tested 2026-10-02: outputs byte-identical to the boot-tested ISOs) |
| `linux/` | `build-synapse-iso.sh` (bash 4+, coreutils, any POSIX awk), [`README.md`](linux/README.md) | **ready** (tested 2026-10-02 on Debian 12 / mawk, Ubuntu 24.04 / gawk, busybox awk: outputs byte-identical to the Windows script's and the boot-tested ISOs) |
| `macos/` | `build-synapse-iso.zsh` (zsh, macOS 10.15+), `Build Synapse ISO.command` (Finder double-click), [`README.md`](macos/README.md) | **written, Mac test pending** (passes the full test battery under zsh in WSL) |

## Reporting a tested ISO

When a script builds an ISO it hasn't been tested with, it prints a `== REPORT` block. Players who
boot-test such an ISO are kindly asked to fill in the `boot test` line, open an issue at
<https://github.com/w3irDv/20XX-Synapse_Engine/issues/new> titled `Tested ISO: mod_name`, and paste the block. Thank you!
