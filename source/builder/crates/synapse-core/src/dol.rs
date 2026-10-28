//! DOL model: the 18 section triples (7 text, 11 data), windows by virtual address, S4.

use sha2::{Digest, Sha256};

pub fn be32(b: &[u8], o: usize) -> u32 {
    u32::from_be_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
}

pub fn set_be32(b: &mut [u8], o: usize, v: u32) {
    b[o..o + 4].copy_from_slice(&v.to_be_bytes());
}

pub fn align(x: u64, a: u64) -> u64 {
    (x + a - 1) & !(a - 1)
}

pub fn sha256(b: &[u8]) -> String {
    format!("{:x}", Sha256::digest(b))
}

pub fn hex(v: u64) -> String {
    format!("0x{v:08X}")
}

/// A loaded section: slot 0-6 = text, 7-17 = data.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Slot {
    pub slot: usize,
    pub off: u32,
    pub va: u32,
    pub size: u32,
}

impl Slot {
    pub fn end(&self) -> u64 {
        self.va as u64 + self.size as u64
    }
    pub fn is_text(&self) -> bool {
        self.slot <= 6
    }
}

pub fn slots(d: &[u8]) -> Vec<Slot> {
    (0..18)
        .filter_map(|i| {
            let size = be32(d, 0x90 + 4 * i);
            (size != 0).then(|| Slot {
                slot: i,
                off: be32(d, 4 * i),
                va: be32(d, 0x48 + 4 * i),
                size,
            })
        })
        .collect()
}

/// DOL size = max(offset + size) of the loaded sections (S2).
pub fn dol_size(hdr: &[u8]) -> u64 {
    (0..18)
        .filter(|&i| be32(hdr, 0x90 + 4 * i) != 0)
        .map(|i| be32(hdr, 4 * i) as u64 + be32(hdr, 0x90 + 4 * i) as u64)
        .max()
        .unwrap_or(0)
}

/// Bytes at [va, va + n) when one loaded section maps all of them.
pub fn window<'a>(d: &'a [u8], slots: &[Slot], va: u32, n: usize) -> Option<&'a [u8]> {
    let (va, n64) = (va as u64, n as u64);
    slots
        .iter()
        .find(|s| s.va as u64 <= va && va + n64 <= s.end())
        .and_then(|s| {
            let o = s.off as usize + (va - s.va as u64) as usize;
            d.get(o..o + n)
        })
}

pub fn word(d: &[u8], slots: &[Slot], va: u32) -> Option<u32> {
    window(d, slots, va, 4).map(|w| be32(w, 0))
}

/// File offset of [va, va + n) when one loaded section maps it (for in-place writes such as the hybrid strip).
pub fn file_offset(slots: &[Slot], va: u32, n: usize) -> Option<usize> {
    let (va, n64) = (va as u64, n as u64);
    slots
        .iter()
        .find(|s| s.va as u64 <= va && va + n64 <= s.end())
        .map(|s| s.off as usize + (va - s.va as u64) as usize)
}

/// S4: old DOL + pad to 32 + section + pad to 32; the free text slot's triple and the entry point.
pub fn new_dol(old: &[u8], sec: &[u8], slot: usize, va: u32, entry: u32) -> Vec<u8> {
    let sec_off = align(old.len() as u64, 32) as usize;
    let mut n = vec![0u8; align((sec_off + sec.len()) as u64, 32) as usize];
    n[..old.len()].copy_from_slice(old);
    n[sec_off..sec_off + sec.len()].copy_from_slice(sec);
    set_be32(&mut n, 4 * slot, sec_off as u32);
    set_be32(&mut n, 0x48 + 4 * slot, va);
    set_be32(&mut n, 0x90 + 4 * slot, sec.len() as u32);
    set_be32(&mut n, 0xE0, entry);
    n
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiny_dol() -> Vec<u8> {
        let mut d = vec![0u8; 0x140];
        set_be32(&mut d, 0, 0x100); // text0 at file 0x100
        set_be32(&mut d, 0x48, 0x8000_3100);
        set_be32(&mut d, 0x90, 0x40);
        set_be32(&mut d, 0xE0, 0x8000_3100);
        d[0x104..0x108].copy_from_slice(&[1, 2, 3, 4]);
        d
    }

    #[test]
    fn model() {
        let d = tiny_dol();
        assert_eq!(dol_size(&d), 0x140);
        let s = slots(&d);
        assert_eq!(s.len(), 1);
        assert_eq!(word(&d, &s, 0x8000_3104), Some(0x0102_0304));
        assert_eq!(window(&d, &s, 0x8000_313E, 4), None);
    }

    #[test]
    fn s4_appends_and_pads() {
        let d = tiny_dol();
        let n = new_dol(&d, &[0xAA; 5], 1, 0x8048_4800, 0x8048_4800);
        assert_eq!(n.len(), 0x160);
        assert_eq!(be32(&n, 4), 0x140);
        assert_eq!(be32(&n, 0x4C), 0x8048_4800);
        assert_eq!(be32(&n, 0x94), 5);
        assert_eq!(be32(&n, 0xE0), 0x8048_4800);
        assert_eq!(&n[0x140..0x145], &[0xAA; 5]);
        assert!(n[0x145..].iter().all(|&b| b == 0));
    }
}
