//! Synapse builder core: ISO / DOL reading, base detection, checks, variant choice,
//! in-place patch and verification over the two embedded packs. See
//! the release scripts' procedure (S0-S9), plus the Full packages; the rules for users: BUILD_DETAILS.md.

pub mod dol;
pub mod iso;
pub mod local;
pub mod log;
pub mod messages;
pub mod pack;
pub mod plan;
pub mod procedure;

/// Builder version, shown by the CLI and the GUI.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
