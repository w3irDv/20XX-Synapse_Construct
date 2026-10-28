//! The user-side build (S0-S9; the rules for users: BUILD_DETAILS.md), ported from
//! release/windows/Build-SynapseIso.ps1 (`Invoke-Build`). Check ids and messages follow the scripts.

use crate::dol::{self, align, be32, hex, sha256};
use crate::iso::{Iso, read_at};
use crate::log::{Log, Report, Stop, stop};
use crate::pack::{Pack, PackKind, Placement, Profile};
use crate::plan::{Plan, plan};
use std::fs::{self, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

pub const MEX_CAVE_LO: u32 = 0x8032_C65C;
pub const MEX_CAVE_HI: u32 = 0x8032_EA80;
pub const APPLOADER_HI: u64 = 0x8120_0000;
pub const MEM1_TOP: u64 = 0x8180_0000;
pub const BI2_SIZE: u64 = 0x2000;
/// align32(FST max) <= this keeps static payloads below the ceiling (BUILD_DETAILS.md 4).
pub const STATIC_FST_LIMIT: u64 = 0x7F40;
pub const BYTES_PER_FILE: u64 = 24;
pub const VANILLA_ENTRY: u32 = 0x8000_522C;
pub const HYBRID_ENTRY: u32 = 0x8048_4800;
pub const HYBRID_TEXT_END: u64 = 0x8048_6600;

/// AI-only, or Full with or without the Wii non-CRT pack (Force 480p + Polling-Drift).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    AiOnly,
    Full { wii_non_crt: bool },
}

impl Kind {
    pub fn variant(self) -> Option<&'static str> {
        match self {
            Kind::AiOnly => None,
            Kind::Full { wii_non_crt: false } => Some("full"),
            Kind::Full { wii_non_crt: true } => Some("full.wii-non-crt"),
        }
    }
    pub fn pack(self) -> PackKind {
        if self == Kind::AiOnly {
            PackKind::Common
        } else {
            PackKind::Full
        }
    }
    /// Suffix of the default output name: `<source>.<suffix>.iso`.
    pub fn suffix(self) -> &'static str {
        self.variant().unwrap_or("aionly")
    }
}

#[derive(Clone, Debug)]
pub struct Options {
    pub source: PathBuf,
    pub out: Option<PathBuf>,
    pub kind: Kind,
    /// Force a profile for an unknown DOL (`None` = auto).
    pub profile: Option<String>,
    pub allow_unknown: bool,
    pub check_only: bool,
    pub force: bool,
}

#[derive(Clone, Debug)]
pub struct Outcome {
    pub profile: String,
    pub unknown: bool,
    pub plan: Plan,
    pub new_dol_size: u64,
    pub new_dol_sha: String,
    pub out: Option<PathBuf>,
    pub out_size: u64,
    pub headroom: String,
}

fn thousands(v: u64) -> String {
    let s = v.to_string();
    let mut o = String::new();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && (s.len() - i).is_multiple_of(3) {
            o.push(',');
        }
        o.push(c);
    }
    o
}

pub fn ceiling(fst_max: u64) -> u64 {
    MEM1_TOP - align(fst_max, 32) - BI2_SIZE
}

fn headroom(p: &Profile, iso: &Iso) -> String {
    if p.placement != Placement::Static {
        return "unlimited (dynamic)".into();
    }
    let hb = STATIC_FST_LIMIT as i64 - align(iso.fst_max, 32) as i64;
    if hb < 0 {
        return format!("{hb} B (OVER THE LIMIT)");
    }
    format!(
        "{} B (~{} files at {BYTES_PER_FILE} B each)",
        thousands(hb as u64),
        hb as u64 / BYTES_PER_FILE
    )
}

fn mex_cave(iso: &Iso) -> Option<&[u8]> {
    dol::window(
        &iso.dol,
        &iso.slots,
        MEX_CAVE_LO,
        (MEX_CAVE_HI - MEX_CAVE_LO) as usize,
    )
}

/// BUILD_DETAILS.md 2: the AI-only profile an unknown DOL looks like, or `None` (with the plain key).
/// Returns (profile, plain key on refusal, low confidence).
pub fn classify(iso: &Iso, log: &mut Log) -> (Option<&'static str>, &'static str, bool) {
    let entry = be32(&iso.dol, 0xE0);
    if entry == VANILLA_ENTRY {
        let (mxdt, aieng) = (
            iso.has_disc_file("MxDt.dat"),
            iso.has_disc_file("AI_Engine.bin"),
        );
        let yn = |b: bool| if b { "yes" } else { "no" };
        log.info(format!(
            "disc marks: MxDt.dat {} (m-ex data file), AI_Engine.bin {} (20XX AI file)",
            yn(mxdt),
            yn(aieng)
        ));
        if mex_cave(iso).is_some_and(|c| c.iter().all(|&b| b == 0)) {
            let low = !mxdt || aieng;
            if low {
                log.info("low confidence: the m-ex cave is empty, but the disc marks are not those of an m-ex ISO");
            }
            return (Some("mex"), "S2", low);
        }
        if aieng {
            log.info("20XX Hack Pack (AI_Engine.bin on the disc, m-ex cave holds code): it already runs the 20XX AI");
            return (None, "S2-20XX", false);
        }
        if mxdt {
            log.info("low confidence: MxDt.dat is on the disc, but the m-ex cave holds code");
        }
        return (Some("vanilla"), "S2", mxdt);
    }
    if entry == HYBRID_ENTRY
        && iso
            .slots
            .iter()
            .any(|s| s.is_text() && s.va == HYBRID_ENTRY && s.end() <= HYBRID_TEXT_END)
    {
        return (Some("hybrid64"), "S2", false);
    }
    log.info(format!(
        "entry point {}: another loader owns the boot (already injected, or another DOL mod)",
        hex(entry as u64)
    ));
    (None, "S2", false)
}

