# In-match controls: CPU selector and CPU config menu

A Synapse ISO adds two tools you use **during a match**, both from **controller 1**:

- the **CPU selector**: Z / A / B + D-pad shortcuts that change what the CPUs do, with a short message at the top of the screen;
- the **CPU config menu**: an on-screen menu (**Z + D-Up**) to fine-tune how the Synapse AI plays.

Neither needs the pause menu; both work in any VS match with CPU players.

## The CPU selector

| Buttons (controller 1) | What it does |
|---|---|
| **Z + D-Left / Z + D-Right** | on a normal CPU type: previous / next **CPU type** (the list below; 20XX is skipped). On type 20XX: previous / next **20XX subtype** |
| **Z + D-Down** | switch between **20XX** and the normal CPU types: from a normal type to 20XX (with the subtype you last chose), and from 20XX back to the normal type you last had (Stay the first time) |
| **A + D-Up** | toggle **Invincibility** (hits do nothing) |
| **A + D-Right** | toggle **No Damage** (hits land and send flying, but percent never goes up) |
| **A + D-Down** | toggle **Infinite Shield** (shields never shrink or break) |
| **A + D-Left** | toggle **Timer Freeze** (the match clock stops) |
| **B + D-Left / B + D-Right** | player 1's damage −5 % / +5 % |
| **B + D-Down / B + D-Up** | player 2's damage −5 % / +5 % |

