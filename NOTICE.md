# Licences and third-party notices

## Synapse's own work: MIT

[`LICENSE`](LICENSE) (MIT, Copyright (c) 2026 w3irDv) covers the work of the Synapse project only:

- the Synapse Builder source (`source/builder/`: `synapse-core`, `synapse-cli`, `synapse-gui`, `xtask`);
- Synapse's own code inside the precompiled packs (`scripts/common/`, `source/full/`): the CPU selector, the
  configuration menus, the reaction code, the patches applied to the AI engine, the boot code and Synapse's features;
- the release scripts (`scripts/windows/`, `scripts/linux/`), the documentation, the table formats;
- the Gecko codes marked `[Synapse]` in `geckos/`.

## Third-party code with its own licence

These keep their own terms; they are followed as published.

| Component | Where | Licence | Copyright |
|---|---|---|---|
| Enhanced Random Character (the Character Random Pool is a fork of it) | the Full packs; `geckos/character_random_pool.offline.gecko.txt` | MIT | Copyright (c) 2026 the Enhanced Random Character contributors ([upstream](https://github.com/2gifts/SSBMEnhancedRandomCharacter)); fork changes Copyright (c) 2026 w3irDv, MIT |
| Rust crates linked into `synapse-gui` / `synapse-cli` (egui, eframe, wgpu, winit, rfd, sha2 and their dependencies) | the executables | each crate's own: mostly `MIT OR Apache-2.0` (taken as MIT where offered), also MIT, Apache-2.0, Zlib, BSD, ISC, BSL-1.0, Unicode-3.0, OFL-1.1 and the Ubuntu Font Licence (egui's font) | listed with their full licence texts in `THIRD_PARTY_LICENSES.txt`, shipped in each executable's zip |

The Enhanced Random Character licence:

```
MIT License

Copyright (c) 2026 the Enhanced Random Character contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Community work without a licence: not covered by the MIT licence

These are their authors' work, published without a licence. They are **not** covered by Synapse's MIT licence; they
are redistributed, as the Melee modding community shares its codes, with credit to their authors. If you are an
author and want your work credited differently or removed, open an issue.

| Work | Authors | Where |
|---|---|---|
| 20XX AI Engine (from the 20XX Melee Training Hack Pack), shipped patched | Achilles1515, expanded by DRGN-DRC | both packs |
| Universal Controller Fix 0.84 | Altimor, PracticalTAS, CarVac, Krohnos | Full packs |
| Normal C-Stick in DEVELOP mode | Magus, Achilles | Full packs (vanilla) |
| Normal C-Stick in 1P mode | Zauron | Full packs (vanilla) |
| Flash Red on failed L-cancel | Achilles1515, Fizzi | Full packs |
| Swap Z and Y (Z-Jump) | Altimor | Full packs |
| Always Display Move/Project Hitboxes (Behind) | Altimor, Aitch | Full packs |
| Widescreen 16:9 | Dan Salvato, mirrorbender, Achilles1515, UnclePunch | Full packs |
| Arcade Melee Camera (Widescreen) | Punkline, Aitch | Full packs |
| Polling Drift + Full Visual Buffer fix | tauKhan | Full packs (Wii non-CRT variant) |
| Force 480p 4:3 | UnclePunch | Full packs (Wii non-CRT variant) |

These community codes are not copied into `geckos/`: `docs/gecko-codes.md` links to them.

## Not included

No Nintendo code or data is distributed. The builders patch the ISO you supply; Super Smash Bros. Melee is a
trademark of Nintendo.
