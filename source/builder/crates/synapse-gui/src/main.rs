//! Synapse GUI over `synapse-core`: pick an ISO, AI-only or Full (+ the Wii non-CRT pack), an output folder, then
//! Check or Build. The core runs on a worker thread; its log streams into the window.

// No console window on Windows release builds; debug builds keep it for logs.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, Sender, channel};

use eframe::egui::{self, Color32, RichText};
use eframe::egui_wgpu::{WgpuConfiguration, WgpuSetup, WgpuSetupCreateNew, wgpu};
use synapse_core::local;
use synapse_core::log::{Entry, Log, Stop, Tag};
use synapse_core::procedure::{self, Kind, Options};

fn main() -> eframe::Result {
    env_logger::init(); // rfd and wgpu errors reach stderr (RUST_LOG=rfd=debug)
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Synapse Builder")
            .with_inner_size([760.0, 640.0])
            .with_min_inner_size([560.0, 420.0])
            .with_drag_and_drop(true),
        wgpu_options: wgpu_options(),
        ..Default::default()
    };
    eframe::run_native(
        "Synapse Builder",
        options,
        Box::new(|_cc| Ok(Box::new(App::new()))),
    )
}

/// wgpu backends: on Windows DX12 first, OpenGL as fallback, never Vulkan (Intel's Vulkan driver
/// `igvk64.dll` 31.0.101.2135 crashes at start-up); elsewhere wgpu's default. `WGPU_BACKEND` still overrides.
fn wgpu_options() -> WgpuConfiguration {
    let mut setup = WgpuSetupCreateNew::without_display_handle();
    if cfg!(windows) {
        setup.instance_descriptor.backends =
            wgpu::Backends::from_env().unwrap_or(wgpu::Backends::DX12 | wgpu::Backends::GL);
    }
    WgpuConfiguration {
        wgpu_setup: WgpuSetup::CreateNew(setup),
        ..Default::default()
    }
}

// ---- settings (user config dir, key=value) ------------------------------------------------------------
const SETTINGS: &str = "gui_settings.txt";

fn load_settings() -> BTreeMap<String, String> {
    local::config_dir()
        .and_then(|d| std::fs::read_to_string(d.join(SETTINGS)).ok())
        .map(|t| {
            t.lines()
                .filter_map(|l| l.split_once('='))
                .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
                .collect()
        })
        .unwrap_or_default()
}

fn save_settings(s: &BTreeMap<String, String>) {
    if let Some(d) = local::config_dir() {
        let text: String = s.iter().map(|(k, v)| format!("{k}={v}\n")).collect();
        if std::fs::create_dir_all(&d)
            .and_then(|_| std::fs::write(d.join(SETTINGS), text))
            .is_err()
        {
            log::warn!("cannot save {}", d.join(SETTINGS).display());
        }
    }
}

// ---- worker --------------------------------------------------------------------------------------------
enum Job {
    Check,
    Build { force: bool },
    CheckBuilt(PathBuf),
}

enum Msg {
    Entry(Entry),
    Ask(String),
    Done {
        result: Result<String, Stop>,
        plain: Vec<&'static str>,
        report: Vec<String>,
    },
}

struct Running {
    rx: Receiver<Msg>,
    answer: Sender<bool>,
    question: Option<String>,
}

#[derive(Clone)]
enum Outcome {
    Ok(String),
    Err { code: u8, msg: String, quiet: bool },
}

struct App {
    iso: String,
    out_dir: String,
    full: bool,
    wii: bool,
    built_iso: String,
    settings: BTreeMap<String, String>,
    log: Vec<Entry>,
    plain: Vec<&'static str>,
    /// The REPORT block of an untested ISO (empty otherwise).
    report: Vec<String>,
    outcome: Option<Outcome>,
    note: Option<String>,
    running: Option<Running>,
    confirm_replace: Option<PathBuf>,
}

impl App {
    fn new() -> Self {
        App {
            iso: String::new(),
            out_dir: String::new(),
            full: false,
            wii: false,
            built_iso: String::new(),
            settings: load_settings(),
            log: Vec::new(),
            plain: Vec::new(),
            report: Vec::new(),
            outcome: None,
            note: None,
            running: None,
            confirm_replace: None,
        }
    }

