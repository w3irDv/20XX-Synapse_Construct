//! `synapse-cli`: the console front end of the Synapse builder (one console and one GUI executable over one core).
//! Exit codes are the release scripts' (BUILD_DETAILS.md 6).

use std::io::{BufRead, IsTerminal, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use synapse_core::local;
use synapse_core::log::{Log, Report, Stop};
use synapse_core::procedure::{self, Kind, Options};

const USAGE: &str = "usage: synapse-cli build <source.iso> [--full [--wii-non-crt]] [--out <iso>] [--profile <p>]
                        [--allow-unknown-base] [--check-only] [--force]
       synapse-cli check-built <iso>
       synapse-cli add-known-base <original.iso> --built <built.iso> [--profile <p>]
       synapse-cli --version

build:
  --full                the Full package (every feature baked; options in game); default: AI-only
  --wii-non-crt         with --full: + Force 480p and Polling-Drift (a real Wii on an LCD / flat screen)
  --out <iso>           output ISO (default: <source>.aionly.iso / .full.iso / .full.wii-non-crt.iso)
  --profile <p>         force the profile of an unknown DOL (AI-only: vanilla | hybrid64 | mex; Full: vanilla | mex)
  --allow-unknown-base  build an untested but eligible ISO without asking (boot-test the result)
  --check-only          run every check, write nothing
  --force               replace an existing output
check-built:            check that an ISO built by this release still boots as built (read-only)
add-known-base:         after a boot test, treat an untested original ISO as known on this machine (asks you to
                        confirm the boot test; the list lives in the user config dir, see below)

Exit codes: 0 ok | 1 usage | 2 release data / unreadable input | 3 ineligible base or check-built failure
            4 unknown DOL without --allow-unknown-base | 5 disk space | 6 write or read-back failure";

enum Command {
    Build(Options),
    CheckBuilt(PathBuf),
    AddKnownBase {
        original: PathBuf,
        built: PathBuf,
        profile: Option<String>,
    },
}

fn parse(args: &[String]) -> Result<Command, String> {
    let mut it = args.iter();
    let cmd = it.next().map(String::as_str).unwrap_or("");
    if !["build", "check-built", "add-known-base"].contains(&cmd) {
        return Err(format!(
            "unknown command '{cmd}' (build | check-built | add-known-base)"
        ));
    }
    let mut o = Options {
        source: PathBuf::new(),
        out: None,
        kind: Kind::AiOnly,
        profile: None,
        allow_unknown: false,
        check_only: false,
        force: false,
    };
    let (mut full, mut wii, mut src, mut built) = (false, false, None, None);
    let mut used: Vec<&str> = Vec::new();
    while let Some(a) = it.next() {
        let mut value = |name: &str| it.next().cloned().ok_or(format!("{name} needs a value"));
        match a.as_str() {
            "--full" => full = true,
            "--wii-non-crt" => wii = true,
            "--out" => o.out = Some(PathBuf::from(value("--out")?)),
            "--profile" => o.profile = Some(value("--profile")?),
            "--allow-unknown-base" => o.allow_unknown = true,
            "--check-only" => o.check_only = true,
            "--force" => o.force = true,
            "--built" => built = Some(PathBuf::from(value("--built")?)),
            s if s.starts_with("--") => return Err(format!("unknown option {s}")),
            s if src.is_none() => {
                src = Some(PathBuf::from(s));
                continue;
            }
            s => return Err(format!("unexpected argument {s}")),
        }
        used.push(a.as_str());
    }
    let src = src.ok_or("missing the ISO argument")?;
    let only = |allowed: &[&str]| match used.iter().find(|u| !allowed.contains(u)) {
        Some(u) => Err(format!("{u} does not go with {cmd}")),
        None => Ok(()),
    };
    match cmd {
        "check-built" => {
            only(&[])?;
            Ok(Command::CheckBuilt(src))
        }
        "add-known-base" => {
            only(&["--built", "--profile"])?;
            let built = built.ok_or("add-known-base <original iso> needs --built <the iso built from it and boot-tested>")?;
            if let Some(p) = &o.profile
                && !["vanilla", "hybrid64", "mex"].contains(&p.as_str())
            {
                return Err(format!("bad --profile '{p}' (vanilla|hybrid64|mex)"));
            }
            Ok(Command::AddKnownBase {
                original: src,
                built,
                profile: o.profile,
            })
        }
        _ => {
            only(&[
                "--full",
                "--wii-non-crt",
                "--out",
                "--profile",
                "--allow-unknown-base",
                "--check-only",
                "--force",
            ])?;
            o.source = src;
            if wii && !full {
                return Err("--wii-non-crt goes with --full".into());
            }
            if full {
                o.kind = Kind::Full { wii_non_crt: wii };
            }
            let allowed: &[&str] = if full {
                &["vanilla", "mex"]
            } else {
                &["vanilla", "hybrid64", "mex"]
            };
            if let Some(p) = &o.profile
                && !allowed.contains(&p.as_str())
            {
                return Err(format!("bad --profile '{p}' ({})", allowed.join("|")));
            }
            if o.check_only && (o.out.is_some() || o.force) {
                return Err("--check-only writes nothing: drop --out / --force".into());
            }
            Ok(Command::Build(o))
        }
    }
}

fn show_report(r: &Report, failed_ids: &[String], code: u8) {
    println!();
    for l in r.lines(failed_ids, code) {
        println!("{l}");
    }
}

/// A y/N question on the console; only when a person can answer (stdin is a terminal).
fn ask_console(question: &str) -> bool {
    print!("{question} [y/N] ");
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    let _ = std::io::stdin().lock().read_line(&mut line);
    matches!(line.trim().to_ascii_lowercase().as_str(), "y" | "yes")
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|a| a == "--version" || a == "-V") {
        println!("synapse-cli {}", synapse_core::VERSION);
        return ExitCode::SUCCESS;
    }
    if args.is_empty() || args.iter().any(|a| a == "--help" || a == "-h") {
        println!("{USAGE}");
        if let Some(d) = local::config_dir() {
            println!("\nLocally added bases: {}", d.display());
        }
        return ExitCode::from(if args.is_empty() { 1 } else { 0 });
    }
    let cmd = match parse(&args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ERROR: {e}\n\n{USAGE}");
            return ExitCode::from(1);
        }
    };
    println!("synapse-cli {}", synapse_core::VERSION);
    let mut log = Log::with_sink(|e| println!("{}", e.line()));
    let mut asker = ask_console;
    let ask: procedure::Ask = if std::io::stdin().is_terminal() {
        Some(&mut asker)
    } else {
        None
    };
    let result: Result<(), Stop> = match &cmd {
        Command::Build(o) => procedure::build(o, &mut log, ask).map(|out| {
            if o.check_only {
                println!();
                println!(
                    "== check only: ELIGIBLE  profile {} {} ({} DOL), plan {:?}, content headroom {}",
                    out.profile,
                    o.kind.variant().unwrap_or("AI-only"),
                    if out.unknown { "unknown" } else { "known" },
                    out.plan.kind,
                    out.headroom
                );
                println!("nothing written.");
            }
        }),
        Command::CheckBuilt(p) => match procedure::check_built(p, &mut log) {
            Ok(Some(_)) if log.failed == 0 => {
                println!("== check-built: OK (still bootable as built)");
                log.explain("OK-CHECKBUILT");
                Ok(())
            }
            Ok(_) => Err(Stop { code: 3, msg: format!("{} check(s) failed", log.failed.max(1)), quiet: false }),
            Err(e) => Err(e),
        },
        Command::AddKnownBase { original, built, profile } => {
            procedure::add_known_base(original, built, profile.as_deref(), &mut log, ask).map(|_| ())
        }
    };
    let code = match result {
        Ok(()) => 0,
        Err(e) => {
            if !e.quiet {
                println!("ERROR: {}", e.msg);
            }
            e.code
        }
    };
    if let Some(r) = &log.report {
        show_report(r, &log.failed_ids, code);
    }
    if !log.plain.is_empty() {
        println!();
        println!("== Recap");
        for t in &log.plain {
            println!(">> {t}");
        }
    }
    ExitCode::from(code)
}
