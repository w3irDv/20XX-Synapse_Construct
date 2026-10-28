//! ISO model: header, FST file extents and the boot DOL, with the G1-G5 checks (BUILD_DETAILS.md 1).

use crate::dol::{Slot, be32, dol_size, hex, sha256, slots};
use crate::log::{Log, Stop, stop};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub const MAGIC_GC: u32 = 0xC233_9F3D;
/// Besides GALE01: accepted only for a known_dols.tsv row with that game id (hybrid.64 v3.2's vanilla build).
pub const ALT_GAME_IDS: [&str; 1] = ["GHME01"];

#[derive(Clone, Copy, Debug)]
pub struct Extent {
    pub start: u64,
    pub end: u64,
}

pub struct Iso {
    pub path: PathBuf,
    pub file: File,
    pub size: u64,
    pub head: Vec<u8>,
    pub game_id: String,
    pub dol_off: u64,
    pub fst_off: u64,
    pub fst_size: u64,
    pub fst_max: u64,
    pub app_end: u64,
    pub fst: Vec<u8>,
    pub files: Vec<Extent>,
    pub dol: Vec<u8>,
    pub slots: Vec<Slot>,
    pub dol_sha: String,
}

pub fn read_at(f: &mut File, off: u64, n: usize) -> std::io::Result<Vec<u8>> {
    let mut b = vec![0u8; n];
    f.seek(SeekFrom::Start(off))?;
    f.read_exact(&mut b)?;
    Ok(b)
}

impl Iso {
    /// G1-G5, then the FST and the DOL. Fails with exit 2 (unreadable) or 3 (not a usable image).
    pub fn open(path: &Path, who: &str, log: &mut Log) -> Result<Iso, Stop> {
        let mut file = File::open(path).map_err(|e| {
            stop(
                log,
                2,
                format!("cannot open {who} {}: {e}", path.display()),
                Some("READ"),
            )
        })?;
        let size = file.metadata().map(|m| m.len()).unwrap_or(0);
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        if !log.check("G1", size >= 0x2460, format!("{name} readable, {size} B")) {
            return Err(stop(log, 3, "image too small", None));
        }
        let rd = |f: &mut File, off: u64, n: usize, log: &mut Log| {
            read_at(f, off, n).map_err(|e| {
                stop(
                    log,
                    2,
                    format!(
                        "unexpected end of file reading {n} bytes at {}: {e}",
                        hex(off)
                    ),
                    Some("READ"),
                )
            })
        };
        let h = rd(&mut file, 0, 0x2460, log)?;
        if !log.check(
            "G2",
            be32(&h, 0x1C) == MAGIC_GC,
            format!("GameCube magic at 0x01C = {}", hex(be32(&h, 0x1C) as u64)),
        ) {
            return Err(stop(
                log,
                3,
                "not a plain GameCube image (NKit/RVZ/WBFS/CISO?): convert it to .iso with Dolphin first",
                None,
            ));
        }
        let game_id = String::from_utf8_lossy(&h[..6]).into_owned();
        let id_ok = (game_id == "GALE01" || ALT_GAME_IDS.contains(&game_id.as_str())) && h[7] == 2;
        let note = if game_id == "GALE01" {
            String::new()
        } else {
            format!("; {game_id} only for a listed ISO")
        };
        if !log.check(
            "G3",
            id_ok,
            format!(
                "game ID {game_id}, revision {} (need GALE01 rev 2{note})",
                h[7]
            ),
        ) {
            return Err(stop(log, 3, "not Melee NTSC 1.02", None));
        }
        let (dol_off, fst_off) = (be32(&h, 0x420) as u64, be32(&h, 0x424) as u64);
        let (fst_size, fst_max) = (be32(&h, 0x428) as u64, be32(&h, 0x42C) as u64);
        let app_end = 0x2460 + be32(&h, 0x2454) as u64 + be32(&h, 0x2458) as u64;
        let g4 = dol_off + 0x100 <= size
            && fst_off + fst_size <= size
            && app_end <= size
            && fst_size <= fst_max
            && fst_size >= 12;
        let msg = format!(
            "DOL {}, FST {} ({fst_size} B, max {fst_max} B), apploader end {} inside the image",
            hex(dol_off),
            hex(fst_off),
            hex(app_end)
        );
        if !log.check("G4", g4, msg) {
            return Err(stop(log, 3, "truncated or corrupt image", None));
        }
        let fst = rd(&mut file, fst_off, fst_size as usize, log)?;
        let n = be32(&fst, 8) as usize;
        let mut files = Vec::new();
        let mut over = 0;
        for i in 1..n {
            let o = 12 * i;
            if o + 12 > fst.len() {
                break;
            }
            if fst[o] == 0 {
                let (fo, fz) = (be32(&fst, o + 4) as u64, be32(&fst, o + 8) as u64);
                if fz > 0 {
                    files.push(Extent {
                        start: fo,
                        end: fo + fz,
                    });
                    if fo + fz > size {
                        over += 1;
                    }
                }
            }
        }
        let g5 = over == 0 && 12 * n <= fst.len();
        if !log.check(
            "G5",
            g5,
            format!(
                "{n} FST entries, {} files, all inside the image",
                files.len()
            ),
        ) {
            return Err(stop(log, 3, "truncated image (files past the end)", None));
        }
        let hdr = rd(&mut file, dol_off, 0x100, log)?;
        let ds = dol_size(&hdr);
        if ds <= 0x100 || dol_off + ds > size {
            return Err(stop(
                log,
                3,
                format!("DOL at {} runs past the end of the image", hex(dol_off)),
                Some("G4"),
            ));
        }
        let dol = rd(&mut file, dol_off, ds as usize, log)?;
        let slots = slots(&dol);
        let dol_sha = sha256(&dol);
        Ok(Iso {
            path: path.to_path_buf(),
            file,
            size,
            head: h,
            game_id,
            dol_off,
            fst_off,
            fst_size,
            fst_max,
            app_end,
            fst,
            files,
            dol,
            slots,
            dol_sha,
        })
    }

    /// Whether `name` is in the FST name table (NUL-separated names after the 12-byte entries).
    pub fn has_disc_file(&self, name: &str) -> bool {
        let st = 12 * be32(&self.fst, 8) as usize;
        if st > self.fst.len() {
            return false;
        }
        let mut needle = vec![0u8];
        needle.extend_from_slice(name.as_bytes());
        needle.push(0);
        let mut hay = vec![0u8];
        hay.extend_from_slice(&self.fst[st..]);
        hay.windows(needle.len()).any(|w| w == needle.as_slice())
    }
}