    fn kind(&self) -> Kind {
        if self.full {
            Kind::Full {
                wii_non_crt: self.wii,
            }
        } else {
            Kind::AiOnly
        }
    }

    fn source(&self) -> Option<PathBuf> {
        let t = self.iso.trim().trim_matches('"');
        (!t.is_empty()).then(|| PathBuf::from(t))
    }

    /// The output ISO: the default name in the chosen folder (default: the source's folder).
    fn output(&self) -> Option<PathBuf> {
        let src = self.source()?;
        let name = procedure::default_output(&src, self.kind())
            .file_name()?
            .to_owned();
        let dir = self.out_dir.trim().trim_matches('"');
        Some(if dir.is_empty() {
            src.with_file_name(name)
        } else {
            Path::new(dir).join(name)
        })
    }

    fn set_iso(&mut self, p: &Path) {
        self.iso = p.display().to_string();
        if let Some(d) = p.parent() {
            self.settings
                .insert("last_iso_dir".into(), d.display().to_string());
            save_settings(&self.settings);
        }
        self.note = None;
    }

    fn start(&mut self, job: Job, ctx: &egui::Context) {
        let (tx, rx) = channel::<Msg>();
        let (answer_tx, answer_rx) = channel::<bool>();
        let (kind, source, out) = (self.kind(), self.source(), self.output());
        self.log.clear();
        self.plain.clear();
        self.report.clear();
        self.outcome = None;
        self.note = None;
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            let sink_tx = tx.clone();
            let sink_ctx = ctx.clone();
            let mut log = Log::with_sink(move |e| {
                let _ = sink_tx.send(Msg::Entry(e.clone()));
                sink_ctx.request_repaint();
            });
            let ask_tx = tx.clone();
            let ask_ctx = ctx.clone();
            let mut ask = move |q: &str| {
                let _ = ask_tx.send(Msg::Ask(q.to_string()));
                ask_ctx.request_repaint();
                answer_rx.recv().unwrap_or(false)
            };
            let result = match job {
                Job::Check | Job::Build { .. } => {
                    let o = Options {
                        source: source.unwrap_or_default(),
                        out: out.clone(),
                        kind,
                        profile: None,
                        allow_unknown: false,
                        check_only: matches!(job, Job::Check),
                        force: matches!(job, Job::Build { force: true }),
                    };
                    procedure::build(&o, &mut log, Some(&mut ask)).map(|r| match (&r.out, o.check_only) {
                        (Some(p), _) => format!("Done: {} ({} B)", p.display(), r.out_size),
                        (None, _) => format!(
                            "Eligible: profile {} {} ({} DOL), plan {:?}, content headroom {}. Nothing written.",
                            r.profile,
                            kind.variant().unwrap_or("AI-only"),
                            if r.unknown { "unknown" } else { "known" },
                            r.plan.kind,
                            r.headroom
                        ),
                    })
                }
                Job::CheckBuilt(p) => match procedure::check_built(&p, &mut log) {
                    Ok(Some(b)) if log.failed == 0 => {
                        log.explain("OK-CHECKBUILT");
                        Ok(format!(
                            "OK: still bootable as built ({} {})",
                            b.profile,
                            b.variant.as_deref().unwrap_or("AI-only")
                        ))
                    }
                    Ok(_) => Err(Stop {
                        code: 3,
                        msg: format!("{} check(s) failed", log.failed.max(1)),
                        quiet: false,
                    }),
                    Err(e) => Err(e),
                },
            };
            let code = result.as_ref().map_or_else(|e| e.code, |_| 0);
            let report = log
                .report
                .as_ref()
                .map(|r| r.lines(&log.failed_ids, code))
                .unwrap_or_default();
            let _ = tx.send(Msg::Done {
                result,
                plain: log.plain.clone(),
                report,
            });
            ctx.request_repaint();
        });
        self.running = Some(Running {
            rx,
            answer: answer_tx,
            question: None,
        });
    }

    fn poll(&mut self) {
        let Some(r) = self.running.as_mut() else {
            return;
        };
        while let Ok(m) = r.rx.try_recv() {
            match m {
                Msg::Entry(e) => self.log.push(e),
                Msg::Ask(q) => r.question = Some(q),
                Msg::Done {
                    result,
                    plain,
                    report,
                } => {
                    self.plain = plain;
                    self.report = report;
                    self.outcome = Some(match result {
                        Ok(s) => Outcome::Ok(s),
                        Err(e) => Outcome::Err {
                            code: e.code,
                            msg: e.msg,
                            quiet: e.quiet,
                        },
                    });
                    self.running = None;
                    return;
                }
            }
        }
    }

    fn browse_iso(&self, start: Option<&str>) -> Option<PathBuf> {
        let mut d = rfd::FileDialog::new().add_filter("GameCube ISO", &["iso", "gcm"]);
        if let Some(dir) = start.or(self.settings.get("last_iso_dir").map(String::as_str)) {
            d = d.set_directory(dir);
        }
        d.pick_file()
    }
}

