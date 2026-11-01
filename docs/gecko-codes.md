# Synapse Gecko codes

Gecko codes for **Super Smash Bros. Melee NTSC 1.02** (game ID `GALE01`), for use **without** a Synapse ISO: on
vanilla Melee or on another mod, pasted into Dolphin (or a console loader such as Nintendont). A Synapse ISO already
has these features built in; you don't need these files for it.

Every file is one code: a `$` title, `*` notes, then the code lines. In Dolphin: right-click the game → Properties →
Gecko Codes → Add New Code, paste the code lines (the name from the `$` line), tick it, start the game.

## Before you paste

- **Don't enable a code on a Synapse ISO that already bakes that feature.** Dolphin applies an enabled `GALE01` Gecko
  code to every `GALE01` ISO, so the same code would run twice, or override the setting you chose in the Synapse
  menu. Untick it before you boot a Synapse ISO.
- **Code space is shared and small.** Dolphin (and console loaders) hold about **408 code lines for all enabled
  codes together**, Dolphin's own enabled `GALE01` codes included. **If the enabled codes go over, none of them is
  applied** (Dolphin shows "Ran out of memory applying gecko codes"). The two pool codes are large: the Character
  Random Pool needs the whole space alone, and the Stage Random Pool leaves room for small codes only. The two
  can't be enabled together.
- The two pool codes are offline only (no Slippi-online support).

## The codes

| File | What it does | Bases | Code lines |
|---|---|---|---|
| [`cpu_lcancel.gecko.txt`](../geckos/cpu_lcancel.gecko.txt) | CPUs L-cancel every aerial landing (20XX Hack Pack rule) | any | 8 |
| [`cpu_no_taunt.gecko.txt`](../geckos/cpu_no_taunt.gecko.txt) | CPUs never taunt (20XX rule) | any | 9 |
| [`cpu_falcon_no_rapid_jab.gecko.txt`](../geckos/cpu_falcon_no_rapid_jab.gecko.txt) | a CPU Captain Falcon never rapid-jabs (20XX rule) | any | 10 |
| [`cpu_no_transform.gecko.txt`](../geckos/cpu_no_transform.gecko.txt) | a CPU Sheik / Zelda never transforms (20XX rule) | any | 24 |
| [`css_stars_wins.gecko.txt`](../geckos/css_stars_wins.gecko.txt) | CSS stars count games won, 20XX rules (use this **or** the KOs one) | any | 39 |
| [`css_stars_kos.gecko.txt`](../geckos/css_stars_kos.gecko.txt) | CSS stars count KOs, once per match, CPUs too (fixes the m-ex double count) | any | 25 |
| [`widescreen_results_43.gecko.txt`](../geckos/widescreen_results_43.gecko.txt) | add-on to the community **Widescreen 16:9** code (enable both): keeps the VS results screen in its 4:3 frame | any | 13 |
| [`cpu_attack_list_guard.gecko.txt`](../geckos/cpu_attack_list_guard.gecko.txt) | stops the CPU crash at `0x800B5084` with added fighters | m-ex (Akaneia, SSBM ACE) | 6 |
| [`sss_last_page.gecko.txt`](../geckos/sss_last_page.gecko.txt) | the stage select reopens on the page last used | m-ex | 37 |
| [`stage_random_pool.gecko.txt`](../geckos/stage_random_pool.gecko.txt) | random stages from a pool you edit on the stage select (D-pad Left); CSS D-pad Down starts on a pool stage; A+Y at GAME! = rematch on the next pool stage | vanilla, hybrid.64, m-ex (**not** Silly Melee) | 333 |
| [`stage_random_pool.silly.gecko.txt`](../geckos/stage_random_pool.silly.gecko.txt) | the same, for Silly Melee | Silly Melee | 329 |
| [`character_random_pool.offline.gecko.txt`](../geckos/character_random_pool.offline.gecko.txt) | per-port random-character pools for you and your CPUs, edited with the D-pad on the CSS; Fixed / Instant / Mystery coin modes. A fork of [Enhanced Random Character](https://github.com/2gifts/SSBMEnhancedRandomCharacter); its notes list what changed | vanilla, m-ex | 399 |

Not here, because they only work inside a Synapse ISO (they read the Synapse menu's settings): Random Stage Music,
the L-cancel chance, the switchable CSS Stars, the Arcade camera timer fix, Memcard Options.

Licence: the codes marked `[Synapse]` are MIT (Copyright (c) 2026 w3irDv); the Character Random Pool is MIT, with
its upstream authors' copyright. See `NOTICE.md` and `LICENSE` at the root of this repository.

## Community codes that Synapse bakes unchanged

A Synapse Full build includes these community codes as published by their authors. They are not copied here: get
them from the [SuperCombo Wiki's SSBM Gecko Codes page](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes), the community's
collection (each link opens the section that holds the code), or, for UCF, its author's repository.

| Code | Authors | Where to get it |
|---|---|---|
| Universal Controller Fix 0.84 | Altimor, PracticalTAS, CarVac, Krohnos | [AltimorTASDK/ucf](https://github.com/AltimorTASDK/ucf) (the source of UCF 0.84, built with cpp2gecko; Slippi ships 0.84 ready to use. The SuperCombo Wiki lists only v0.80) |
| Normal C-Stick Functionality in DEVELOP Mode | Magus, Achilles1515 | [SuperCombo Wiki: DEVELOP Mode Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#DEVELOP_Mode_Codes) |
| Normal C-Stick Functionality in 1P Mode | Zauron | [SuperCombo Wiki: Alter SSBM's Existing Game Mechanics](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Alter_SSBM's_Existing_Game_Mechanics_and_Game_Types) |
| Flash Red on Failed L-Cancel | Achilles1515, Fizzi | [SuperCombo Wiki: Character Model Display and Color Overlay Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Character_Model_Display_and_Color_Overlay_Codes) |
| Swap Z and Y (Z-Jump), per port | Altimor | [SuperCombo Wiki: Z-Jump Codes (Offline Only)](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Codes_for_a_Competitive_Setting) |
| Always Display Move/Project Hitboxes (Behind) | Altimor, Aitch | [SuperCombo Wiki: Collision Bubble Visualization Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Collision_Bubble_Visualization_Codes_%28Hitbox/Hurtbox/Shieldbox%29) (the wiki has Altimor's "Always Display Hitboxes"; this Altimor & Aitch variant, drawn behind the fighters, is not listed there) |
| Widescreen 16:9 | Dan Salvato, mirrorbender, Achilles1515, UnclePunch | [SuperCombo Wiki: Graphics/Audio Configuration Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Graphics/Audio_Configuration_Codes) ("Force Widescreen 16:9") |
| Arcade Melee Camera (Widescreen) | Punkline, Aitch | [SuperCombo Wiki: To Be Categorized](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#To_Be_Categorized) |
| Polling Drift + Full Visual Buffer fix (Wii, non-CRT screens only) | tauKhan | [SuperCombo Wiki: Graphics/Audio Configuration Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Graphics/Audio_Configuration_Codes) ("Visual Buffer & Polling Drift Fixes", the Wii-only Full version) |
| Force 480p 4:3 | UnclePunch | [SuperCombo Wiki: Graphics/Audio Configuration Codes](https://wiki.supercombo.gg/w/SSBM/Gecko_Codes#Graphics/Audio_Configuration_Codes) ("Force 480p") |