/// A text slot holding a section of either pack (by address + size): the ISO is already injected.
fn release_section<'a>(iso: &Iso, packs: &'a [&'a Pack]) -> Option<(usize, &'a Profile)> {
    iso.slots.iter().filter(|s| s.is_text()).find_map(|s| {
        packs
            .iter()
            .flat_map(|p| p.profiles.iter())
            .find(|p| p.va == s.va && p.size == s.size)
            .map(|p| (s.slot, p))
    })
}

/// G3, second half: a disc whose game id isn't GALE01 is accepted only as a known_dols.tsv row with that id.
fn check_game_id(iso: &Iso, pack: &Pack, variant: Option<&str>, log: &mut Log) -> Result<(), Stop> {
    if iso.game_id == "GALE01" {
        return Ok(());
    }
    match pack.known(&iso.dol_sha, variant) {
        Some(k) if k.game_id == iso.game_id => {
            log.pass(
                "G3",
                format!(
                    "game ID {}: boot DOL is the listed '{}'",
                    iso.game_id, k.name
                ),
            );
            Ok(())
        }
        _ => {
            log.bad(
                "G3",
                format!("game ID {}: boot DOL is not a listed ISO", iso.game_id),
                Some("G3id"),
            );
            Err(stop(
                log,
                3,
                format!("game ID {} is accepted only for a listed ISO", iso.game_id),
                None,
            ))
        }
    }
}

/// B6 / K5: every word the payload relies on (AI-only: hooks.tsv; Full: the profile's sites.tsv rows).
fn check_sites(iso: &Iso, pack: &Pack, p: &Profile, id: &str, log: &mut Log) -> bool {
    let mut bad = Vec::new();
    let mut n = 0;
    for s in pack.sites_for(&p.name) {
        n += 1;
        let w = dol::word(&iso.dol, &iso.slots, s.va);
        if w != Some(s.word) && (w.is_none() || w != s.poke_word) {
            let found = w.map_or("unmapped".into(), |w| hex(w as u64));
            bad.push(format!(
                "{} {} {} holds {found}, expected {}",
                s.kind,
                s.name,
                hex(s.va as u64),
                hex(s.word as u64)
            ));
        }
    }
    if bad.is_empty() {
        let what = if pack.kind == PackKind::Full {
            "sites.tsv words match"
        } else {
            "hook sites hold their stock words"
        };
        log.pass(id, format!("{n} {what}"));
    } else {
        for b in &bad {
            let what = if pack.kind == PackKind::Full {
                "site changed"
            } else {
                "hook taken"
            };
            log.bad(id, format!("{what}: {b}"), None);
        }
    }
    bad.is_empty()
}

/// S3: B1-B10. Returns the free text slot (or usize::MAX when there is none; B2 failed).
fn check_base(iso: &Iso, pack: &Pack, p: &Profile, unknown: bool, log: &mut Log) -> usize {
    let d = &iso.dol;
    let entry = be32(d, 0xE0);
    log.check(
        "B1",
        entry == p.exp_entry,
        format!(
            "DOL entry {}, expected {}",
            hex(entry as u64),
            hex(p.exp_entry as u64)
        ),
    );
    let slot = (0..7).find(|&i| be32(d, 0x90 + 4 * i) == 0);
    log.check(
        "B2",
        slot.is_some(),
        format!(
            "free text slot: {}",
            slot.map_or("none".into(), |s| s.to_string())
        ),
    );
    let (lo, hi) = (p.va as u64, p.va as u64 + p.size as u64);
    let clash: Vec<String> = iso
        .slots
        .iter()
        .filter(|s| lo < s.end() && (s.va as u64) < hi)
        .map(|s| s.slot.to_string())
        .collect();
    let what = if clash.is_empty() {
        "no loaded section".into()
    } else {
        format!("slot(s) {}", clash.join(","))
    };
    log.check(
        "B3",
        clash.is_empty(),
        format!("section [{}, {}) overlaps {what}", hex(lo), hex(hi)),
    );
    let (bss, bsz) = (be32(d, 0xD8) as u64, be32(d, 0xDC) as u64);
    log.check(
        "B4",
        bss <= lo && hi <= bss + bsz && hi <= APPLOADER_HI,
        format!(
            "section inside bss [{}, {}) and below {}",
            hex(bss),
            hex(bss + bsz),
            hex(APPLOADER_HI)
        ),
    );
    let in_text = iso
        .slots
        .iter()
        .any(|s| s.is_text() && s.va <= p.exp_entry && (p.exp_entry as u64) < s.end());
    log.check(
        "B5",
        in_text,
        format!(
            "chain target {} lies in a loaded text section",
            hex(p.exp_entry as u64)
        ),
    );
    check_sites(iso, pack, p, "B6", log);
    let cave = mex_cave(iso);
    let zero = cave.is_some_and(|c| c.iter().all(|&b| b == 0));
    if p.mex_cave {
        log.check(
            "B7",
            zero,
            format!(
                "m-ex cave [{}, {}) mapped and all zero",
                hex(MEX_CAVE_LO as u64),
                hex(MEX_CAVE_HI as u64)
            ),
        );
    } else {
        log.check("B8", !zero, "m-ex cave not all zero (vanilla-family DOL)");
    }
    if p.placement == Placement::Static {
        check_ceiling(p, iso, "B9", log);
    }
    if unknown {
        let mut bad = Vec::new();
        let mut n = 0;
        for f in pack.fingerprints_for(&p.name) {
            n += 1;
            if dol::window(d, &iso.slots, f.va, f.bytes.len()) != Some(f.bytes.as_slice()) {
                bad.push(f.name.clone());
            }
        }
        if bad.is_empty() {
            log.pass("B10", format!("{n} fingerprint windows match"));
        } else {
            log.bad(
                "B10",
                format!("fingerprints differ: {}", bad.join(", ")),
                None,
            );
        }
    }
    slot.unwrap_or(usize::MAX)
}