const NO_PICK: &str = "No file chosen. If no dialog appeared, type or paste the path, or drop the ISO onto this window.";

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        self.poll();
        let busy = self.running.is_some();

        // drag-and-drop: the first dropped file becomes the source ISO
        let dropped: Vec<PathBuf> = ctx.input(|i| {
            i.raw
                .dropped_files
                .iter()
                .map(|f| f.path().to_path_buf())
                .collect()
        });
        if !busy && let Some(p) = dropped.first() {
            self.set_iso(p);
        }
        let hovering = ctx.input(|i| !i.raw.hovered_files.is_empty());

        egui::CentralPanel::default_margins().show(ui, |ui| {
            ui.heading(format!("Synapse Builder {}", synapse_core::VERSION));
            if hovering {
                ui.colored_label(Color32::LIGHT_BLUE, "Drop the ISO to use it as the source");
            }
            ui.add_space(6.0);
            ui.add_enabled_ui(!busy, |ui| {
                egui::Grid::new("form").num_columns(3).spacing([8.0, 8.0]).show(ui, |ui| {
                    ui.label("Source ISO");
                    ui.add(egui::TextEdit::singleline(&mut self.iso).hint_text("type, paste, browse or drop an ISO").desired_width(480.0));
                    if ui.button("Browse…").clicked() {
                        match self.browse_iso(None) {
                            Some(p) => self.set_iso(&p),
                            None => self.note = Some(NO_PICK.into()),
                        }
                    }
                    ui.end_row();

                    ui.label("Package");
                    ui.horizontal(|ui| {
                        ui.radio_value(&mut self.full, false, "AI-only");
                        ui.radio_value(&mut self.full, true, "Full (every feature; options in game)");
                    });
                    ui.label("");
                    ui.end_row();

                    ui.label("");
                    ui.add_enabled(
                        self.full,
                        egui::Checkbox::new(&mut self.wii, "Real Wii on an LCD / flat screen (Force 480p + Polling-Drift)"),
                    );
                    ui.label("");
                    ui.end_row();

                    ui.label("Output folder");
                    ui.add(egui::TextEdit::singleline(&mut self.out_dir).hint_text("default: the source ISO's folder").desired_width(480.0));
                    if ui.button("Browse…").clicked() {
                        let mut d = rfd::FileDialog::new();
                        if let Some(dir) = self.settings.get("last_out_dir") {
                            d = d.set_directory(dir);
                        }
                        match d.pick_folder() {
                            Some(p) => {
                                self.out_dir = p.display().to_string();
                                self.settings.insert("last_out_dir".into(), self.out_dir.clone());
                                save_settings(&self.settings);
                            }
                            None => self.note = Some("No folder chosen. If no dialog appeared, type or paste the folder.".into()),
                        }
                    }
                    ui.end_row();

                    ui.label("Output ISO");
                    match self.output() {
                        Some(p) => ui.monospace(p.display().to_string()),
                        None => ui.weak("(choose a source ISO)"),
                    };
                    ui.label("");
                    ui.end_row();
                });
                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    let ready = self.source().is_some();
                    if ui.add_enabled(ready, egui::Button::new("Check")).on_hover_text("run every check, write nothing").clicked() {
                        self.start(Job::Check, &ctx);
                    }
                    if ui.add_enabled(ready, egui::Button::new(RichText::new("Build").strong())).clicked() {
                        match self.output() {
                            Some(out) if out.exists() => self.confirm_replace = Some(out),
                            _ => self.start(Job::Build { force: false }, &ctx),
                        }
                    }
                    ui.separator();
                    ui.add(egui::TextEdit::singleline(&mut self.built_iso).hint_text("an ISO built by this release").desired_width(240.0));
                    if ui.button("Check built ISO…").clicked() {
                        let typed = self.built_iso.trim().trim_matches('"').to_string();
                        let p = if typed.is_empty() { self.browse_iso(None) } else { Some(PathBuf::from(typed)) };
                        match p {
                            Some(p) => {
                                self.built_iso = p.display().to_string();
                                self.start(Job::CheckBuilt(p), &ctx);
                            }
                            None => self.note = Some(NO_PICK.into()),
                        }
                    }
                });
            });
            if let Some(n) = &self.note {
                ui.colored_label(Color32::from_rgb(220, 160, 40), n);
            }

            // result + recap
            ui.add_space(4.0);
            if busy {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Working… (a build copies the whole ISO: 0.5–1.7 GB)");
                });
            }
            match &self.outcome {
                Some(Outcome::Ok(s)) => {
                    ui.colored_label(Color32::from_rgb(60, 170, 80), s);
                }
                Some(Outcome::Err { code, msg, quiet: false }) => {
                    ui.colored_label(Color32::from_rgb(220, 70, 60), format!("ERROR (exit {code}): {msg}"));
                }
                _ => {}
            }
            for t in &self.plain {
                ui.label(RichText::new(format!("» {t}")).strong());
            }
            if !self.report.is_empty() {
                let mut text = self.report.join("
");
                ui.add_space(4.0);
                if ui.button("Copy report").clicked() {
                    ctx.copy_text(text.clone());
                }
                ui.add(
                    egui::TextEdit::multiline(&mut text)
                        .font(egui::TextStyle::Monospace)
                        .desired_width(f32::INFINITY)
                        .desired_rows(self.report.len())
                        .interactive(false),
                );
            }

            // log
            ui.add_space(4.0);
            ui.separator();
            egui::ScrollArea::vertical().stick_to_bottom(true).auto_shrink([false, false]).show(ui, |ui| {
                for e in &self.log {
                    let color = match e.tag {
                        Tag::Pass => Color32::from_rgb(60, 170, 80),
                        Tag::Fail => Color32::from_rgb(220, 70, 60),
                        Tag::Info => Color32::GRAY,
                        Tag::Text => ui.visuals().text_color(),
                    };
                    ui.label(RichText::new(e.line()).monospace().color(color));
                }
            });
        });

        // modal: replace an existing output?
        if let Some(out) = self.confirm_replace.clone() {
            let mut answer = None;
            egui::Modal::new(egui::Id::unique("replace")).show(&ctx, |ui| {
                ui.label(format!("{} already exists. Replace it?", out.display()));
                ui.horizontal(|ui| {
                    if ui.button("Replace").clicked() {
                        answer = Some(true);
                    }
                    if ui.button("Cancel").clicked() {
                        answer = Some(false);
                    }
                });
            });
            if let Some(a) = answer {
                self.confirm_replace = None;
                if a {
                    self.start(Job::Build { force: true }, &ctx);
                }
            }
        }

        // modal: the core's yes / no question (an eligible but untested ISO)
        let question = self.running.as_ref().and_then(|r| r.question.clone());
        if let Some(q) = question {
            let mut answer = None;
            egui::Modal::new(egui::Id::unique("ask")).show(&ctx, |ui| {
                ui.label("This ISO is not in the list of tested ISOs, but it passed every compatibility check.");
                ui.label("The checks prove the AI can be installed safely, not that it works with this mod: boot-test the result.");
                ui.add_space(6.0);
                ui.label(RichText::new(&q).strong());
                ui.horizontal(|ui| {
                    if ui.button("Yes, build it").clicked() {
                        answer = Some(true);
                    }
                    if ui.button("No").clicked() {
                        answer = Some(false);
                    }
                });
            });
            if let (Some(a), Some(r)) = (answer, self.running.as_mut()) {
                r.question = None;
                let _ = r.answer.send(a);
            }
        }
    }
}
