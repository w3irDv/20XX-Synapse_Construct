//! Developer commands. `cargo xtask oracle` = the core's byte-identity test on golden ISOs (local only:
//! ISOs never go to CI). It never runs the pack generator: it compares the
//! core's output with the packs' own records.

use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, Instant};
use synapse_core::log::{Log, Tag};
use synapse_core::pack::{Pack, PackKind};
use synapse_core::procedure::{self, Kind, Options};

const USAGE: &str = "usage: cargo xtask oracle [--iso-dir DIR] [--build-isos DIR]
       cargo xtask goldens

  goldens  print every golden ISO hash in release/<pack>/PROVENANCE.md: stem, variant, SHA-256 (tab-separated, sorted)
  oracle   every ISO in --iso-dir (default ../iso) whose boot DOL a pack lists is checked by the core for AI-only and
           both Full variants: the new DOL must equal the pack's out_dol_sha256 (S5). With --build-isos, each
           (ISO, variant) that has a golden ISO hash in release/<pack>/PROVENANCE.md (local, not published) is also
           built in full into DIR, hashed, compared and deleted (one ISO on disk at a time). A tested mod kept only as
           a DOL stand-in (DIR/dols/<ISO name>.dol + .meta, release_tables.py standin) gets the same DOL checks on a
           synthetic disc around its DOL (S1-S5; no plan, no golden ISO).";

const KINDS: [Kind; 3] = [
    Kind::AiOnly,
    Kind::Full { wii_non_crt: false },
    Kind::Full { wii_non_crt: true },
];

fn label(k: Kind) -> &'static str {
    k.variant().unwrap_or("aionly")
}

/// Golden ISO hashes from the PROVENANCE.md verify tables: (source ISO stem, variant label) -> SHA-256.
fn goldens(release: &Path) -> BTreeMap<(String, String), String> {
    let mut g = BTreeMap::new();
    for (pack, full) in [("common", false), ("full", true)] {
        let Ok(text) = fs::read_to_string(release.join(pack).join("PROVENANCE.md")) else {
            continue;
        };
        for line in text.lines().filter(|l| l.contains(".release-verify.iso`")) {
            let cols: Vec<&str> = line
                .split('|')
                .map(|c| c.trim().trim_matches('`'))
                .collect();
            // common: | profile | iso | plan | size | verify | sha |    full: | profile | variant | iso | plan | ... | sha |
            let (name, variant) = if full {
                (cols[3], cols[2].to_string())
            } else {
                (cols[2], "aionly".to_string())
            };
            let mut stem = name.trim_end_matches(".release-verify.iso").to_string();
            if full {
                stem = stem
                    .trim_end_matches(&format!(".{}.{variant}", cols[1]))
                    .to_string();
            }
            g.insert((stem, variant), cols[cols.len() - 2].to_string());
        }
    }
    g
}

fn sha_file(p: &Path) -> std::io::Result<String> {
    let mut f = fs::File::open(p)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 22];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(format!("{:x}", h.finalize()))
}

/// A tested mod kept as a DOL stand-in: its ISO's stem, its boot DOL, and the two disc values the checks read.
struct StandIn {
    stem: String,
    dol: Vec<u8>,
    game_id: String,
    fst_max: u32,
}

/// The DOL stand-ins in `<iso_dir>/dols/` whose ISO is not in `iso_dir` itself.
/// The `.meta` next to each stand-in must name the ISO and hold the DOL's size and SHA-256.
fn standins(iso_dir: &Path) -> Result<Vec<StandIn>, String> {
    let dir = iso_dir.join("dols");
    let Ok(rd) = fs::read_dir(&dir) else {
        return Ok(Vec::new());
    };
    let mut metas: Vec<PathBuf> = rd
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "meta"))
        .collect();
    metas.sort();
    let mut out = Vec::new();
    for meta in metas {
        let text = fs::read_to_string(&meta).map_err(|e| format!("{}: {e}", meta.display()))?;
        let mut lines = text.lines();
        let (Some(head), Some(vals)) = (lines.next(), lines.next()) else {
            return Err(format!(
                "{}: expected a header and a value line",
                meta.display()
            ));
        };
        let m: BTreeMap<&str, &str> = head.split('\t').zip(vals.split('\t')).collect();
        let field = |k: &str| {
            m.get(k)
                .copied()
                .ok_or_else(|| format!("{}: no '{k}' column", meta.display()))
        };
        let iso = field("iso")?;
        if iso_dir.join(iso).exists() {
            continue; // the real ISO is here: checked as an ISO
        }
        let dpath = meta.with_extension("dol");
        let dol = fs::read(&dpath).map_err(|e| format!("{}: {e}", dpath.display()))?;
        if format!("{:x}", Sha256::digest(&dol)) != field("dol_sha256")?
            || dol.len().to_string() != field("dol_size")?
        {
            return Err(format!(
                "{}: does not match its .meta (size or SHA-256)",
                dpath.display()
            ));
        }
        let fst_max = field("fst_max")?
            .parse()
            .map_err(|_| format!("{}: bad fst_max", meta.display()))?;
        let stem = Path::new(iso)
            .file_stem()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        out.push(StandIn {
            stem,
            dol,
            game_id: field("game_id")?.to_string(),
            fst_max,
        });
    }
    Ok(out)
}