fn check_ceiling(p: &Profile, iso: &Iso, id: &str, log: &mut Log) -> bool {
    let ceil = ceiling(iso.fst_max);
    let top = p.static_top.unwrap_or(0) as u64;
    log.check(
        id,
        ceil >= top,
        format!(
            "static ceiling {} (FST max {} B) >= {} (end of the A4 block)",
            hex(ceil),
            iso.fst_max,
            hex(top)
        ),
    )
}

/// S4 for the Full hybrid profiles: the UCF strip blob over its span, after its SHA-256 check (§11.1).
fn apply_strip(
    d: &mut [u8],
    slots: &[dol::Slot],
    pack: &Pack,
    name: &str,
    log: &mut Log,
) -> Result<(), Stop> {
    let s = pack
        .strips
        .iter()
        .find(|s| s.profile == name)
        .expect("profiles.tsv names a strips.tsv row");
    let blob = pack.blob(&s.file, s.len, &s.new_sha, log)?;
    let off = dol::file_offset(slots, s.va, s.len);
    let ok = off.is_some_and(|o| sha256(&d[o..o + s.len]) == s.orig_sha);
    if !log.check(
        "S4",
        ok,
        format!(
            "strip span {} + {} B holds the expected bytes (SHA-256 {}...)",
            hex(s.va as u64),
            s.len,
            &s.orig_sha[..12]
        ),
    ) {
        return Err(stop(
            log,
            3,
            "the hybrid codelist differs from the listed one: not eligible for Full",
            Some("B6"),
        ));
    }
    let o = off.unwrap();
    d[o..o + s.len].copy_from_slice(blob);
    log.pass(
        "S4",
        format!(
            "wrote the strip blob {} ({} B) at {}",
            s.file,
            s.len,
            hex(s.va as u64)
        ),
    );
    Ok(())
}

/// Deletes the `.part` output on any early return.
struct PartGuard(Option<PathBuf>);

impl Drop for PartGuard {
    fn drop(&mut self) {
        if let Some(p) = self.0.take() {
            let _ = fs::remove_file(p);
        }
    }
}

pub fn default_output(source: &Path, kind: Kind) -> PathBuf {
    let stem = source
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    source.with_file_name(format!("{stem}.{}.iso", kind.suffix()))
}

/// A yes / no question for the person at the console (or a dialog); `None` = nobody to ask.
pub type Ask<'a> = Option<&'a mut dyn FnMut(&str) -> bool>;

