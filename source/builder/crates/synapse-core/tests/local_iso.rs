//! Local-only (needs real ISOs, never run in CI): `cargo test --release -p synapse-core -- --ignored` with
//! SYNAPSE_TEST_ORIGINAL = an ISO whose boot DOL no pack lists (but eligible for AI-only `vanilla`),
//! SYNAPSE_TEST_BUILT = the ISO `synapse-cli build --allow-unknown-base` made from it,
//! SYNAPSE_CONFIG_DIR = a scratch dir (the local known list is written there and removed at the end).

use std::path::PathBuf;
use synapse_core::local;
use synapse_core::log::Log;
use synapse_core::pack::PackKind;
use synapse_core::procedure::{self, Kind, Options};

fn env(name: &str) -> PathBuf {
    PathBuf::from(std::env::var_os(name).unwrap_or_else(|| panic!("set {name}")))
}

#[test]
#[ignore]
fn add_known_base_then_the_original_builds_as_known() {
    let (original, built) = (env("SYNAPSE_TEST_ORIGINAL"), env("SYNAPSE_TEST_BUILT"));
    env("SYNAPSE_CONFIG_DIR");
    let list = local::path(PackKind::Common).unwrap();
    let _ = std::fs::remove_file(&list);
    let mut o = Options {
        source: original.clone(),
        out: None,
        kind: Kind::AiOnly,
        profile: None,
        allow_unknown: false,
        check_only: false,
        force: false,
    };

    // an eligible unknown DOL: the y/N question, answered n = exit 4, quiet, DECLINED recap, no REPORT, no output
    let mut no = |_: &str| false;
    let mut log = Log::default();
    let e = procedure::build(&o, &mut log, Some(&mut no)).unwrap_err();
    assert!(e.code == 4 && e.quiet && log.report.is_none());
    assert!(log.plain.iter().any(|t| t.starts_with("Nothing was built")));
    let mut part = procedure::default_output(&original, Kind::AiOnly).into_os_string();
    part.push(".part");
    assert!(!PathBuf::from(part).exists());

    // boot test not confirmed: nothing written
    let mut log = Log::default();
    assert!(!procedure::add_known_base(&original, &built, None, &mut log, Some(&mut no)).unwrap());
    assert!(!list.exists());

    // confirmed: one row
    let mut yes = |_: &str| true;
    let mut log = Log::default();
    assert!(procedure::add_known_base(&original, &built, None, &mut log, Some(&mut yes)).unwrap());
    let text = std::fs::read_to_string(&list).unwrap();
    assert_eq!(text.lines().filter(|l| !l.starts_with('#')).count(), 1);

    // a second time: already known, nothing added
    let mut log = Log::default();
    assert!(!procedure::add_known_base(&original, &built, None, &mut log, Some(&mut yes)).unwrap());

    // the original is now a known DOL: S2 names the local row and S5 checks the exact out DOL
    o.check_only = true;
    let mut log = Log::default();
    let out = procedure::build(&o, &mut log, None).unwrap();
    assert!(!out.unknown);
    assert!(
        log.entries
            .iter()
            .any(|e| e.id == "S2" && e.msg.contains("(added locally)"))
    );
    assert!(
        log.entries
            .iter()
            .any(|e| e.id == "S5" && e.msg.contains("= known_dols.tsv"))
    );

    std::fs::remove_file(&list).unwrap();
}