/// A minimal disc image around a stand-in DOL, enough for the core's S1-S5: header (game id, revision 2, magic,
/// DOL / FST offsets, the real disc's FST max), the DOL, a one-entry FST. Its layout is not the real disc's.
fn standin_disc(dol: &[u8], game_id: &str, fst_max: u32, path: &Path) -> std::io::Result<()> {
    const DOL_OFF: usize = 0x2460;
    let fst_off = (DOL_OFF + dol.len() + 31) & !31;
    let mut img = vec![0u8; fst_off + 16];
    let id = game_id.as_bytes();
    img[..id.len().min(6)].copy_from_slice(&id[..id.len().min(6)]);
    img[7] = 2;
    let put =
        |img: &mut [u8], off: usize, v: u32| img[off..off + 4].copy_from_slice(&v.to_be_bytes());
    put(&mut img, 0x1C, 0xC233_9F3D);
    put(&mut img, 0x420, DOL_OFF as u32);
    put(&mut img, 0x424, fst_off as u32);
    put(&mut img, 0x428, 16);
    put(&mut img, 0x42C, fst_max);
    img[DOL_OFF..DOL_OFF + dol.len()].copy_from_slice(dol);
    img[fst_off] = 1; // root directory
    put(&mut img, fst_off + 8, 1); // one entry: the root
    fs::write(path, img)
}

/// S2 passed = the pack lists this DOL (for the kind being built).
fn s2_known(log: &Log) -> Option<String> {
    log.entries
        .iter()
        .find(|e| e.tag == Tag::Pass && e.id == "S2")
        .map(|e| e.msg.clone())
}