/// The whole build: S0-S9. With `check_only`, stops after S6 (the new DOL is still built and checked).
/// `ask` is used once, for an eligible unknown DOL without `allow_unknown` (the scripts' y/N prompt).
pub fn build(o: &Options, log: &mut Log, ask: Ask) -> Result<Outcome, Stop> {
    let common = Pack::load(PackKind::Common, log)?;
    let full = Pack::load(PackKind::Full, log)?;
    let pack = if o.kind.pack() == PackKind::Full {
        &full
    } else {
        &common
    };
    let variant = o.kind.variant();
    log.text(format!(
        "== source {} ({})",
        o.source.display(),
        variant.unwrap_or("AI-only")
    ));
    let mut iso = Iso::open(&o.source, "source ISO", log)?;
    check_game_id(&iso, pack, variant, log)?;

    // ---- S2: profile
    let known = pack.known(&iso.dol_sha, variant).cloned();
    let unknown = known.is_none();
    let mut low = false;
    let pname = if let Some(k) = &known {
        log.pass(
            "S2",
            format!(
                "boot DOL {} B, SHA-256 {}: known base '{}'{} -> profile {}",
                iso.dol.len(),
                iso.dol_sha,
                k.name,
                if k.local { " (added locally)" } else { "" },
                k.profile
            ),
        );
        if o.profile.as_ref().is_some_and(|f| *f != k.profile) {
            return Err(stop(
                log,
                1,
                format!(
                    "--profile {} contradicts the known DOL (profile {})",
                    o.profile.as_ref().unwrap(),
                    k.profile
                ),
                Some("PROFILE"),
            ));
        }
        k.profile.clone()
    } else {
        if let Some((slot, p)) = release_section(&iso, &[&common, &full]) {
            log.bad(
                "B1",
                format!("DOL entry {}: this ISO already carries the Synapse {} section (slot {slot}); start from the original, un-injected ISO", hex(be32(&iso.dol, 0xE0) as u64), p.name),
                Some("B1inj"),
            );
            return Err(stop(log, 3, "already injected", None));
        }
        log.info(format!(
            "boot DOL {} B, SHA-256 {}: UNKNOWN (not in known_dols.tsv)",
            iso.dol.len(),
            iso.dol_sha
        ));
        log.report = Some(Report {
            release: pack.release_id(),
            iso: o
                .source
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default(),
            size: iso.size,
            dol_sha: iso.dol_sha.clone(),
            profile: "(none)".into(),
            checks: "failed".into(),
            plan: "-".into(),
            output: None,
        });
        let code_unknown = if o.allow_unknown { 3 } else { 4 };
        let name = if let Some(f) = &o.profile {
            log.info(format!("profile forced: {f}"));
            f.clone()
        } else {
            let (p, key, l) = classify(&iso, log);
            low = l;
            match p {
                Some(p) => {
                    log.info(format!("classified as profile {p} (BUILD_DETAILS.md 2)"));
                    p.to_string()
                }
                None => {
                    log.bad(
                        "S2",
                        "no profile applies to this DOL: ineligible",
                        Some(key),
                    );
                    return Err(stop(
                        log,
                        code_unknown,
                        "unknown DOL, and ineligible",
                        Some("UNKNOWN-INELIGIBLE"),
                    ));
                }
            }
        };
        // Full on an unknown DOL: only the profiles with fingerprints (vanilla, mex)
        if pack.kind == PackKind::Full
            && !pack
                .fingerprints
                .iter()
                .any(|f| f.profile.as_deref() == Some(name.as_str()))
        {
            log.bad(
                "S2",
                format!("profile {name}: the Full package needs a listed ISO for this base"),
                Some("FULL-KNOWN"),
            );
            return Err(stop(
                log,
                3,
                "unknown DOL: Full is not available for this base (build AI-only)",
                None,
            ));
        }
        name
    };
    let p = pack.profile(&pname, variant).cloned().ok_or_else(|| {
        stop(
            log,
            1,
            format!("no {} profile '{pname}'", pack.kind.name()),
            Some("USAGE"),
        )
    })?;
    if let Some(r) = log.report.as_mut() {
        r.profile = pname.clone();
    }
    let sec = pack.blob(&p.file, p.size as usize, &p.sha, log)?;

    // ---- S3
    let slot = check_base(&iso, pack, &p, unknown, log);
    if unknown && !o.allow_unknown {
        if log.failed > 0 {
            return Err(stop(
                log,
                4,
                format!(
                    "unknown DOL, and ineligible: it failed {} check(s) for profile {pname}",
                    log.failed
                ),
                Some("UNKNOWN-INELIGIBLE"),
            ));
        }
        log.info("eligible, but unproven: building it needs --allow-unknown-base, then a boot test (BUILD_DETAILS.md 3)");
        if low {
            log.info(format!(
                "the guess ({pname}) is uncertain: the marks above disagree"
            ));
        }
        if let Some(r) = log.report.as_mut() {
            r.checks = "all passed".into();
        }
        // only an ELIGIBLE unknown DOL reaches the question; building never registers it (add-known-base does)
        let can_ask = ask.is_some();
        let answer = match ask {
            Some(a) if !o.check_only => {
                log.text("");
                log.text("This ISO is not in the list of tested ISOs, but it passed every compatibility check.");
                log.text("The checks prove the AI can be installed safely, not that it works with this mod: boot-test the result.");
                if low {
                    log.text(format!("The guess ({pname}) is uncertain: the marks above disagree. Answer n unless you know it is {pname}."));
                }
                Some(a(&format!("Build it anyway, as profile {pname}?")))
            }
            _ => None,
        };
        match answer {
            Some(true) => log.info("building the unknown DOL (confirmed at the prompt)"),
            Some(false) => {
                log.info("not built: you answered n (nothing was written)");
                log.report = None;
                log.explain("DECLINED");
                return Err(Stop {
                    code: 4,
                    msg: "declined".into(),
                    quiet: true,
                });
            }
            None => {
                return Err(stop(
                    log,
                    4,
                    if can_ask {
                        "unknown DOL: checked only, nothing built"
                    } else {
                        "unknown DOL: re-run with --allow-unknown-base to build it"
                    },
                    Some(if can_ask {
                        "UNKNOWN-ELIGIBLE-ASK"
                    } else {
                        "UNKNOWN-ELIGIBLE"
                    }),
                ));
            }
        }
    }
    if log.failed > 0 {
        if unknown {
            log.explain("UNKNOWN-INELIGIBLE");
        }
        return Err(stop(
            log,
            3,
            format!(
                "the base failed {} check(s): not eligible for profile {pname}",
                log.failed
            ),
            None,
        ));
    }
    if let Some(r) = log.report.as_mut() {
        r.checks = "all passed".into();
    }

    // ---- S4 / S5
    let mut base = iso.dol.clone();
    if p.strip.is_some() {
        apply_strip(
            &mut base,
            &iso.slots,
            pack,
            p.strip.as_deref().unwrap(),
            log,
        )?;
    }
    let new = dol::new_dol(&base, sec, slot, p.va, p.new_entry);
    let new_sha = sha256(&new);
    if let Some(k) = &known {
        if !log.check(
            "S5",
            new_sha == k.out_sha && new.len() as u64 == k.out_size,
            format!(
                "new DOL {} B, SHA-256 {new_sha} = known_dols.tsv",
                new.len()
            ),
        ) {
            return Err(stop(
                log,
                6,
                "the new DOL differs from the expected one",
                Some("WRITE"),
            ));
        }
    } else {
        let sec_off = align(iso.dol.len() as u64, 32) as usize;
        let mut ok = be32(&new, 0xE0) == p.new_entry
            && be32(&new, 4 * slot) as usize == sec_off
            && be32(&new, 0x48 + 4 * slot) == p.va
            && be32(&new, 0x90 + 4 * slot) as usize == sec.len()
            && sha256(&new[sec_off..sec_off + sec.len()]) == p.sha
            && dol::slots(&new).len() == iso.slots.len() + 1;
        for i in (0..18).filter(|&i| i != slot) {
            for off in [4 * i, 0x48 + 4 * i, 0x90 + 4 * i] {
                ok &= be32(&new, off) == be32(&iso.dol, off);
            }
        }
        let msg = format!(
            "new DOL {} B re-parses: slot {slot} = section at {}, entry {}, other slots unchanged",
            new.len(),
            hex(p.va as u64),
            hex(p.new_entry as u64)
        );
        if !log.check("S5", ok, msg) {
            return Err(stop(
                log,
                6,
                "the new DOL does not re-parse as written",
                Some("WRITE"),
            ));
        }
    }

    // ---- S6
    let pl = plan(&iso, new.len() as u64);
    let mut out_size = iso.size.max(pl.dol + new.len() as u64);
    if pl.fst != iso.fst_off {
        out_size = out_size.max(pl.fst + align(iso.fst_size, 32));
    }
    log.pass(
        "S6",
        format!(
            "plan {:?}: DOL at {} ({} B), FST at {}; output {out_size} B",
            pl.kind,
            hex(pl.dol),
            new.len(),
            hex(pl.fst)
        ),
    );
    let room = headroom(&p, &iso);
    if let Some(r) = log.report.as_mut() {
        r.plan = format!("{:?}", pl.kind);
    }
    let mut outcome = Outcome {
        profile: pname.clone(),
        unknown,
        plan: pl,
        new_dol_size: new.len() as u64,
        new_dol_sha: new_sha.clone(),
        out: None,
        out_size,
        headroom: room,
    };
    if o.check_only {
        log.explain(if unknown {
            "OK-CHECK-UNKNOWN"
        } else {
            "OK-CHECK-KNOWN"
        });
        return Ok(outcome);
    }

    // ---- G6
    let out = o
        .out
        .clone()
        .unwrap_or_else(|| default_output(&o.source, o.kind));
    let same = fs::canonicalize(&out)
        .ok()
        .is_some_and(|a| fs::canonicalize(&o.source).is_ok_and(|b| a == b));
    if same || out == o.source {
        return Err(stop(
            log,
            1,
            "the output path is the source path",
            Some("USAGE"),
        ));
    }
    if out.exists() && !o.force {
        return Err(stop(
            log,
            1,
            format!("output exists: {} (use --force)", out.display()),
            Some("EXISTS"),
        ));
    }
    let out_dir = out
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
        .to_path_buf();
    if !out_dir.is_dir() {
        return Err(stop(
            log,
            1,
            format!("output folder does not exist: {}", out_dir.display()),
            Some("OUTDIR"),
        ));
    }
    let need = out_size + (64 << 20);
    let free = fs4::available_space(&out_dir).unwrap_or(u64::MAX);
    if !log.check(
        "G6",
        free >= need,
        format!(
            "output {}; free space {} MB, need {} MB",
            out.display(),
            thousands(free >> 20),
            thousands(need >> 20)
        ),
    ) {
        return Err(stop(log, 5, "not enough disk space", Some("SPACE")));
    }

    // ---- S7 (the FST bytes are already in memory)
    let mut part_name = out.clone().into_os_string();
    part_name.push(".part");
    let part = PathBuf::from(part_name);
    let mut guard = PartGuard(Some(part.clone()));
    let werr = |log: &mut Log, what: &str, e: std::io::Error| {
        stop(
            log,
            6,
            format!("{what} {}: {e}", part.display()),
            Some("WRITE"),
        )
    };
    log.text(format!(
        "copying the source ISO ({} MB)...",
        thousands(iso.size >> 20)
    ));
    fs::copy(&o.source, &part).map_err(|e| werr(log, "cannot copy the source to", e))?;
    {
        let mut w = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&part)
            .map_err(|e| werr(log, "cannot open", e))?;
        let mut put = |off: u64, b: &[u8]| -> std::io::Result<()> {
            w.seek(SeekFrom::Start(off))?;
            w.write_all(b)
        };
        put(pl.dol, &new).map_err(|e| werr(log, "cannot write", e))?;
        if pl.fst != iso.fst_off {
            let mut fp = iso.fst.clone();
            fp.resize(align(iso.fst_size, 32) as usize, 0);
            put(pl.fst, &fp).map_err(|e| werr(log, "cannot write", e))?;
        }
        let mut hw = [0u8; 8];
        dol::set_be32(&mut hw, 0, pl.dol as u32);
        dol::set_be32(&mut hw, 4, pl.fst as u32);
        put(0x420, &hw).map_err(|e| werr(log, "cannot write", e))?;
        w.sync_all().map_err(|e| werr(log, "cannot flush", e))?;
    }
    let moved = if pl.fst != iso.fst_off {
        format!(", the FST at {}", hex(pl.fst))
    } else {
        String::new()
    };
    log.pass(
        "S7",
        format!(
            "wrote the DOL at {}{moved}, header [0x420]={} [0x424]={}",
            hex(pl.dol),
            hex(pl.dol),
            hex(pl.fst)
        ),
    );

    // ---- S8
    verify(&mut iso, &part, &new, &new_sha, out_size, log)
        .map_err(|e| werr(log, "cannot read back", e))?;
    if log.failed > 0 {
        return Err(stop(log, 6, "read-back verification failed", Some("WRITE")));
    }
    fs::rename(&part, &out).map_err(|e| werr(log, "cannot rename", e))?;
    guard.0 = None;

    // ---- S9
    log.text("");
    log.text("== DONE");
    log.text(format!(
        "  output    : {} ({} B)",
        out.display(),
        thousands(out_size)
    ));
    log.text(format!(
        "  profile   : {pname}{} ({} DOL{})",
        variant.map(|v| format!(" {v}")).unwrap_or_default(),
        if unknown { "unknown" } else { "known" },
        if unknown {
            " - boot-test it before relying on it"
        } else {
            ""
        }
    ));
    log.text(format!(
        "  plan      : {:?}  DOL at {}, FST at {}",
        pl.kind,
        hex(pl.dol),
        hex(pl.fst)
    ));
    log.text(format!("  headroom  : {}", outcome.headroom));
    boot_checklist(&pname, log);
    if let Some(r) = log.report.as_mut() {
        r.output = Some(out.display().to_string());
    }
    log.explain(if unknown {
        "OK-BUILT-UNKNOWN"
    } else {
        "OK-BUILT-KNOWN"
    });
    outcome.out = Some(out);
    Ok(outcome)
}

