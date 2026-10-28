//! S6: where the new DOL (and, if moved, the FST) goes in the ISO; plans P1-P3 (= Get-Plan in the
//! release scripts).

use crate::dol::align;
use crate::iso::{Extent, Iso};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PlanKind {
    /// The new DOL fits in place, before the FST.
    P1,
    /// The DOL fits in place once the FST moves to the first gap that takes it.
    P2,
    /// The DOL moves to the first gap that takes it (or past the end).
    P3,
}

#[derive(Clone, Copy, Debug)]
pub struct Plan {
    pub kind: PlanKind,
    pub dol: u64,
    pub fst: u64,
}

fn gaps(occ: &[Extent], limit: u64) -> Vec<Extent> {
    let mut sorted = occ.to_vec();
    sorted.sort_by_key(|e| (e.start, e.end));
    let mut g = Vec::new();
    let mut cur = 0;
    for e in &sorted {
        if e.start > cur {
            g.push(Extent {
                start: align(cur, 32),
                end: e.start,
            });
        }
        cur = cur.max(e.end);
    }
    g.push(Extent {
        start: align(cur, 32),
        end: limit,
    });
    g.retain(|e| e.end > e.start);
    g
}

fn next_occupied(x: u64, occ: &[Extent], iso_size: u64) -> u64 {
    occ.iter()
        .map(|e| e.start)
        .filter(|&s| s >= x)
        .fold(iso_size, u64::min)
}

pub fn plan(iso: &Iso, new_size: u64) -> Plan {
    let mut fixed = vec![
        Extent {
            start: 0,
            end: 0x2440,
        },
        Extent {
            start: 0x2440,
            end: iso.app_end,
        },
    ];
    fixed.extend_from_slice(&iso.files); // the old DOL counts as free
    let fst = Extent {
        start: iso.fst_off,
        end: iso.fst_off + iso.fst_size,
    };
    let mut with_fst = fixed.clone();
    with_fst.push(fst);
    if iso.dol_off + new_size <= next_occupied(iso.dol_off, &with_fst, iso.size) {
        return Plan {
            kind: PlanKind::P1,
            dol: iso.dol_off,
            fst: iso.fst_off,
        };
    }
    if iso.dol_off + new_size <= next_occupied(iso.dol_off, &fixed, iso.size) {
        let mut occ = fixed.clone();
        occ.push(Extent {
            start: iso.dol_off,
            end: iso.dol_off + new_size,
        });
        let need = align(iso.fst_size, 32);
        let to = gaps(&occ, iso.size)
            .iter()
            .find(|g| g.end - g.start >= need)
            .map_or_else(
                || align(occ.iter().map(|e| e.end).max().unwrap_or(0), 32),
                |g| g.start,
            );
        return Plan {
            kind: PlanKind::P2,
            dol: iso.dol_off,
            fst: to,
        };
    }
    let to = gaps(&with_fst, iso.size)
        .iter()
        .find(|g| g.end - g.start >= new_size)
        .map_or_else(
            || align(with_fst.iter().map(|e| e.end).max().unwrap_or(0), 0x8000),
            |g| g.start,
        );
    Plan {
        kind: PlanKind::P3,
        dol: to,
        fst: iso.fst_off,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gaps_are_aligned_and_sorted() {
        let occ = [
            Extent {
                start: 0x100,
                end: 0x205,
            },
            Extent {
                start: 0,
                end: 0x80,
            },
        ];
        let g = gaps(&occ, 0x1000);
        assert_eq!((g[0].start, g[0].end), (0x80, 0x100));
        assert_eq!((g[1].start, g[1].end), (0x220, 0x1000));
    }
}
