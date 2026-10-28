//! Bases the user added on this machine with `add-known-base` (eligible, boot-tested by the user; not part of the
//! release). One file per pack in the user config dir, in its pack's known_dols.tsv format.

use crate::pack::PackKind;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

/// `SYNAPSE_CONFIG_DIR`, else the OS config dir + `Synapse` (`synapse` on Linux).
pub fn config_dir() -> Option<PathBuf> {
    if let Some(d) = std::env::var_os("SYNAPSE_CONFIG_DIR") {
        return Some(PathBuf::from(d));
    }
    let home = || std::env::var_os("HOME").map(PathBuf::from);
    if cfg!(windows) {
        std::env::var_os("APPDATA").map(|d| PathBuf::from(d).join("Synapse"))
    } else if cfg!(target_os = "macos") {
        home().map(|h| h.join("Library/Application Support/Synapse"))
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| home().map(|h| h.join(".config")))
            .map(|d| d.join("synapse"))
    }
}

pub fn file_name(kind: PackKind) -> &'static str {
    match kind {
        PackKind::Common => "known_dols.local.tsv",
        PackKind::Full => "known_dols.full.local.tsv",
    }
}

pub fn path(kind: PackKind) -> Option<PathBuf> {
    config_dir().map(|d| d.join(file_name(kind)))
}

/// The file's text, or `None` when there is none (or it can't be read).
pub fn read(kind: PackKind) -> Option<String> {
    path(kind).and_then(|p| fs::read_to_string(p).ok())
}

/// Appends one row (columns already in the pack's order), creating the dir and the header if needed. LF endings.
pub fn append(kind: PackKind, cols: &[&str]) -> std::io::Result<PathBuf> {
    let p = path(kind)
        .ok_or_else(|| std::io::Error::other("no user config dir (set SYNAPSE_CONFIG_DIR)"))?;
    if let Some(d) = p.parent() {
        fs::create_dir_all(d)?;
    }
    let mut text = fs::read_to_string(&p).unwrap_or_default();
    if text.is_empty() {
        let head = match kind {
            PackKind::Common => {
                "# in_dol_sha256\tprofile\tbase_name\tout_dol_size\tout_dol_sha256\n"
            }
            PackKind::Full => {
                "# in_dol_sha256\tprofile\tvariant\tbase_name\tout_dol_size\tout_dol_sha256\n"
            }
        };
        text.push_str(head);
        text.push_str("# Boot DOLs added on this machine with add-known-base (eligible, boot-tested by the user; not part of the release).\n");
    } else if !text.ends_with('\n') {
        text.push('\n');
    }
    let clean: Vec<String> = cols
        .iter()
        .map(|c| c.replace(['\t', '\r', '\n'], " ").trim().to_string())
        .collect();
    text.push_str(&clean.join("\t"));
    text.push('\n');
    let mut f = fs::File::create(&p)?;
    f.write_all(text.as_bytes())?;
    Ok(p)
}