/// What `check_built` found: the pack, profile and variant of the section in the ISO, and its padded boot DOL.
#[derive(Clone, Debug)]
pub struct Built {
    pub pack: PackKind,
    pub profile: String,
    pub variant: Option<String>,
    pub dol_sha: String,
    pub dol_size: u64,
}

/// BUILD_DETAILS.md 5: K1-K8 on an already-built ISO, read-only, over both packs. `Ok(None)` = no section of
/// this release in the DOL (K2 failed); any other failed K check is in `log.failed`.
pub fn check_built(path: &Path, log: &mut Log) -> Result<Option<Built>, Stop> {
    let common = Pack::load(PackKind::Common, log)?;
    let full = Pack::load(PackKind::Full, log)?;
    check_built_with(path, &common, &full, log)
}

fn check_built_with(
    path: &Path,
    common: &Pack,
    full: &Pack,
    log: &mut Log,
) -> Result<Option<Built>, Stop> {
    log.text(format!("== check-built {}", path.display()));
    let mut iso = Iso::open(path, "ISO", log)?;
    if iso.game_id != "GALE01" {
        let ok = common
            .known
            .iter()
            .chain(&full.known)
            .any(|k| k.game_id == iso.game_id);
        let msg = format!(
            "game ID {}: this release lists a base with that game ID",
            iso.game_id
        );
        if !ok {
            log.bad("G3", msg, Some("G3id"));
            return Err(stop(
                log,
                3,
                format!("game ID {} is accepted only for a listed ISO", iso.game_id),
                None,
            ));
        }
        log.pass("G3", msg);
    }
    log.pass("K1", "G1-G5 passed");
    // Profiles can share address and size, so a slot is damaged only when it matches a candidate's address and
    // size but none of their SHA-256s.
    let mut found: Option<(&Pack, Profile, usize)> = None;
    for s in iso.slots.iter().filter(|s| s.is_text()) {
        let cands: Vec<(&Pack, &Profile)> = [common, full]
            .into_iter()
            .flat_map(|pk| pk.profiles.iter().map(move |p| (pk, p)))
            .filter(|(_, p)| p.va == s.va && p.size == s.size)
            .collect();
        if cands.is_empty() {
            continue;
        }
        let sha = sha256(&iso.dol[s.off as usize..(s.off + s.size) as usize]);
        if let Some((pk, p)) = cands.iter().find(|(_, p)| p.sha == sha) {
            found = Some((*pk, (*p).clone(), s.slot));
        } else {
            let names: Vec<String> = cands.iter().map(|(_, p)| label(p)).collect();
            log.bad(
                "K2",
                format!(
                    "slot {} at {} has the size of the {} section but its SHA-256 differs: the section is damaged",
                    s.slot,
                    hex(s.va as u64),
                    names.join(" / ")
                ),
                Some("K2bad"),
            );
        }
    }
    let padded = align(iso.dol.len() as u64, 32);
    let full_dol = if iso.dol_off + padded <= iso.size {
        read_at(&mut iso.file, iso.dol_off, padded as usize).unwrap_or_else(|_| iso.dol.clone())
    } else {
        iso.dol.clone()
    };
    let dol_sha = sha256(&full_dol);
    let as_built = common
        .known
        .iter()
        .chain(&full.known)
        .any(|k| k.out_sha == dol_sha);
    let Some((pk, p, slot)) = found else {
        if log.failed == 0 {
            log.bad(
                "K2",
                "no Synapse section from this release in the DOL (not built by this release, or a tool rewrote the DOL)",
                Some("K2none"),
            );
        }
        log.info(if as_built {
            "K8 DOL as built"
        } else {
            "K8 DOL differs from the build (another tool edited it, or not built by this release)"
        });
        return Ok(None);
    };
    log.pass(
        "K2",
        format!(
            "slot {slot}: the {} section ({} B at {}), SHA-256 matches",
            label(&p),
            p.size,
            hex(p.va as u64)
        ),
    );
    let entry = be32(&iso.dol, 0xE0);
    log.check(
        "K3",
        entry == p.new_entry,
        format!(
            "DOL entry {}, expected {} (the Synapse stub)",
            hex(entry as u64),
            hex(p.new_entry as u64)
        ),
    );
    let in_text = iso
        .slots
        .iter()
        .any(|s| s.is_text() && s.va <= p.exp_entry && (p.exp_entry as u64) < s.end());
    log.check(
        "K4",
        in_text,
        format!(
            "chain target {} still lies in a loaded text section",
            hex(p.exp_entry as u64)
        ),
    );
    check_sites(&iso, pk, &p, "K5", log);
    if p.mex_cave {
        let zero = mex_cave(&iso).is_some_and(|c| c.iter().all(|&b| b == 0));
        log.check(
            "K6",
            zero,
            format!(
                "m-ex cave [{}, {}) still all zero",
                hex(MEX_CAVE_LO as u64),
                hex(MEX_CAVE_HI as u64)
            ),
        );
    }
    if p.placement == Placement::Static && !check_ceiling(&p, &iso, "K7", log) {
        log.text("       THIS ISO WILL HANG AT BOOT: the FST grew past the static limit after the injection.");
        log.text("       Re-inject from the un-injected modded copy (it will be refused too: too much content for");
        log.text("       the static layout of this base, BUILD_DETAILS.md 4).");
    }
    log.info(if as_built {
        "K8 DOL as built"
    } else {
        "K8 DOL differs from the build (another tool edited it; K2-K6 decide whether that matters)"
    });
    log.info(format!(
        "profile {}; FST {} B (max {} B); content headroom: {}",
        label(&p),
        iso.fst_size,
        iso.fst_max,
        headroom(&p, &iso)
    ));
    Ok(Some(Built {
        pack: pk.kind,
        profile: p.name.clone(),
        variant: p.variant.clone(),
        dol_sha,
        dol_size: full_dol.len() as u64,
    }))
}

