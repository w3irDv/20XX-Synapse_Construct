//! Embeds the two release packs (AI-only `common`, `full`) and refuses to build when a file
//! does not match its pack's `SHA256SUMS`.
//!
//! The packs are found in either layout: the dev repo (`builder/`, `release/common`, `release/full`)
//! or the public repo (`source/builder/`, `scripts/common`, `source/full`).
use sha2::{Digest, Sha256};
use std::{
    env,
    fmt::Write as _,
    fs,
    path::{Path, PathBuf},
};

/// The first candidate folder of `pack` that holds a `SHA256SUMS`.
fn pack_dir(root: &Path, pack: &str) -> PathBuf {
    let candidates = match pack {
        "common" => [root.join("release/common"), root.join("../scripts/common")],
        _ => [root.join("release/full"), root.join("full")],
    };
    for c in &candidates {
        if c.join("SHA256SUMS").is_file() {
            return c.canonicalize().unwrap();
        }
    }
    panic!("pack {pack} not found; looked in {candidates:?}");
}

fn main() {
    // dev repo: the repo root; public repo: source/
    let root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../..");
    let mut code = String::new();
    for (konst, pack) in [("COMMON", "common"), ("FULL", "full")] {
        let dir = pack_dir(&root, pack);
        let sums_path = dir.join("SHA256SUMS");
        println!("cargo:rerun-if-changed={}", sums_path.display());
        let sums = fs::read_to_string(&sums_path)
            .unwrap_or_else(|e| panic!("{}: {e}", sums_path.display()));
        writeln!(
            code,
            "pub static {konst}_SUMS: &str = include_str!({:?});",
            sums_path.display().to_string()
        )
        .unwrap();
        writeln!(code, "pub static {konst}: &[(&str, &[u8])] = &[").unwrap();
        for line in sums.lines().filter(|l| !l.trim().is_empty()) {
            let (hash, rel) = line
                .split_once("  ")
                .unwrap_or_else(|| panic!("{pack}/SHA256SUMS: bad line {line:?}"));
            let path = dir.join(rel);
            println!("cargo:rerun-if-changed={}", path.display());
            let bytes = fs::read(&path).unwrap_or_else(|e| panic!("{pack}/{rel}: {e}"));
            let got = format!("{:x}", Sha256::digest(&bytes));
            assert_eq!(
                got,
                hash.to_lowercase(),
                "{pack}/{rel}: SHA-256 does not match SHA256SUMS"
            );
            writeln!(
                code,
                "    ({rel:?}, include_bytes!({:?})),",
                path.display().to_string()
            )
            .unwrap();
        }
        writeln!(code, "];").unwrap();
    }
    fs::write(
        PathBuf::from(env::var("OUT_DIR").unwrap()).join("packs.rs"),
        code,
    )
    .unwrap();
}
