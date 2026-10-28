//! The two embedded release packs: `release/common` (AI-only) and `release/full`
//! (Full). `build.rs` checked them against SHA256SUMS at compile time; S0 re-hashes.

use crate::dol::sha256;
use crate::local;
use crate::log::{Log, Stop, stop};

mod embedded {
    include!(concat!(env!("OUT_DIR"), "/packs.rs"));
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PackKind {
    Common,
    Full,
}

impl PackKind {
    /// The pack's name in messages (its folder differs between the dev and the public repo).
    pub fn name(self) -> &'static str {
        match self {
            PackKind::Common => "AI-only pack",
            PackKind::Full => "Full pack",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Placement {
    Static,
    Dynamic,
}

#[derive(Clone, Debug)]
pub struct Profile {
    pub name: String,
    /// `None` in the AI-only pack; `full` / `full.wii-non-crt` in the Full pack.
    pub variant: Option<String>,
    pub file: String,
    pub size: u32,
    pub sha: String,
    pub va: u32,
    pub new_entry: u32,
    pub exp_entry: u32,
    pub placement: Placement,
    pub mex_cave: bool,
    pub static_top: Option<u32>,
    /// `strips.tsv` profile whose blob S4 writes first (hybrid profiles of the Full pack).
    pub strip: Option<String>,
}

#[derive(Clone, Debug)]
pub struct Known {
    pub in_sha: String,
    pub profile: String,
    pub variant: Option<String>,
    pub name: String,
    pub out_size: u64,
    pub out_sha: String,
    pub game_id: String,
    /// Added on this machine (`add-known-base`), not part of the release.
    pub local: bool,
}

/// A word the payload relies on: `hooks.tsv` (AI-only, every profile) or a `sites.tsv` row (Full, per profile).
#[derive(Clone, Debug)]
pub struct Site {
    pub profile: Option<String>,
    pub va: u32,
    pub word: u32,
    pub kind: String,
    pub name: String,
    /// A plain 04's new value: a DOL already holding it passes too.
    pub poke_word: Option<u32>,
}

#[derive(Clone, Debug)]
pub struct Fingerprint {
    pub profile: Option<String>,
    pub name: String,
    pub va: u32,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct Strip {
    pub profile: String,
    pub va: u32,
    pub len: usize,
    pub orig_sha: String,
    pub new_sha: String,
    pub file: String,
}

pub struct Pack {
    pub kind: PackKind,
    files: &'static [(&'static str, &'static [u8])],
    sums: &'static str,
    pub profiles: Vec<Profile>,
    pub known: Vec<Known>,
    pub sites: Vec<Site>,
    pub fingerprints: Vec<Fingerprint>,
    pub strips: Vec<Strip>,
}

fn rows(text: &str) -> impl Iterator<Item = Vec<&str>> {
    text.lines()
        .map(|l| l.trim_end_matches('\r'))
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| l.split('\t').collect())
}

fn hexu(s: &str) -> u32 {
    u32::from_str_radix(s.trim_start_matches("0x").trim_start_matches("0X"), 16)
        .unwrap_or_else(|_| panic!("bad hex in an embedded table: {s:?}"))
}

fn opt(s: &str) -> Option<String> {
    (s != "-").then(|| s.to_string())
}

fn unhex(s: &str) -> Vec<u8> {
    (0..s.len() / 2)
        .map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).expect("bad fingerprint hex"))
        .collect()
}

impl Pack {
    fn raw(kind: PackKind) -> (&'static [(&'static str, &'static [u8])], &'static str) {
        match kind {
            PackKind::Common => (embedded::COMMON, embedded::COMMON_SUMS),
            PackKind::Full => (embedded::FULL, embedded::FULL_SUMS),
        }
    }

    pub fn file(&self, name: &str) -> Option<&'static [u8]> {
        self.files.iter().find(|(n, _)| *n == name).map(|(_, b)| *b)
    }