fn label(p: &Profile) -> String {
    match &p.variant {
        Some(v) => format!("{} {v}", p.name),
        None => format!("{} AI-only", p.name),
    }
}

/// Days since 1970-01-01 -> (y, m, d) (proleptic Gregorian; H. Hinnant's civil_from_days).
fn civil(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

fn today() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let (y, m, d) = civil((secs / 86_400) as i64);
    format!("{y:04}-{m:02}-{d:02}")
}

/// Adds an UNKNOWN but eligible original DOL to this machine's local known list. Refuses unless the built ISO
/// passes K1-K8, the original passes S1-S3 as an unknown DOL of the built section's profile (fingerprints
/// included), the built ISO's DOL is exactly the one the core makes from the original (R1), and the user confirms a
/// boot test (`ask`; `None` = no console: refused). Returns whether a row was added.
pub fn add_known_base(
    original: &Path,
    built: &Path,
    profile: Option<&str>,
    log: &mut Log,
    ask: Ask,
) -> Result<bool, Stop> {
    let common = Pack::load(PackKind::Common, log)?;
    let full = Pack::load(PackKind::Full, log)?;
    let b = check_built_with(built, &common, &full, log)?;
    let Some(b) = b.filter(|_| log.failed == 0) else {
        return Err(stop(
            log,
            3,
            "the built ISO failed check-built: not added",
            None,
        ));
    };
    let pack = if b.pack == PackKind::Full {
        &full
    } else {
        &common
    };
    let variant = b.variant.as_deref();
    log.text("");
    log.text(format!(
        "== add-known-base {} ({})",
        original.display(),
        variant.unwrap_or("AI-only")
    ));
    let iso = Iso::open(original, "original ISO", log)?;
    check_game_id(&iso, pack, variant, log)?;
    if let Some(k) = pack.known(&iso.dol_sha, variant) {
        log.pass(
            "S2",
            format!(
                "boot DOL SHA-256 {} is already known: '{}' (profile {}{}); nothing to add",
                iso.dol_sha,
                k.name,
                k.profile,
                if k.local { ", added locally" } else { "" }
            ),
        );
        return Ok(false);
    }
    if let Some((_, p)) = release_section(&iso, &[&common, &full]) {
        log.bad(
            "B1",
            format!(
                "this ISO already carries the Synapse {} section: add-known-base takes the ORIGINAL ISO (without Synapse); the built one goes in --built",
                label(p)
            ),
            Some("B1inj"),
        );
        return Err(stop(log, 3, "the original is an injected ISO", None));
    }
    let pname = match profile {
        Some(f) => {
            log.info(format!("profile forced: {f}"));
            f.to_string()
        }
        None => match classify(&iso, log) {
            (Some(p), _, _) => p.to_string(),
            (None, key, _) => {
                log.bad(
                    "S2",
                    "no profile applies to this DOL: ineligible",
                    Some(key),
                );
                return Err(stop(
                    log,
                    3,
                    "ineligible base: not added",
                    Some("UNKNOWN-INELIGIBLE"),
                ));
            }
        },
    };
    if pack.kind == PackKind::Full
        && !pack
            .fingerprints
            .iter()
            .any(|f| f.profile.as_deref() == Some(pname.as_str()))
    {
        log.bad(
            "S2",
            format!("profile {pname}: the Full package needs a listed ISO for this base"),
            Some("FULL-KNOWN"),
        );
        return Err(stop(
            log,
            3,
            "Full is not available for an unknown DOL of this base: not added",
            None,
        ));
    }
    let Some(p) = pack.profile(&pname, variant).cloned() else {
        return Err(stop(
            log,
            1,
            format!("no {} profile '{pname}'", pack.kind.name()),
            Some("USAGE"),
        ));
    };
    log.info(format!(
        "unknown boot DOL {} B, SHA-256 {}: profile {}",
        iso.dol.len(),
        iso.dol_sha,
        label(&p)
    ));
    let sec = pack.blob(&p.file, p.size as usize, &p.sha, log)?;
    let slot = check_base(&iso, pack, &p, true, log);
    if log.failed > 0 {
        return Err(stop(
            log,
            3,
            format!(
                "the original failed {} check(s) for profile {pname}: not added",
                log.failed
            ),
            Some("UNKNOWN-INELIGIBLE"),
        ));
    }
    let mut base = iso.dol.clone();
    if let Some(sp) = p.strip.as_deref() {
        apply_strip(&mut base, &iso.slots, pack, sp, log)?;
    }
    let new = dol::new_dol(&base, sec, slot, p.va, p.new_entry);
    let new_sha = sha256(&new);
    log.info(format!(
        "this release builds a {} B DOL with SHA-256 {new_sha} from it",
        new.len()
    ));
    let same = b.profile == pname && b.dol_sha == new_sha && b.dol_size == new.len() as u64;
    let msg = format!(
        "built ISO DOL ({} B, SHA-256 {}, profile {}) is the one built from the original",
        b.dol_size, b.dol_sha, b.profile
    );
    if !log.check("R1", same, msg) {
        return Err(stop(
            log,
            3,
            "the built ISO was not built from this original by this release (or was changed afterwards): not added",
            None,
        ));
    }
    let Some(ask) = ask else {
        return Err(stop(
            log,
            1,
            "add-known-base asks you to confirm a boot test: run it from a console",
            Some("USAGE"),
        ));
    };
    log.text("");
    let bname = built
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    log.text(format!(
        "Boot-test {bname} first (Dolphin; MMU on, Fastmem off):"
    ));
    log.text("  it boots; a type-4 CPU attacks and wavedashes; Z + D-Up opens the menu; the mod's own features still work.");
    if !ask("Did the built ISO pass that boot test?") {
        log.info("not confirmed: nothing added");
        return Ok(false);
    }
    let stem = original
        .file_stem()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let name = format!("{stem} (added locally {})", today());
    let size = new.len().to_string();
    let mut cols = vec![iso.dol_sha.as_str(), pname.as_str()];
    if let Some(v) = variant {
        cols.push(v);
    }
    cols.extend([name.as_str(), size.as_str(), new_sha.as_str()]);
    let path = crate::local::append(pack.kind, &cols).map_err(|e| {
        stop(
            log,
            6,
            format!("cannot write the local known list: {e}"),
            Some("WRITE"),
        )
    })?;
    log.pass(
        "R2",
        format!(
            "added to {}: '{name}', profile {}",
            path.display(),
            label(&p)
        ),
    );
    log.text("Builds from this ISO are now treated as known, and their new DOL is checked byte for byte.");
    log.text("If you can, please also open an issue titled \"Tested ISO: mod_name\" with the REPORT block of the build,");
    log.text("so the ISO can be added for everyone in a later release. Thank you!");
    log.text("  https://github.com/w3irDv/20XX-Synapse_Engine/issues/new");
    Ok(true)
}

