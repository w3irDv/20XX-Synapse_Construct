//! The check log: every step reports `[PASS]` / `[FAIL]` / `[INFO]` lines with a check id, plus plain-language
//! explanations for players (the `== Recap` block). The core never prints; a front end attaches a sink.

use crate::messages;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tag {
    Pass,
    Fail,
    Info,
    Text,
}

#[derive(Clone, Debug)]
pub struct Entry {
    pub tag: Tag,
    pub id: String,
    pub msg: String,
}

impl Entry {
    /// The scripts' line format: `[PASS] B6 msg`, `[INFO] msg`; `Text` lines are printed as they are.
    pub fn line(&self) -> String {
        match self.tag {
            Tag::Text => self.msg.clone(),
            Tag::Info => format!("[INFO] {}", self.msg),
            Tag::Pass => format!("[PASS] {} {}", self.id, self.msg),
            Tag::Fail => format!("[FAIL] {} {}", self.id, self.msg),
        }
    }
}

type Sink = Box<dyn FnMut(&Entry) + Send>;

/// The block a user copies when reporting an untested ISO (the scripts' REPORT block).
#[derive(Clone, Debug, Default)]
pub struct Report {
    pub release: String,
    pub iso: String,
    pub size: u64,
    pub dol_sha: String,
    pub profile: String,
    pub checks: String,
    pub plan: String,
    pub output: Option<String>,
}

impl Report {
    /// The block's lines, as the CLI prints them and the GUI shows them; `code` = the run's exit code.
    pub fn lines(&self, failed_ids: &[String], code: u8) -> Vec<String> {
        let mut v = vec![
            "== REPORT (untested ISO: copy this block when you report how it went)".to_string(),
            format!("  release data : {}", self.release),
            format!("  iso          : {} ({} B)", self.iso, self.size),
            format!(
                "  game code    : SHA-256 {} (not in known_dols.tsv)",
                self.dol_sha
            ),
            format!("  profile      : {}", self.profile),
        ];
        if failed_ids.is_empty() {
            v.push(format!("  checks       : {}", self.checks));
        } else {
            v.push(format!(
                "  checks       : failed: {}",
                failed_ids.join(", ")
            ));
        }
        v.push(format!("  plan         : {}", self.plan));
        v.push(format!("  exit code    : {code}"));
        if code == 0 && self.output.is_some() {
            v.push("  boot test    : <fill in: boots? CPU at type 4 attacks and wavedashes? Z+D-Up menu opens? the mod's own features still work?>".to_string());
        }
        v.push("  Please open an issue titled \"Tested ISO: mod_name\" and paste this block. Thank you!".to_string());
        v.push("  https://github.com/w3irDv/20XX-Synapse_Construct/issues/new".to_string());
        v
    }
}

#[derive(Default)]
pub struct Log {
    pub entries: Vec<Entry>,
    pub failed: usize,
    pub failed_ids: Vec<String>,
    /// Set for an unknown DOL (S2); `None` for a known one or a declined build.
    pub report: Option<Report>,
    /// Plain-language explanations, in order, without repeats (printed once at the end as the recap).
    pub plain: Vec<&'static str>,
    sink: Option<Sink>,
}

impl Log {
    pub fn with_sink(sink: impl FnMut(&Entry) + Send + 'static) -> Self {
        Log {
            sink: Some(Box::new(sink)),
            ..Default::default()
        }
    }

    fn push(&mut self, tag: Tag, id: &str, msg: String) {
        let e = Entry {
            tag,
            id: id.to_string(),
            msg,
        };
        if let Some(s) = self.sink.as_mut() {
            s(&e);
        }
        self.entries.push(e);
    }

    pub fn explain(&mut self, key: &str) {
        if let Some(t) = messages::player(key)
            && !self.plain.contains(&t)
        {
            self.plain.push(t);
        }
    }

    pub fn pass(&mut self, id: &str, msg: impl Into<String>) {
        self.push(Tag::Pass, id, msg.into());
    }

    pub fn info(&mut self, msg: impl Into<String>) {
        self.push(Tag::Info, "", msg.into());
    }

    pub fn text(&mut self, msg: impl Into<String>) {
        self.push(Tag::Text, "", msg.into());
    }

    /// A failed check; `key` = the plain-language message (default: the check id's own).
    pub fn bad(&mut self, id: &str, msg: impl Into<String>, key: Option<&str>) {
        self.failed += 1;
        self.push(Tag::Fail, id, msg.into());
        self.explain(key.unwrap_or(id));
        if !self.failed_ids.iter().any(|x| x == id) {
            self.failed_ids.push(id.to_string());
        }
    }

    pub fn check(&mut self, id: &str, ok: bool, msg: impl Into<String>) -> bool {
        if ok {
            self.pass(id, msg);
        } else {
            self.bad(id, msg, None);
        }
        ok
    }
}

/// A step that stops the run: exit code (the scripts' 1-6) + message.
#[derive(Debug, Clone)]
pub struct Stop {
    pub code: u8,
    pub msg: String,
    /// The user's own choice (no ERROR line), e.g. a declined prompt.
    pub quiet: bool,
}

impl std::fmt::Display for Stop {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.msg)
    }
}

impl std::error::Error for Stop {}

pub fn stop(log: &mut Log, code: u8, msg: impl Into<String>, key: Option<&str>) -> Stop {
    if let Some(k) = key {
        log.explain(k);
    }
    Stop {
        code,
        msg: msg.into(),
        quiet: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_lines() {
        let r = Report {
            release: "abc".into(),
            plan: "P2".into(),
            checks: "all passed".into(),
            output: Some("out.iso".into()),
            ..Default::default()
        };
        let ok = r.lines(&[], 0);
        assert!(ok[0].starts_with("== REPORT"));
        assert!(ok.iter().any(|l| l == "  checks       : all passed"));
        assert!(ok.iter().any(|l| l.starts_with("  boot test")));
        let bad = r.lines(&["B6".into(), "B9".into()], 3);
        assert!(bad.iter().any(|l| l == "  checks       : failed: B6, B9"));
        assert!(bad.iter().any(|l| l == "  exit code    : 3"));
        assert!(!bad.iter().any(|l| l.starts_with("  boot test")));
    }
}