- Every change shows a message for about 3 seconds: the CPU type on the first line and, on type 20XX, the subtype on the second line; or the toggle and whether it is now On or Off.
- **One CPU type for all CPUs.** The type and the subtype apply to **every CPU** in the match **except Nana** (Ice Climbers' partner): she always keeps following Popo. The toggles (A + D-pad) apply to **everyone**, humans included, until you toggle them off. Damage stays between 0 % and 999 %. B fires a special move and A an attack while you press them, as usual.
- **Remembered:** once you pick a type, every new **VS**, **Special Melee** (Stamina, Giant, …) and **Training** match starts the CPUs on it, also after going back to character select, until you turn the game off. Event, Home-Run and the single-player modes keep their own CPU types. The subtype is remembered too and applies in **every** mode, so in an Event a 20XX CPU uses your subtype (on STAND it stands still). In Training, Training's own CPU option still works after the match starts.
- **The D-pad alone, and X, Y, L or R + D-pad, do nothing**, so mods that use them (Silly Melee's save / load state, its practice dummies, …) never change your CPU. Only controller 1 is read.
- While the config menu is open the match is frozen and the selector doesn't run; the D-pad does nothing there.

### CPU types (Z + D-Left / Z + D-Right)

**20XX** is the Synapse AI. The others are Melee's own built-in CPU behaviours, in this order:

Stay · Unused · Escape · Jump · **20XX** · Inert · Nana · Defensive · Struggle · Freak · Cooperate · SpLwLink · SpLwSamus · OnlyItem · EvZelda · NoAct · Air · Item · GuardEdge

The list wraps around at both ends, and Z + D-Left / Right step over **20XX** (reach it with **Z + D-Down**). Some of the built-in types are passive or only meaningful in their original single-player context; for training, use **20XX**, and **Stay** as a pause.

### 20XX subtypes (Z + D-Left / Z + D-Right, while on type 20XX)

| Subtype | The CPU… |
|---|---|
| **DEFAULT** | plays with the full Synapse AI (uses the config menu settings) |
| **SHIELD-HOLD** | holds shield |
| **SHIELD-OOS** | holds shield; each time you hit its shield, it answers out of shield (OOS SELECTION in the menu) as soon as the shield stun ends: out-of-shield practice |
| **STAND** | stands still, without shielding |
| **VANILLA** | plays like Melee's normal CPU |

The subtype is shared by all CPUs and wraps around at both ends.

## The CPU config menu

### Quick start: change a setting

1. **Z + D-Up**: the config menu opens and **the whole match freezes** (fighters, items, the clock; the HUD and
   music keep going).
2. Move with the **control stick**: up / down moves the cursor, left / right changes the value. **A** opens a
   sub-page, **B** goes back.
3. **START** (or **B** on the first page, or **Z + D-Up**): the menu closes and the match resumes. The CPUs use
   your new settings at once.

### Open, move, change, close

| Buttons (controller 1) | In the menu |
|---|---|
| **Z + D-Up** | open the menu (from the match): the match freezes |
| **Stick up / down** | move the cursor (blue); it skips titles and notes, and wraps around |
| **Stick left / right** | change the value under the cursor |
| **L or R held** + stick left / right | change a number by 10 at a time |
| **A** | open the page of a line that ends with `>` |
| **B** | back to the previous page; on the first page, close the menu |
| **START** or **Z + D-Up** | close the menu from any page |

The D-pad does nothing while the menu is open, so mods that put save / load state on the D-pad (Silly Melee)
are never triggered from the menu. When you close with **B** or **Z + D-Up**, the match resumes only once you
let go of every button, so the closing press never becomes an attack. In Event, Home-Run Contest and
Multi-Man, Z restarts the event while the match is frozen (as in a normal pause): close with START or B there.
In Training, the menu freezes the match the same way and Training's own menu stays closed.

Holding a direction repeats it after a short delay: Left / Right fast (about 20 steps a second), so big numbers are quick to change; Up / Down slower (about 7 a second), so the cursor stops where you want. Numbers stop at their minimum and maximum; lists of named choices wrap around.

Changes apply **immediately**. They last until you turn the game off (they aren't saved to the memory card), and they carry over from one match to the next. Who they affect:

- **Pages 1 and 4** (shield, neutral, SHFFL, out-of-shield, techchase): the CPUs playing the Synapse AI, i.e. type **20XX** with subtype **DEFAULT**. Two exceptions: on SHIELD-OOS the out-of-shield lines apply, and on SHIELD-HOLD, SHIELD-OOS and STAND the techchase escape (page 4) still applies after a knockdown.
- **Page 5** (the 20XX CPU rules): **every CPU**, whatever its type; humans are never affected.
- **Pages 2 and 3** (DI, smash DI, tech, getup) and **NANA ALWAYS THROWS**: **every CPU**, whatever its type (DI and smash DI skip the Inert type). Humans are never affected, except that NANA ALWAYS THROWS also sets the throw of the Nana partner of a human Ice Climbers player.

Numbers marked **%** are chances out of 100.

**How NEUTRAL DEFENSE and SHIELD PROPENSITY work together.** When the opponent is close, the CPU first rolls NEUTRAL DEFENSE; only if that passes does it roll SHIELD PROPENSITY, and if that passes too it puts up shield, waits a moment and does its OOS SELECTION option. So the chance of a shield setup is about NEUTRAL DEFENSE × SHIELD PROPENSITY (defaults 100 % × 10 % = about 10 %). For more shielding, raise SHIELD PROPENSITY; for none at all, set NEUTRAL DEFENSE to 0. What it does from shield is set by OOS SELECTION and the two OOS REACTION TIME lines.

### Page 1: `<CPU CODES>` (opens first)

| Line | Values | Default | What it sets |
|---|---|---|---|
| 20XX CPU RULES `>` | | | opens page 5 |
| DIRECTIONAL INFLUENCE `>` | | | opens page 2 |
| GROUND TECH OPTIONS `>` | | | opens page 3 |
| TECHCHASE ESCAPE OPTIONS `>` | | | opens page 4 |
| SHIELD PROPENSITY | 0–100 % | 10 | when a shield setup is considered (see NEUTRAL DEFENSE), the chance the CPU actually shields and then acts out of shield (OOS SELECTION); a bit higher while the opponent is attacking |
| NEUTRAL OFFENSE | 0–100 % | 100 | how aggressive it is in neutral |
| NEUTRAL DEFENSE | 0–100 % | 100 | when the opponent is close, the chance the CPU considers a shield setup at all (0 = never: it goes straight to attacking) |
| SHFFL SELECTION | DEFAULT (RANDOM), NAIR, FAIR, BAIR, UAIR, DAIR | DEFAULT (RANDOM) | the aerial it short-hops and fast-falls with |
| OOS SELECTION | DEFAULT (RANDOM), GRAB, ROLL (RANDOM), ROLL AWAY, ROLL TOWARD, SPOTDODGE, SHIELD DROP, WAVEDASH (RANDOM), SHFFL, U-SMASH, UP-B, DOWN-B | DEFAULT (RANDOM) | what it does out of shield |
| OOS REACTION TIME | 0–255 frames | 0 | how long it waits in shield before acting; above about 210 its shield breaks before it acts |
| OOS REACTION TIME TYPE | EXACT, RANDOM MAX | EXACT | wait exactly that long, or a random time up to it |
| NANA ALWAYS THROWS | DEFAULT, FORWARD, BACK, UP, DOWN | DEFAULT | the throw Nana (Ice Climbers) always uses; it changes the direction, not when she throws. DEFAULT = the game decides: Nana repeats Popo's input a few frames late, or, when the climbers are split up, she pummels and then throws toward a nearby edge (otherwise in a random direction) |

### Page 2: `<DIRECTIONAL INFLUENCE CODES>`

| Line | Values | Default | What it sets |
|---|---|---|---|
| DIRECTIONAL INFLUENCE | VANILLA, NO DI, RANDOM, SURVIVAL | RANDOM | how the CPU DIs when hit |
| SMASH DI | VANILLA, NONE, RANDOM, TOWARD, AWAY, UP, DOWN | RANDOM | how it smash-DIs during hitlag |
| SMASH DI CHANCE | 0–100 % | 15 | chance of a smash-DI input, **per frame** of hitlag: keep it low, high values give inhumanly fast SDI |
| *`<CUSTOM DAMAGEFLYTOP DI (EX. U-THROW)>`* | | | DI when sent straight up (e.g. by an up-throw): |
| CUSTOM IN/OUT DI CHANCE | 0–100 % | 25 | chance of DI in or out |
| CUSTOM INWARD DI CHANCE | 0–100 % | 50 | of those, chance the DI goes inward |
| X-AXIS STRENGTH | 0.00–3.00 (steps of 0.05) | 1.00 | how far sideways that DI pushes |

### Page 3: `<TECH OPTIONS>` and `<GETUP OPTIONS>`

| Line | Values | Default | What it sets |
|---|---|---|---|
| CUSTOM TECH OPTIONS | OFF, ON | ON | use the three chances below instead of Melee's |
| TECH ROLL FORWARD | 0–100 % | 25 | |
| TECH ROLL BACKWARD | 0–100 % | 25 | |
| TECH IN PLACE | 0–100 % | 50 | |
| CUSTOM GETUP OPTIONS | OFF, ON | ON | use the getup settings below instead of Melee's |
| FRAME PERFECT GETUP | 0–100 % | 50 | chance of getting up on the first possible frame |
| MAX LAY WAIT FRAMES | 0–220 frames | 60 | otherwise it lies down for a random time up to this |
| STANDUP | 0–100 % | 25 | |
| GETUP ROLL FORWARD | 0–100 % | 25 | |
| GETUP ROLL BACKWARD | 0–100 % | 25 | |
| GETUP ATTACK | 0–100 % | 25 | |

In both lists the CPU tries the options from top to bottom (as the menu's note says). With CUSTOM TECH OPTIONS ON, the CPU's own button timing doesn't matter: if none of the three tech chances fires, it **misses the tech** (with the defaults, about 28 % of landings). If no getup option fires, it keeps lying and tries again; the game stands it up by itself after 220 frames.

### Page 4: `<TECHCHASE ESCAPE OPTIONS>`

| Line | Values | Default | What it sets |
|---|---|---|---|
| SHINE | 0–100 % | 10 | chance it shines out of a techchase (characters with a shine) |
| SPOTDODGE | 0–100 % | 15 | chance it spotdodges |
| ROLL | 0–100 % | 10 | chance it rolls |

When none of these happens, the CPU falls back to its other options.

### Page 5: `<20XX CPU RULES>`

Four rules the 20XX Training Pack applies to its CPUs, each with its own line. On m-ex mods (Akaneia, SSBM ACE and
other m-ex builds) the page has a fifth line, ADDED FIGHTERS PLAY AS.

| Line | Values | Default | What it sets |
|---|---|---|---|
| L-CANCEL CHANCE | 0–100 % | 100 | chance a CPU L-cancels when it lands during an aerial (half the landing lag). 100 = always, as on 20XX; 0 = rule off (a CPU then L-cancels only when its own inputs happen to, which is rare) |
| BLOCK TAUNTS | YES, NO | YES | YES: CPUs never taunt |
| BLOCK FALCON RAPID JAB | YES, NO | YES | YES: a Captain Falcon CPU never starts its rapid jab (it can still jab) |
| BLOCK SHEIK/ZELDA TRANSFORM | YES, NO | YES | YES: a Sheik or Zelda CPU never transforms with down-B |
| ADDED FIGHTERS PLAY AS *(m-ex only)* | CAPTAIN FALCON, PEACH, MARTH, PIKACHU, FALCO, FOX, DK, YOUNG LINK, DR. MARIO, GAME & WATCH, ZELDA, MARIO, ROY, OFF (VANILLA AI) | DK | which original character's 20XX tactics a fighter the mod added uses when it is a type-4 CPU (it still uses its own moves). OFF: added fighters play with the game's normal CPU instead. Applies from the next frame, kept until you turn the console off (a soft reset keeps it) |

## Troubleshooting

| What happens | Why / what to do |
|---|---|
| The D-pad does nothing | hold **Z**, **A** or **B** first: the D-pad alone does nothing. The selector reads **controller 1** only; also check the config menu isn't open (the match is then frozen and the stick drives the menu) |
| Z + D-Left/Right changes the subtype, not the type | the CPU is on **20XX**: press **Z + D-Down** to go back to the normal types |
| Z + D-pad does nothing | there must be a **CPU** in the match (in Silly Melee, L + R + D-Up turns P2 into a human: L + R + D-Down gives it back) |
| The CPU starts a match on an unexpected type | the selector remembers your last pick in VS, Special Melee and Training: change it with Z + D-pad |
| The CPU acts like Melee's normal CPU | it is on another type (press **Z + D-Down** for 20XX), or the subtype is **VANILLA** (Z + D-Left/Right) |
| A 20XX CPU stands still or only shields (also in an Event) | the subtype is **STAND** or **SHIELD-HOLD**: Z + D-Left/Right back to **DEFAULT** |
| Page 1 / page 4 settings seem ignored | they affect CPUs on type **20XX** with subtype **DEFAULT** (page 4 also on SHIELD-HOLD / SHIELD-OOS / STAND) |
| Z + D-Up opens nothing | press Z first and keep holding it, then D-Up; it must be controller 1, during a match |