/// S8: V1-V5 on the written file.
fn verify(
    iso: &mut Iso,
    part: &Path,
    new: &[u8],
    new_sha: &str,
    out_size: u64,
    log: &mut Log,
) -> std::io::Result<()> {
    let mut v = fs::File::open(part)?;
    let vh = read_at(&mut v, 0, 0x440)?;
    let v1 = vh[..8] == iso.head[..8]
        && [0x1C, 0x428, 0x42C]
            .iter()
            .all(|&o| be32(&vh, o) == be32(&iso.head, o));
    log.check(
        "V1",
        v1,
        "disc ID, magic, FST size and FST max size unchanged",
    );
    let (dol_at, fst_at) = (be32(&vh, 0x420) as u64, be32(&vh, 0x424) as u64);
    let vd = read_at(&mut v, dol_at, new.len())?;
    log.check(
        "V2",
        sha256(&vd) == new_sha && dol::dol_size(&vd) + 32 > new.len() as u64,
        format!("DOL at {} reads back with SHA-256 {new_sha}", hex(dol_at)),
    );
    let vf = read_at(&mut v, fst_at, iso.fst_size as usize)?;
    log.check(
        "V3",
        vf == iso.fst,
        format!("FST at {} reads back unchanged", hex(fst_at)),
    );
    let mut sorted = iso.files.clone();
    sorted.sort_by_key(|e| e.start);
    let mut v4 = true;
    if let (Some(first), Some(last)) = (sorted.first().copied(), sorted.last().copied()) {
        for f in [first, last] {
            let n = (f.end - f.start).min(1 << 20) as usize;
            v4 &= read_at(&mut v, f.start, n)? == read_at(&mut iso.file, f.start, n)?;
        }
        log.check(
            "V4",
            v4,
            format!(
                "first and last file ({}, {}) read back identical",
                hex(first.start),
                hex(last.start)
            ),
        );
    }
    let len = v.metadata()?.len();
    log.check(
        "V5",
        len == out_size,
        format!("output size {len} B = planned {out_size} B"),
    );
    Ok(())
}

