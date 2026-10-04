# In-match controls: CPU selector and CPU config menu

A Synapse ISO adds two tools you use **during a match**, both from **controller 1**:

- the **CPU selector**: D-pad shortcuts that change what the CPUs do, with a short message at the top of the screen;
- the **CPU config menu**: an on-screen menu (**Z + D-Up**) to fine-tune how the Synapse AI plays.

Neither needs the pause menu; both work in any VS match with CPU players.

## The CPU selector

| Buttons (controller 1) | What it does |
|---|---|
| **D-Down** | CPU type **20XX**: the Synapse AI (the one this ISO adds) |
| **D-Up** | CPU type **Stay**: the CPU stands still |
| **D-Left / D-Right** | previous / next CPU type (the list below) |
| **Z + D-Left / Z + D-Right** | previous / next **20XX subtype**; only while the CPU is on type 20XX |
| **A + D-Up** | toggle **Invincibility** (hits do nothing) |
| **A + D-Right** | toggle **No Damage** (hits land and send flying, but percent never goes up) |
| **A + D-Down** | toggle **Infinite Shield** (shields never shrink or break) |
| **A + D-Left** | toggle **Timer Freeze** (the match clock stops) |
| **X + D-Left / X + D-Right** | player 1's damage −5 % / +5 % |
| **X + D-Down / X + D-Up** | player 2's damage −5 % / +5 % |

- Every change shows a message for about 3 seconds: the CPU type on the first line and, on type 20XX, the subtype on the second line; or the toggle and whether it is now On or Off.
- The CPU type and the subtype apply to **every CPU** in the match **except Nana** (Ice Climbers' partner): she always keeps following Popo. The toggles (A + D-pad) apply to **everyone**, humans included, until you toggle them off. Damage stays between 0 % and 999 %.
- **R + D-pad does nothing**, so shielding while you press the D-pad changes nothing. (Before 2026-10-02 the subtype was on R + D-Left/Right; it is now on Z.)
- While the config menu is open, the D-pad drives the menu, not the selector.

### CPU types (D-Left / D-Right)

**20XX** is the Synapse AI. The others are Melee's own built-in CPU behaviours, in this order:

Stay · Unused · Escape · Jump · **20XX** · Inert · Nana · Defensive · Struggle · Freak · Cooperate · SpLwLink · SpLwSamus · OnlyItem · EvZelda · NoAct · Air · Item · GuardEdge

The list wraps around at both ends. Some of the built-in types are passive or only meaningful in their original single-player context; for training, use **20XX**, and **Stay** as a pause.

### 20XX subtypes (Z + D-Left / Z + D-Right, type 20XX only)

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

The match keeps running while the menu is open, so stop the CPU first:

1. **D-Up**: the CPU switches to **Stay** and stands still.
2. **Z + D-Up**: the config menu opens.
3. Move with **D-Up / D-Down**, change a value with **D-Left / D-Right**, open a sub-page with **A**, go back with **B**.
4. **B** on the first page: the menu closes and you're back in the match.
5. **D-Down**: the CPU goes back to **20XX** (the Synapse AI) and uses your new settings at once.

### Open, move, change, close

| Buttons (controller 1) | In the menu |
|---|---|
| **Z + D-Up** | open the menu (from the match); **Z + D-Up** again closes it from any page |
| **D-Up / D-Down** | move the cursor (blue); it skips titles and notes, and wraps around |
| **D-Left / D-Right** | change the value under the cursor |
| **L or R held** + D-Left / D-Right | change a number by 10 at a time |
| **A** | open the page of a line that ends with `>` |
| **B** | back to the previous page; on the first page, close the menu |

Holding a direction repeats it after a short delay: Left / Right fast (about 20 steps a second), so big numbers are quick to change; Up / Down slower (about 7 a second), so the cursor stops where you want. Numbers stop at their minimum and maximum; lists of named choices wrap around.

Changes apply **immediately**. They last until you turn the game off (they aren't saved to the memory card), and they carry over from one match to the next. Who they affect:

- **Pages 1 and 4** (shield, neutral, SHFFL, out-of-shield, techchase): the CPUs playing the Synapse AI, i.e. type **20XX** with subtype **DEFAULT**. Two exceptions: on SHIELD-OOS the out-of-shield lines apply, and on SHIELD-HOLD, SHIELD-OOS and STAND the techchase escape (page 4) still applies after a knockdown.
- **Pages 2 and 3** (DI, smash DI, tech, getup) and **NANA ALWAYS THROWS**: **every CPU**, whatever its type (DI and smash DI skip the Inert type). Humans are never affected, except that NANA ALWAYS THROWS also sets the throw of the Nana partner of a human Ice Climbers player.

Numbers marked **%** are chances out of 100.

**How NEUTRAL DEFENSE and SHIELD PROPENSITY work together.** When the opponent is close, the CPU first rolls NEUTRAL DEFENSE; only if that passes does it roll SHIELD PROPENSITY, and if that passes too it puts up shield, waits a moment and does its OOS SELECTION option. So the chance of a shield setup is about NEUTRAL DEFENSE × SHIELD PROPENSITY (defaults 100 % × 10 % = about 10 %). For more shielding, raise SHIELD PROPENSITY; for none at all, set NEUTRAL DEFENSE to 0. What it does from shield is set by OOS SELECTION and the two OOS REACTION TIME lines.

### Page 1: `<CPU CODES>` (opens first)

| Line | Values | Default | What it sets |
|---|---|---|---|
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

## Troubleshooting

| What happens | Why / what to do |
|---|---|
| The D-pad does nothing | the selector reads **controller 1** only; also check the config menu isn't open (the D-pad then moves its cursor) |
| Z + D-Left/Right does nothing | the CPU isn't on type **20XX**: press D-Down first |
| The CPU acts like Melee's normal CPU | it is on another type (press D-Down), or the subtype is **VANILLA** (Z + D-Left/Right) |
| Page 1 / page 4 settings seem ignored | they affect CPUs on type **20XX** with subtype **DEFAULT** (page 4 also on SHIELD-HOLD / SHIELD-OOS / STAND) |
| The CPU moved while I was in the menu | the match doesn't pause: press D-Up (Stay) before opening the menu |
| Z + D-Up opens nothing | press Z first and keep holding it, then D-Up; it must be controller 1, during a match |