    fn text(&self, name: &str) -> &'static str {
        std::str::from_utf8(
            self.file(name)
                .unwrap_or_else(|| panic!("{}/{name} not embedded", self.kind.name())),
        )
        .expect("embedded table is not UTF-8")
    }

    /// Release id: the first 12 hex digits of SHA256SUMS' SHA-256 (the scripts' `release data` line).
    pub fn release_id(&self) -> String {
        sha256(self.sums.as_bytes())[..12].to_string()
    }

    /// S0 + parse. The tables are the developer's, so a malformed row is a bug (panic), not a user error.
    pub fn load(kind: PackKind, log: &mut Log) -> Result<Pack, Stop> {
        let (files, sums) = Pack::raw(kind);
        let mut n = 0;
        for line in sums.lines().filter(|l| !l.trim().is_empty()) {
            let (hash, rel) = line.split_once("  ").unwrap_or((line, ""));
            let ok = files
                .iter()
                .any(|(f, b)| *f == rel && sha256(b) == hash.to_lowercase());
            if !ok {
                return Err(stop(
                    log,
                    2,
                    format!(
                        "release file corrupted: {}/{rel} (SHA-256 mismatch)",
                        kind.name()
                    ),
                    Some("RELEASE"),
                ));
            }
            n += 1;
        }
        let mut p = Pack {
            kind,
            files,
            sums,
            profiles: vec![],
            known: vec![],
            sites: vec![],
            fingerprints: vec![],
            strips: vec![],
        };
        log.pass(
            "S0",
            format!(
                "release data {} ({}): {n} files match SHA256SUMS",
                kind.name(),
                p.release_id()
            ),
        );
        let full = kind == PackKind::Full;
        let k = usize::from(full); // the Full tables have a variant / profile column more
        for r in rows(p.text("profiles.tsv")) {
            p.profiles.push(Profile {
                name: r[0].into(),
                variant: full.then(|| r[1].to_string()),
                file: r[1 + k].into(),
                size: r[2 + k].parse().expect("section_size"),
                sha: r[3 + k].to_lowercase(),
                va: hexu(r[4 + k]),
                new_entry: hexu(r[5 + k]),
                exp_entry: hexu(r[6 + k]),
                placement: if r[7 + k] == "static" {
                    Placement::Static
                } else {
                    Placement::Dynamic
                },
                mex_cave: r[8 + k] == "1",
                static_top: (r[9 + k] != "-").then(|| hexu(r[9 + k])),
                strip: if full { opt(r[11]) } else { None },
            });
        }
        for r in rows(p.text("known_dols.tsv")) {
            p.known.push(Known {
                in_sha: r[0].to_lowercase(),
                profile: r[1].into(),
                variant: full.then(|| r[2].to_string()),
                name: r[2 + k].into(),
                out_size: r[3 + k].parse().expect("out_dol_size"),
                out_sha: r[4 + k].to_lowercase(),
                game_id: r
                    .get(5 + k)
                    .filter(|g| !g.is_empty())
                    .map_or("GALE01".into(), |g| g.to_string()),
                local: false,
            });
        }
        // bases added on this machine: a release row wins; a profile / variant this pack lacks is ignored
        if let Some(text) = local::read(kind) {
            let mut n = 0;
            for r in rows(&text) {
                if r.len() < 5 + k {
                    continue;
                }
                let (in_sha, variant) = (r[0].to_lowercase(), full.then(|| r[2].to_string()));
                let dup = p
                    .known
                    .iter()
                    .any(|x| x.in_sha == in_sha && x.variant == variant);
                let has_profile = p
                    .profiles
                    .iter()
                    .any(|x| x.name == r[1] && x.variant == variant);
                if dup || !has_profile {
                    continue;
                }
                p.known.push(Known {
                    in_sha,
                    profile: r[1].into(),
                    variant,
                    name: r[2 + k].into(),
                    out_size: r[3 + k].parse().unwrap_or(0),
                    out_sha: r[4 + k].to_lowercase(),
                    game_id: "GALE01".into(),
                    local: true,
                });
                n += 1;
            }
            log.info(format!(
                "{}: {n} locally added base(s)",
                local::file_name(kind)
            ));
        }
        if full {
            for r in rows(p.text("sites.tsv")) {
                p.sites.push(Site {
                    profile: Some(r[0].into()),
                    va: hexu(r[1]),
                    word: hexu(r[2]),
                    kind: r[3].into(),
                    name: r[4].into(),
                    poke_word: (r[5] != "-").then(|| hexu(r[5])),
                });
            }
            for r in rows(p.text("strips.tsv")) {
                p.strips.push(Strip {
                    profile: r[0].into(),
                    va: hexu(r[1]),
                    len: r[2].parse().expect("strip length"),
                    orig_sha: r[3].to_lowercase(),
                    new_sha: r[4].to_lowercase(),
                    file: r[5].into(),
                });
            }
        } else {
            for r in rows(p.text("hooks.tsv")) {
                p.sites.push(Site {
                    profile: None,
                    va: hexu(r[0]),
                    word: hexu(r[1]),
                    kind: "stub".into(),
                    name: r[2].into(),
                    poke_word: None,
                });
            }
        }
        for r in rows(p.text("fingerprints.tsv")) {
            p.fingerprints.push(Fingerprint {
                profile: full.then(|| r[0].to_string()),
                name: r[k].into(),
                va: hexu(r[1 + k]),
                bytes: unhex(r[3 + k]),
            });
        }
        Ok(p)
    }

    pub fn profile(&self, name: &str, variant: Option<&str>) -> Option<&Profile> {
        self.profiles
            .iter()
            .find(|p| p.name == name && p.variant.as_deref() == variant)
    }

    pub fn known(&self, in_sha: &str, variant: Option<&str>) -> Option<&Known> {
        self.known
            .iter()
            .find(|k| k.in_sha == in_sha && k.variant.as_deref() == variant)
    }

    /// The words an input DOL of `profile` must hold (AI-only: every hooks.tsv row).
    pub fn sites_for<'a>(&'a self, profile: &'a str) -> impl Iterator<Item = &'a Site> {
        self.sites
            .iter()
            .filter(move |s| s.profile.as_deref().is_none_or(|p| p == profile))
    }

    pub fn fingerprints_for<'a>(
        &'a self,
        profile: &'a str,
    ) -> impl Iterator<Item = &'a Fingerprint> {
        self.fingerprints
            .iter()
            .filter(move |f| f.profile.as_deref().is_none_or(|p| p == profile))
    }

    /// A pack file checked against its table hash (S0 for the one section / strip blob a build uses).
    pub fn blob(
        &self,
        file: &str,
        size: usize,
        sha: &str,
        log: &mut Log,
    ) -> Result<&'static [u8], Stop> {
        match self.file(file) {
            Some(b) if b.len() == size && sha256(b) == sha => {
                log.pass(
                    "S0",
                    format!(
                        "{} {file}: {size} B, SHA-256 matches its table",
                        self.kind.name()
                    ),
                );
                Ok(b)
            }
            _ => Err(stop(
                log,
                2,
                format!(
                    "{}/{file}: size/SHA-256 do not match its table",
                    self.kind.name()
                ),
                Some("RELEASE"),
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_packs_load() {
        let mut log = Log::default();
        let c = Pack::load(PackKind::Common, &mut log).unwrap();
        let f = Pack::load(PackKind::Full, &mut log).unwrap();
        assert_eq!(c.profiles.len(), 3);
        assert_eq!(f.profiles.len(), 10);
        assert!(c.sites.iter().all(|s| s.profile.is_none()));
        assert!(f.profile("hybrid64", Some("full")).unwrap().strip.is_some());
        assert_eq!(f.strips.len(), 2);
        for p in c.profiles.iter().chain(&f.profiles) {
            let pk = if p.variant.is_some() { &f } else { &c };
            pk.blob(&p.file, p.size as usize, &p.sha, &mut log).unwrap();
        }
        assert_eq!(log.failed, 0);
    }
}