fn boot_checklist(profile: &str, log: &mut Log) {
    log.text("");
    log.text("Boot check (Dolphin; MMU on, Fastmem off):");
    log.text("  1. VS mode, set a CPU to type 4 (any level): it attacks and wavedashes.");
    log.text("  2. Z + D-Up opens the CPU config menu; the D-pad changes the CPU type (toast).");
    if profile == "vanilla" {
        log.text("  3. Tournament Mode still starts from the main menu.");
    }
    log.text("Adding stages or characters: add them BEFORE injecting, and keep the un-injected copy (BUILD_DETAILS.md 4).");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thousands_groups() {
        assert_eq!(thousands(0), "0");
        assert_eq!(thousands(1234567), "1,234,567");
        assert_eq!(thousands(999), "999");
    }

    #[test]
    fn civil_dates() {
        assert_eq!(civil(0), (1970, 1, 1));
        assert_eq!(civil(11_016), (2000, 2, 29));
        assert_eq!(civil(20_753), (2026, 10, 27));
    }

    #[test]
    fn output_names() {
        let s = Path::new("C:/x/Melee.iso");
        assert_eq!(
            default_output(s, Kind::AiOnly),
            Path::new("C:/x/Melee.aionly.iso")
        );
        assert_eq!(
            default_output(s, Kind::Full { wii_non_crt: true }),
            Path::new("C:/x/Melee.full.wii-non-crt.iso")
        );
    }
}