fn oracle(iso_dir: &Path, build_dir: Option<&Path>) -> Result<(), String> {
    let release = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../release");
    let gold = goldens(&release);
    let mut plog = Log::default();
    let packs = [
        Pack::load(PackKind::Common, &mut plog).map_err(|e| e.msg)?,
        Pack::load(PackKind::Full, &mut plog).map_err(|e| e.msg)?,
    ];
    let mut isos: Vec<PathBuf> = fs::read_dir(iso_dir)
        .map_err(|e| format!("{}: {e}", iso_dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x.eq_ignore_ascii_case("iso")))
        .collect();
    isos.sort();
    // (source, ISO stem, is a DOL stand-in on a synthetic disc)
    let mut sources: Vec<(PathBuf, String, bool)> = isos
        .iter()
        .map(|p| {
            (
                p.clone(),
                p.file_stem().unwrap().to_string_lossy().into_owned(),
                false,
            )
        })
        .collect();
    let tmp = build_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(std::env::temp_dir);
    for s in standins(iso_dir)? {
        let p = tmp.join(format!("{}.standin.iso", s.stem));
        standin_disc(&s.dol, &s.game_id, s.fst_max, &p)
            .map_err(|e| format!("{}: {e}", p.display()))?;
        sources.push((p, s.stem, true));
    }
    let (mut pass, mut fail, mut built) = (0, 0, 0);
    let (mut dol_time, mut iso_time) = (Duration::ZERO, Duration::ZERO);
    let mut seen: Vec<(String, Option<&str>)> = Vec::new();
    for (iso, stem, standin) in &sources {
        let (stem, standin) = (stem.clone(), *standin);
        for kind in KINDS {
            let mut o = Options {
                source: iso.clone(),
                out: None,
                kind,
                profile: None,
                allow_unknown: false,
                check_only: true,
                force: false,
            };
            let mut log = Log::default();
            let t = Instant::now();
            let checked = procedure::build(&o, &mut log, None);
            dol_time += t.elapsed();
            match checked {
                Ok(out) if !out.unknown => {
                    pass += 1;
                    seen.push((s2_known(&log).unwrap_or_default(), kind.variant()));
                    let plan = if standin {
                        "DOL stand-in, no plan".to_string()
                    } else {
                        format!("{:?}", out.plan.kind)
                    };
                    println!(
                        "[PASS] {stem} {}: {} -> out DOL {}... = out_dol_sha256 ({plan})",
                        label(kind),
                        out.profile,
                        &out.new_dol_sha[..16],
                    );
                    if standin {
                        continue; // a synthetic disc: no golden ISO
                    }
                    let (Some(dir), Some(want)) = (
                        build_dir,
                        gold.get(&(stem.clone(), label(kind).to_string())),
                    ) else {
                        continue;
                    };
                    let dest = dir.join(format!("{stem}.{}.oracle.iso", label(kind)));
                    o.check_only = false;
                    o.out = Some(dest.clone());
                    o.force = true;
                    let mut blog = Log::default();
                    let t = Instant::now();
                    let r = procedure::build(&o, &mut blog, None);
                    let build_s = t.elapsed();
                    let t = Instant::now();
                    let got = r.as_ref().ok().and_then(|_| sha_file(&dest).ok());
                    let hash_s = t.elapsed();
                    let t = Instant::now();
                    // the built ISO must also pass check-built (K1-K8) and name the same profile / variant
                    let mut klog = Log::default();
                    let k = procedure::check_built(&dest, &mut klog);
                    let check_s = t.elapsed();
                    iso_time += build_s + hash_s + check_s;
                    let k_ok = matches!(&k, Ok(Some(b)) if klog.failed == 0
                        && b.profile == out.profile && b.variant.as_deref() == kind.variant());
                    let _ = fs::remove_file(&dest);
                    built += 1;
                    if k_ok {
                        pass += 1;
                        println!(
                            "[PASS] {stem} {}: check-built K1-K8 pass, section {} {}",
                            label(kind),
                            out.profile,
                            label(kind)
                        );
                    } else {
                        fail += 1;
                        let fails: Vec<String> = klog
                            .entries
                            .iter()
                            .filter(|x| x.tag == Tag::Fail)
                            .map(|x| x.line())
                            .collect();
                        println!(
                            "[FAIL] {stem} {}: check-built {}",
                            label(kind),
                            fails.join("; ")
                        );
                    }
                    if got.as_deref() == Some(want.as_str()) {
                        pass += 1;
                        println!(
                            "[PASS] {stem} {}: built ISO = golden {}... (build {:.1} s, hash {:.1} s, check-built {:.1} s)",
                            label(kind),
                            &want[..16],
                            build_s.as_secs_f32(),
                            hash_s.as_secs_f32(),
                            check_s.as_secs_f32()
                        );
                    } else {
                        fail += 1;
                        let why = r.err().map(|e| e.msg).or(got).unwrap_or_default();
                        println!(
                            "[FAIL] {stem} {}: built ISO {why} != golden {want}",
                            label(kind)
                        );
                    }
                }
                Ok(_) => {}
                Err(e) if s2_known(&log).is_some() => {
                    fail += 1;
                    let fails: Vec<String> = log
                        .entries
                        .iter()
                        .filter(|x| x.tag == Tag::Fail)
                        .map(|x| x.line())
                        .collect();
                    println!(
                        "[FAIL] {stem} {}: known DOL, but {} ({})",
                        label(kind),
                        e.msg,
                        fails.join("; ")
                    );
                }
                Err(_) => println!(
                    "[SKIP] {stem} {}: not a listed DOL of this pack",
                    label(kind)
                ),
            }
        }
    }
    for (p, _, standin) in &sources {
        if *standin {
            let _ = fs::remove_file(p);
        }
    }
    // coverage: every known_dols.tsv row should have met an ISO (or a DOL stand-in)
    let mut missing = 0;
    for p in &packs {
        for k in &p.known {
            if !seen
                .iter()
                .any(|(m, v)| m.contains(&k.in_sha) && *v == k.variant.as_deref())
            {
                missing += 1;
                println!(
                    "[INFO] not covered (no ISO with this DOL in {}): {} {} '{}'",
                    iso_dir.display(),
                    p.kind.name(),
                    k.variant.as_deref().unwrap_or("aionly"),
                    k.name
                );
            }
        }
    }
    println!(
        "\noracle: {pass} PASS, {fail} FAIL, {built} ISO(s) built; {missing} known_dols row(s) without an ISO here"
    );
    println!(
        "oracle times: DOL checks {:.0} s, ISOs {:.0} s",
        dol_time.as_secs_f32(),
        iso_time.as_secs_f32()
    );
    if fail > 0 {
        Err(format!("{fail} check(s) failed"))
    } else {
        Ok(())
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("goldens") {
        let release = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../release");
        for ((stem, variant), sha) in goldens(&release) {
            println!("{stem}\t{variant}\t{sha}");
        }
        return ExitCode::SUCCESS;
    }
    if args.first().map(String::as_str) != Some("oracle") {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    }
    let mut iso_dir = PathBuf::from("../iso");
    let mut build_dir = None;
    let mut it = args.iter().skip(1);
    while let Some(a) = it.next() {
        match (a.as_str(), it.next()) {
            ("--iso-dir", Some(v)) => iso_dir = PathBuf::from(v),
            ("--build-isos", Some(v)) => build_dir = Some(PathBuf::from(v)),
            _ => {
                eprintln!("{USAGE}");
                return ExitCode::from(2);
            }
        }
    }
    match oracle(&iso_dir, build_dir.as_deref()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("oracle: {e}");
            ExitCode::from(1)
        }
    }
}
