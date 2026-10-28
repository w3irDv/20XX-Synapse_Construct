//! Plain-language messages for players, keyed by check id or outcome. The AI-only wording is shared with the
//! three release scripts: keep it identical to `$PLAYER` in Build-SynapseIso.ps1.
//! Option names are the CLI's (`--force`, `--allow-unknown-base`, …).

pub fn player(key: &str) -> Option<&'static str> {
    Some(match key {
        "G1" => "The file can't be read, or it is too small to be a Melee disc image.",
        "G2" => {
            "This isn't a plain GameCube disc image (it may be compressed: .nkit, .rvz, .ciso, .wbfs). In Dolphin, right-click the game > Convert File... > ISO, then try again."
        }
        "G3" => {
            "This isn't Melee NTSC 1.02 (the US/Japanese version 1.02). PAL and versions 1.00/1.01 aren't supported."
        }
        "G3id" => {
            "This disc's game ID is accepted only for the exact ISOs this release lists (hybrid.64's vanilla build is one). This copy isn't one of them: start from the original, unmodified ISO."
        }
        "G4" | "G5" => "The disc image looks truncated or damaged. Dump or download it again.",
        "B1" => {
            "Another mod already changes how this game starts up, so Synapse can't be added on top of it."
        }
        "B1inj" => {
            "This ISO already contains the Synapse AI. Start again from your original ISO (the one without it)."
        }
        "B2" | "B3" | "B4" | "B5" => {
            "This mod's game code is laid out differently from what Synapse needs; it can't be added safely."
        }
        "B6" => {
            "Another mod already changes game code that the Synapse AI needs, so the two can't be combined (20XX is one such mod)."
        }
        "B7" => {
            "This mod uses the memory area that Synapse needs on Akaneia/ACE-style ISOs; it can't be added safely."
        }
        "B8" => {
            "This mod's game code doesn't match the kind of ISO it looks like; it can't be added safely."
        }
        "B9" => {
            "This ISO has more added content (stages, characters, files) than the AI can fit next to on this base (vanilla / hybrid.64). Remove some content, or use an Akaneia/ACE-based ISO, which has no such limit."
        }
        "B10" => {
            "This mod changes game code that the AI relies on; they are probably not compatible."
        }
        "S2" => "This ISO's game code isn't a kind Synapse knows how to modify.",
        "DECLINED" => {
            "Nothing was built: you answered n. To build it later, run it again and answer y, then test the result in Dolphin before relying on it."
        }
        "S2-20XX" => {
            "This is the 20XX Hack Pack: it already has the 20XX AI and its own CPU menus, so this release doesn't modify it."
        }
        "FULL-KNOWN" => {
            "The Full package on this kind of ISO (hybrid.64, Silly Melee) needs one of the exact ISOs this release lists. This copy isn't one of them: start from the original ISO, or build AI-only."
        }
        "K2none" => {
            "This ISO doesn't contain the Synapse AI from this release (it was never added, or another tool removed it)."
        }
        "K2bad" => {
            "The Synapse AI inside this ISO is damaged: another tool changed it. Rebuild from your copy without Synapse."
        }
        "K3" => {
            "Another tool changed how the game starts up, so the Synapse AI no longer loads. Rebuild from your copy without Synapse."
        }
        "K4" => {
            "Part of the game this ISO needs to start was removed by another tool. Rebuild from your copy without Synapse."
        }
        "K5" => {
            "Another mod now changes game code that the AI needs. Rebuild from your copy without Synapse, without that mod."
        }
        "K6" => {
            "Another mod now uses the memory area the AI needs. Rebuild from your copy without Synapse, without that mod."
        }
        "K7" => {
            "This ISO will freeze at startup: too much content was added after Synapse. Add the content to your copy without Synapse and build again; if that copy is refused too, there is too much content for this base."
        }
        "OK-CHECKBUILT" => "This ISO still contains a working Synapse AI.",
        "USAGE" => "The command was not understood. See README.md for the options.",
        "PROFILE" => {
            "This ISO was recognised, and the --profile you chose doesn't match it. Leave --profile out."
        }
        "EXISTS" => {
            "The output file already exists. Add --force to replace it, or choose another --out."
        }
        "OUTDIR" => "The folder for the output file doesn't exist.",
        "RELEASE" => {
            "The release files are incomplete, damaged, or were edited. Download the builder again."
        }
        "READ" => "The file can't be read (wrong path, or it is in use).",
        "SPACE" => {
            "There isn't enough free disk space for the new ISO. Free some space or choose another --out."
        }
        "WRITE" => {
            "Writing the new ISO failed and the incomplete file was deleted. Check the disk and run again."
        }
        "UNKNOWN-ELIGIBLE" => {
            "This ISO's game code was changed by the mod you're using, and this release hasn't been tested with it. It looks compatible. To build it anyway, run it again with --allow-unknown-base, then test the result in Dolphin before relying on it."
        }
        "UNKNOWN-ELIGIBLE-ASK" => {
            "This ISO's game code was changed by the mod you're using, and this release hasn't been tested with it. It looks compatible. To build it anyway, build it (not just check it) and answer yes when asked, then test the result in Dolphin before relying on it."
        }
        "UNKNOWN-INELIGIBLE" => {
            "This ISO's game code was changed by the mod you're using, and it isn't compatible with Synapse (see the reasons above)."
        }
        "OK-CHECK-KNOWN" => {
            "This ISO is supported. Run the same command without --check-only to build it."
        }
        "OK-CHECK-UNKNOWN" => {
            "This ISO looks compatible but hasn't been tested with Synapse. You can build it; test it in Dolphin before relying on it."
        }
        "OK-BUILT-KNOWN" => {
            "Done: your new ISO with the Synapse AI is ready (path above). Your original ISO was not changed."
        }
        "OK-BUILT-UNKNOWN" => {
            "Done, but this mod has never been tested with Synapse: test the new ISO in Dolphin (steps above) before relying on it, and please report the result (REPORT block above)."
        }
        _ => return None,
    })
}
