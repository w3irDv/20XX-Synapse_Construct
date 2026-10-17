# 20XX Synapse Engine

<p align="center"><a href="https://github.com/w3irDv/20XX-Synapse_Engine/" title="20XX-Synapse_Engine"><img src="./20XX-SE_logo.svg" width="400"></a></p>
<p align="center">
<a href="https://github.com/w3irDv/20XX-Synapse_Engine/releases" title="Releases"><img src="https://img.shields.io/github/v/release/w3irDv/20XX-Synapse_Engine?logo=github"></a>
</p>

## What Synapse is

Synapse brings the **20XX CPU AI** to Super Smash Bros. Melee (NTSC 1.02), on vanilla Melee and on mods built on it. The 20XX AI is the "advanced" CPU from the 20XX Training Hack Pack: it wavedashes, dash-dances, shields and answers out of shield, techs and DIs, recovers and edgeguards. Synapse adds it to your Melee Mod together with:

- a **CPU selector** on the D-pad and a **CPU config menu** (see [In a match](#in-a-match) below);
- the 20XX **DI, smash DI, tech and Nana-throw** reactions;
- the 20XX **CPU rules**: CPUs L-cancel, never taunt, Captain Falcon never rapid-jabs, Sheik/Zelda never transform, each switchable in the menu.

It also drives characters added by Akaneia or SSBM ACE: by default they play the 20XX AI as Donkey Kong (with their own moves); the menu's **ADDED FIGHTERS PLAY AS** line picks another character, or OFF for Melee's own CPU. Your original ISO is never modified: the builder writes a new one.

## Why Synapse?

20XX Melee Training Hack Pack is one of the most incredible Melee mods of all time. Apart from its huge number of stages and endless tunes, it brings you a killer AI engine that is light-years apart from the vanilla Melee one that all other mods inherit. I like to play solo, and after playing against a 20XX Fox, all other mods seem really boring... But I also like to play new stages, new characters and different music... so why not connect the 20XX AI Engine to your preferred mod and enjoy the best of both worlds? That's what Synapse is: the neural connection between 20XX HP and any mod!

## What you need

- **This release folder**, complete: the folder for your system **and** `common/` next to it.
- **A Melee NTSC 1.02 ISO** you own, uncompressed (`.iso` / `.gcm`), **without** Synapse already in it:
  
  - vanilla Melee NTSC 1.02 (Tournament Mode keeps working);
  - hybrid.64 v3.2 (Slippi or vanilla build), Akaneia or SSBM ACE v2.0.0;
  - Silly Melee v1.01;
  - also tested: SSBM Custom Stages Expansion 0.91, SSBM ULTRA v2.4 CSE 0.91, Arcade Melee Demo 2.0;
  - another mod built on NTSC 1.02, if it passes the builder's checks.
  
  20XX itself is not supported. Compressed images (`.nkit.iso`, `.rvz`, `.ciso`, `.wbfs`) must first be converted to a plain ISO with Dolphin (right-click the game → Convert File… → ISO).
- Free disk space for one more copy of your ISO (1.4–1.7 GB).

Nothing to install: each builder uses only the shell your system already has.

## Build it

The new ISO is written **next to your ISO**, named `<name>.aionly.iso`.

### Windows 10 / 11

Drag your ISO onto **`windows\Build-SynapseIso.cmd`**.

Or, from PowerShell in the `windows` folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-SynapseIso.ps1 -SourceIso "D:\Games\Melee.iso"
```

No Windows setting needs changing: the `.cmd` file and the command above allow the script for that one run only. Don't start `.\Build-SynapseIso.ps1` on its own: Windows' default policy refuses it ("running scripts is disabled on this system"). If Windows warns about a file downloaded from the internet, choose **Run** (or **More info → Run anyway**); to avoid the warning, right-click the downloaded `.zip` → **Properties** → tick **Unblock** before extracting it.

### Linux

From a terminal in the `linux` folder:

```bash
./build-synapse-iso.sh --source ~/Games/Melee.iso
```

If you get `Permission denied`, run `bash build-synapse-iso.sh --source ~/Games/Melee.iso` instead.

### macOS

The macOS builder passes the same tests as the others but has not been run on a real Mac yet; please report how it goes.

**First time only**, in Terminal (macOS blocks files downloaded from the internet):

```bash
xattr -dr com.apple.quarantine /path/to/the/release/folder
chmod +x /path/to/the/release/folder/macos/*.zsh /path/to/the/release/folder/macos/*.command
```

Tip: type the command up to the path, then drag the release folder onto the Terminal window.

Then double-click **`macos/Build Synapse ISO.command`** in Finder and choose your ISO. Or, from Terminal in the `macos` folder:

```bash
./build-synapse-iso.zsh --source ~/Games/Melee.iso
```

If macOS asks whether Terminal may access a folder, answer **Allow**.

## In a match

Both tools use **controller 1**.

**CPU selector**

| Buttons | Does |
|---|---|
| **D-Down** | CPUs play the **20XX Hack Pack AI** (CPU type 20XX) |
| **D-Up** | CPUs **stand still** (type Stay) |
| **D-Left / D-Right** | previous / next CPU type (the 20XX Hack Pack AI and Melee's own types, listed below) |
| **Z + D-Left / D-Right** | 20XX Hack Pack AI subtype: DEFAULT, SHIELD-HOLD, SHIELD-OOS, STAND, VANILLA |
| **A + D-pad** | toggle Invincibility (Up), No Damage (Right), Infinite Shield (Down), Timer Freeze (Left) |
| **X + D-pad** | damage −5 / +5 %: player 1 (Left / Right), player 2 (Down / Up) |

CPU types, in D-Left / D-Right order (the list wraps around at both ends):

Stay · Unused · Escape · Jump · **20XX** · Inert · Nana · Defensive · Struggle · Freak · Cooperate · SpLwLink · SpLwSamus · OnlyItem · EvZelda · NoAct · Air · Item · GuardEdge

**20XX** is the 20XX Hack Pack AI; the others are Melee's own built-in CPU behaviours. Some are passive or only meaningful in their original single-player context: for training, use **20XX**, and **Stay** as a pause.

**CPU config menu:** **Z + D-Up** opens it (**B** goes back and closes it; **D-pad** moves and changes values). Place the CPU in the "Stay" state using **D-Up** before entering, and return it to **20XX** using **D-Down** after exiting. The menu tunes how the 20XX Hack Pack AI plays: aggression in neutral, shield and out-of-shield habits, SHFFL aerials, DI and smash DI, tech and getup choices, and techchase escapes, plus the 20XX CPU rules page (and, on m-ex mods such as Akaneia and SSBM ACE, which character added fighters play as). Changes apply at once and last until you turn the game off.

You can easily change between 20XX and vanilla AIs just with one  **Z + D-Left**  and one **Z+D-Right**.

Full details: [`CONTROLS.md`](release/CONTROLS.md).

## After the build

The builder ends with a few lines under **`== Recap`**: read them first. They say whether it worked and what to do next. Then open the new ISO in Dolphin (or load it on your console as usual), start a VS match with a CPU, and press **D-Down** (controller 1) to give it the 20XX Hack Pack AI.

If something fails, the full README for your system has every option and a troubleshooting table: [`windows/README.md`](release/windows/README.md) · [`linux/README.md`](release/linux/README.md) · [`macos/README.md`](release/macos/README.md). Release index: [`README.md`](release/README.md).

## Credits

* The [20XX Melee Training Hack Pack](https://smashboards.com/threads/the-20xx-melee-training-hack-pack-v5-0-2-1-20-2023.351221/) and its 20XX AI Engine were created by Achilles1515 and expanded by DRGN-DRC. All the credit goes to them. Thanks for creating, in my opinion, the most revolutionary and complete Melee mod, in code, music, stages and endless options, and for publishing the notes and source code that made this port possible.
* Thanks to Punkline for all their contributions to the Melee mod community and for the libraries in the Hack Pack.
* Thanks to UnclePunch, Ploaj, and all members of the Akaneia team for [m-ex](https://github.com/akaneia/m-ex).
* Thanks to the SSBM ACE team for [SSBM ACE](https://github.com/Chri222k/ACE-BUILD-PUBLIC-/), which Synapse also supports.
* Thanks to Cjag for bringing us [Hybrid 64](https://gamebanana.com/mods/40702), which, besides being so much fun to play, also taught us a practical lesson on how to safely extend a DOL.
* Thanks to the Melee modding community for the GALE01 symbol map and years of shared research.
* The injection code has been AI-(reverse-)engineered using as a base the original 20XX Hack Pack, m-ex repos and Hybrid 64 binaries.
