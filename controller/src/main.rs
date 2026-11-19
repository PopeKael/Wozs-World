#![cfg_attr(not(target_os = "windows"), allow(dead_code))]
#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

use std::{
    fs,
    io::{self, Write},
    net::{SocketAddr, TcpStream},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

use eframe::egui::{self, Color32, RichText, Vec2, ViewportBuilder, ViewportCommand, WindowLevel};
use serde::{Deserialize, Serialize};

#[cfg(not(target_os = "windows"))]
compile_error!("Woz's World Dock is a Windows desktop application.");

const DEFAULT_PORT: u16 = 9000;
const STATUS_REFRESH: Duration = Duration::from_secs(2);
const CONNECT_TIMEOUT: Duration = Duration::from_millis(250);
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct ManagedProcess {
    process_id: u32,
    dotnet_path: PathBuf,
    #[serde(default = "default_port")]
    http_port: u16,
    ready_utc: Option<String>,
}

fn default_port() -> u16 {
    DEFAULT_PORT
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
struct Settings {
    always_on_top: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            always_on_top: true,
        }
    }
}

#[derive(Clone, Debug)]
enum WorldStatus {
    Running { process_id: u32 },
    Starting { process_id: u32 },
    Unresponsive { process_id: u32 },
    Stopped,
    UnmanagedListener,
    Attention(String),
}

impl WorldStatus {
    fn is_running(&self) -> bool {
        matches!(self, Self::Running { .. })
    }

    fn can_start(&self) -> bool {
        matches!(self, Self::Stopped)
    }

    fn can_stop(&self) -> bool {
        matches!(
            self,
            Self::Running { .. } | Self::Starting { .. } | Self::Unresponsive { .. }
        )
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Running { .. } => "RUNNING",
            Self::Starting { .. } => "PROCESS ACTIVE",
            Self::Unresponsive { .. } => "NOT RESPONDING",
            Self::Stopped => "STOPPED",
            Self::UnmanagedListener => "PORT IN USE",
            Self::Attention(_) => "CHECK DETAILS",
        }
    }

    fn color(&self) -> Color32 {
        match self {
            Self::Running { .. } => Color32::from_rgb(86, 207, 133),
            Self::Starting { .. } => Color32::from_rgb(244, 191, 82),
            Self::Stopped => Color32::from_rgb(145, 155, 169),
            Self::UnmanagedListener | Self::Unresponsive { .. } | Self::Attention(_) => {
                Color32::from_rgb(243, 119, 103)
            }
        }
    }

    fn detail(&self) -> String {
        match self {
            Self::Running { process_id } => {
                format!("Local region ready · PID {process_id}")
            }
            Self::Starting { process_id } => {
                format!(
                    "Simulator process is alive, but startup and login readiness are not verified · PID {process_id}"
                )
            }
            Self::Unresponsive { process_id } => format!(
                "The simulator was ready, but its configured local port is no longer responding · PID {process_id}; graceful stop is available."
            ),
            Self::Stopped => "The local simulator is stopped.".to_owned(),
            Self::UnmanagedListener => format!(
                "The configured local port is open, but it is not owned by this project's recorded process."
            ),
            Self::Attention(message) => message.clone(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Operation {
    Start,
    Stop,
}

impl Operation {
    fn label(self) -> &'static str {
        match self {
            Self::Start => "Starting Woz's World…",
            Self::Stop => "Requesting graceful shutdown…",
        }
    }

    fn script_name(self) -> &'static str {
        match self {
            Self::Start => "Start-World.ps1",
            Self::Stop => "Stop-World.ps1",
        }
    }

    fn file_tag(self) -> &'static str {
        match self {
            Self::Start => "start",
            Self::Stop => "stop",
        }
    }
}

struct OperationResult {
    operation_id: u64,
    operation: Operation,
    exit_code: Option<i32>,
    output: String,
    error: Option<String>,
}

#[derive(Serialize)]
struct CreateAccountRequest {
    first_name: String,
    last_name: String,
    password: String,
    email: String,
}

struct AccountResult {
    request_id: u64,
    exit_code: Option<i32>,
    output: String,
    error: Option<String>,
}

struct WorldDock {
    project_root: PathBuf,
    settings: Settings,
    status: WorldStatus,
    last_status_check: Instant,
    active_operation: Option<Operation>,
    current_operation_id: u64,
    operation_receiver: Receiver<OperationResult>,
    operation_sender: Sender<OperationResult>,
    account_receiver: Receiver<AccountResult>,
    account_sender: Sender<AccountResult>,
    account_request_id: u64,
    account_in_progress: bool,
    show_create_account: bool,
    account_first_name: String,
    account_last_name: String,
    account_email: String,
    account_password: String,
    account_password_confirm: String,
    account_message: String,
    last_operation: String,
    last_output: String,
    show_details: bool,
}

impl WorldDock {
    fn new(project_root: PathBuf, settings: Settings) -> Self {
        let (operation_sender, operation_receiver) = mpsc::channel();
        let (account_sender, account_receiver) = mpsc::channel();
        let status = inspect_world(&project_root);

        Self {
            project_root,
            settings,
            status,
            last_status_check: Instant::now(),
            active_operation: None,
            current_operation_id: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            operation_receiver,
            operation_sender,
            account_receiver,
            account_sender,
            account_request_id: 0,
            account_in_progress: false,
            show_create_account: false,
            account_first_name: String::new(),
            account_last_name: String::new(),
            account_email: String::new(),
            account_password: String::new(),
            account_password_confirm: String::new(),
            account_message: String::new(),
            last_operation: "Controller ready.".to_owned(),
            last_output: String::new(),
            show_details: false,
        }
    }

    fn begin_operation(&mut self, operation: Operation) {
        self.current_operation_id = self.current_operation_id.wrapping_add(1);
        let operation_id = self.current_operation_id;
        let project_root = self.project_root.clone();
        let sender = self.operation_sender.clone();
        self.active_operation = Some(operation);
        self.last_operation = operation.label().to_owned();

        thread::spawn(move || {
            let script = project_root
                .join("scripts")
                .join(operation.script_name());
            let output_dir = project_root.join(".local").join("world-dock-commands");
            let run_tag = format!("{operation_id:016}-{}", operation.file_tag());
            let stdout_path = output_dir.join(format!("{run_tag}.stdout.log"));
            let stderr_path = output_dir.join(format!("{run_tag}.stderr.log"));

            let result = (|| -> io::Result<OperationResult> {
                fs::create_dir_all(&output_dir)?;
                let stdout_file = fs::File::create(&stdout_path)?;
                let stderr_file = fs::File::create(&stderr_path)?;
                // File redirection avoids waiting on pipe EOF if a detached child inherits a handle.
                let status = Command::new("powershell.exe")
                    .arg("-NoProfile")
                    .arg("-NonInteractive")
                    .arg("-ExecutionPolicy")
                    .arg("Bypass")
                    .arg("-File")
                    .arg(&script)
                    .current_dir(&project_root)
                    .creation_flags(CREATE_NO_WINDOW)
                    .stdin(Stdio::null())
                    .stdout(Stdio::from(stdout_file))
                    .stderr(Stdio::from(stderr_file))
                    .status()?;

                let mut output = read_text_file(&stdout_path);
                let stderr = read_text_file(&stderr_path);
                if !stderr.is_empty() {
                    if !output.is_empty() {
                        output.push('\n');
                    }
                    output.push_str(&stderr);
                }

                Ok(OperationResult {
                    operation_id,
                    operation,
                    exit_code: status.code(),
                    output,
                    error: None,
                })
            })();

            let operation_result = result.unwrap_or_else(|error| OperationResult {
                operation_id,
                operation,
                exit_code: None,
                output: String::new(),
                error: Some(format!("Could not run {}: {error}", script.display())),
            });

            let _ = sender.send(operation_result);
        });
    }

    fn receive_operation_results(&mut self) {
        while let Ok(result) = self.operation_receiver.try_recv() {
            if result.operation_id != self.current_operation_id {
                continue;
            }
            self.active_operation = None;
            self.last_output = result.output;
            self.last_operation = match (&result.error, result.exit_code) {
                (Some(error), _) => error.clone(),
                (None, Some(0)) => match result.operation {
                    Operation::Start if self.last_output.contains("is ready") => {
                        "World is ready; region and REST checks passed.".to_owned()
                    }
                    Operation::Start => "Start command completed.".to_owned(),
                    Operation::Stop if self.last_output.contains("No simulator process was running") => {
                        "World was already stopped; cleared its stale PID record.".to_owned()
                    }
                    Operation::Stop if self.last_output.contains("exited before the REST console accepted") => {
                        "Simulator exited before a graceful request; process record cleared.".to_owned()
                    }
                    Operation::Stop => "Graceful shutdown completed.".to_owned(),
                },
                (None, code) => format!(
                    "{} failed with exit code {}.",
                    result.operation.script_name(),
                    code.map_or_else(|| "unknown".to_owned(), |value| value.to_string())
                ),
            };
            self.last_status_check = Instant::now()
                .checked_sub(STATUS_REFRESH)
                .unwrap_or_else(Instant::now);
        }

        while let Ok(result) = self.account_receiver.try_recv() {
            if result.request_id != self.account_request_id {
                continue;
            }
            self.account_in_progress = false;
            if let Some(error) = result.error {
                self.account_message = error;
            } else if result.exit_code == Some(0) && result.output.trim() == "ACCOUNT_CREATED" {
                self.account_password.clear();
                self.account_password_confirm.clear();
                self.account_message = format!(
                    "Account created. Sign in to Aurora with {} {} and the password you chose.",
                    self.account_first_name.trim(),
                    self.account_last_name.trim()
                );
            } else {
                self.account_message = if result.output.trim().is_empty() {
                    "The simulator did not confirm the result. Check whether the account exists before retrying.".to_owned()
                } else {
                    result.output.trim().to_owned()
                };
            }
        }
    }

    fn begin_account_creation(&mut self) {
        let first_name = self.account_first_name.trim().to_owned();
        let last_name = self.account_last_name.trim().to_owned();
        let email = self.account_email.trim().to_owned();

        if !self.status.is_running() {
            self.account_message = "Start Woz's World before creating an account.".to_owned();
            return;
        }
        if first_name.is_empty() || last_name.is_empty() {
            self.account_message = "Enter both a first name and a last name.".to_owned();
            return;
        }
        if !valid_account_name(&first_name) || !valid_account_name(&last_name) {
            self.account_message = "Use letters, numbers, periods, apostrophes, hyphens or underscores, with no spaces.".to_owned();
            return;
        }
        if self.account_password.chars().any(char::is_control) {
            self.account_message = "The password cannot contain a line break or other control character.".to_owned();
            return;
        }
        if email.chars().any(char::is_control) {
            self.account_message = "The email field cannot contain a line break or other control character.".to_owned();
            return;
        }
        if self.account_password.is_empty() {
            self.account_message = "Enter a password for the new account.".to_owned();
            return;
        }
        if self.account_password != self.account_password_confirm {
            self.account_message = "The two password entries do not match.".to_owned();
            return;
        }

        let mut request = CreateAccountRequest {
            first_name,
            last_name,
            password: self.account_password.clone(),
            email,
        };
        self.account_request_id = self.account_request_id.wrapping_add(1);
        let request_id = self.account_request_id;
        let sender = self.account_sender.clone();
        let script = self.project_root.join("scripts").join("Create-World-Account.ps1");
        let project_root = self.project_root.clone();
        self.account_in_progress = true;
        self.account_message = "Creating the account on the local simulator…".to_owned();

        thread::spawn(move || {
            let result = (|| -> io::Result<AccountResult> {
                let mut child = Command::new("powershell.exe")
                    .arg("-NoProfile")
                    .arg("-NonInteractive")
                    .arg("-ExecutionPolicy")
                    .arg("Bypass")
                    .arg("-File")
                    .arg(&script)
                    .current_dir(&project_root)
                    .creation_flags(CREATE_NO_WINDOW)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped())
                    .spawn()?;

                let mut request_bytes = serde_json::to_vec(&request)
                    .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
                let mut stdin = child.stdin.take().ok_or_else(|| {
                    io::Error::new(io::ErrorKind::BrokenPipe, "Account helper input is unavailable.")
                })?;
                stdin.write_all(&request_bytes)?;
                drop(stdin);
                request_bytes.fill(0);
                request.password = "\0".repeat(request.password.len());
                request.password.clear();

                let output = child.wait_with_output()?;
                let mut output_text = String::from_utf8_lossy(&output.stdout).trim().to_owned();
                let stderr_text = String::from_utf8_lossy(&output.stderr)
                    .trim()
                    .to_owned();
                if output_text.is_empty() && !stderr_text.is_empty() {
                    output_text = stderr_text;
                }

                Ok(AccountResult {
                    request_id,
                    exit_code: output.status.code(),
                    output: output_text,
                    error: None,
                })
            })();

            let account_result = result.unwrap_or_else(|error| AccountResult {
                request_id,
                exit_code: None,
                output: String::new(),
                error: Some(format!("Could not start the local account helper: {error}")),
            });
            let _ = sender.send(account_result);
        });
    }

    fn refresh_status(&mut self) {
        self.status = inspect_world(&self.project_root);
        self.last_status_check = Instant::now();
    }

    fn save_settings(&self) -> io::Result<()> {
        let local_dir = self.project_root.join(".local");
        fs::create_dir_all(&local_dir)?;
        let target = local_dir.join("world-dock-settings.json");
        let bytes = serde_json::to_vec_pretty(&self.settings)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
        fs::write(target, bytes)
    }

    fn open_logs(&mut self) {
        let path = self.project_root.join("logs");
        match Command::new("explorer.exe")
            .arg(path)
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
        {
            Ok(_) => {
                self.last_operation = "Opened the world logs folder.".to_owned();
            }
            Err(error) => {
                self.last_operation = format!("Could not open the logs folder: {error}");
            }
        }
    }

    fn draw_details(&mut self, ctx: &egui::Context) {
        egui::Window::new("World Dock details")
            .open(&mut self.show_details)
            .default_size(Vec2::new(470.0, 310.0))
            .show(ctx, |ui| {
                ui.label(RichText::new(&self.last_operation).strong());
                ui.separator();
                ui.label(format!("Project: {}", self.project_root.display()));
                ui.label(format!(
                    "Process record: {}",
                    self.project_root
                        .join(".local")
                        .join("opensim-process.json")
                        .display()
                ));
                ui.label(format!("Current status: {}", self.status.detail()));
                ui.separator();
                ui.label(RichText::new("Last command output").strong());
                egui::ScrollArea::vertical()
                    .max_height(150.0)
                    .show(ui, |ui| {
                        if self.last_output.is_empty() {
                            ui.weak("No command output yet.");
                        } else {
                            ui.monospace(&self.last_output);
                        }
                    });
            });
    }
}

impl eframe::App for WorldDock {
    fn ui(&mut self, root_ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = root_ui.ctx().clone();
        self.receive_operation_results();

        if self.last_status_check.elapsed() >= STATUS_REFRESH {
            self.refresh_status();
        }

        // The server can be ready before PowerShell finishes its final checks.
        // Let the user stop a verified live world without waiting on that wrapper.
        if self.active_operation == Some(Operation::Start) && self.status.is_running() {
            self.active_operation = None;
            self.last_operation =
                "World is responding; the start script is finishing its checks.".to_owned();
        }

        ctx.request_repaint_after(Duration::from_millis(300));

        egui::CentralPanel::default().show(root_ui, |ui| {
            ui.add_space(3.0);
            ui.horizontal(|ui| {
                ui.heading("Woz's World");
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(RichText::new("LOCAL SIM").small().color(Color32::LIGHT_BLUE));
                });
            });
            ui.add_space(5.0);

            egui::Frame::new()
                .fill(Color32::from_rgb(25, 34, 45))
                .stroke(egui::Stroke::new(1.0, Color32::from_rgb(54, 69, 83)))
                .corner_radius(8.0)
                .inner_margin(egui::Margin::symmetric(12, 9))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        let mut checked = self.status.is_running();
                        ui.add_enabled(
                            false,
                            egui::Checkbox::new(&mut checked, "Server running"),
                        );
                        ui.label(
                            RichText::new(self.status.label())
                                .strong()
                                .color(self.status.color()),
                        );
                    });
                    ui.label(RichText::new(self.status.detail()).small());
                });

            ui.add_space(10.0);
            ui.horizontal(|ui| {
                let start_enabled =
                    self.active_operation.is_none() && self.status.can_start();
                let stop_enabled = self.status.can_stop()
                    && (self.active_operation.is_none()
                        || self.active_operation == Some(Operation::Start));

                if ui
                    .add_enabled(start_enabled, egui::Button::new("▶  Start"))
                    .clicked()
                {
                    self.begin_operation(Operation::Start);
                }
                if ui
                    .add_enabled(stop_enabled, egui::Button::new("■  Graceful stop"))
                    .clicked()
                {
                    self.begin_operation(Operation::Stop);
                }
                let create_enabled = self.status.is_running() && !self.account_in_progress;
                if ui
                    .add_enabled(create_enabled, egui::Button::new("Create Account"))
                    .clicked()
                {
                    self.show_create_account = true;
                    self.account_message.clear();
                }
            });

            ui.horizontal(|ui| {
                if ui
                    .checkbox(&mut self.settings.always_on_top, "Keep on top")
                    .changed()
                {
                    let level = if self.settings.always_on_top {
                        WindowLevel::AlwaysOnTop
                    } else {
                        WindowLevel::Normal
                    };
                    ctx.send_viewport_cmd(ViewportCommand::WindowLevel(level));
                    if let Err(error) = self.save_settings() {
                        self.last_operation = format!("Could not save panel setting: {error}");
                    }
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.small_button("Details").clicked() {
                        self.show_details = true;
                    }
                    if ui.small_button("Logs").clicked() {
                        self.open_logs();
                    }
                    if ui.small_button("Refresh").clicked() {
                        self.refresh_status();
                    }
                });
            });

            if let Some(operation) = self.active_operation {
                ui.label(
                    RichText::new(operation.label())
                        .small()
                        .color(Color32::from_rgb(244, 191, 82)),
                );
            }

            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                ui.weak("Closing this panel leaves the simulator running.");
            });
        });

        if self.show_details {
            self.draw_details(&ctx);
        }
        if self.show_create_account {
            self.draw_create_account(&ctx);
        }
    }
}

impl WorldDock {
    fn draw_create_account(&mut self, ctx: &egui::Context) {
        let mut submit = false;
        let mut is_open = self.show_create_account;
        let mut close_clicked = false;
        egui::Window::new("Create a local account")
            .open(&mut is_open)
            .collapsible(false)
            .resizable(false)
            .default_width(430.0)
            .show(ctx, |ui| {
                ui.label("Create a separate regular account on your local Woz's World simulator.");
                ui.label("Nothing is created until you select Create account.");
                ui.weak("Use one word for each name. The password is not saved by the Dock.");
                ui.add_space(8.0);

                ui.label("First name");
                ui.add(egui::TextEdit::singleline(&mut self.account_first_name).desired_width(f32::INFINITY));
                ui.label("Last name");
                ui.add(egui::TextEdit::singleline(&mut self.account_last_name).desired_width(f32::INFINITY));
                ui.label("Email (optional)");
                ui.add(egui::TextEdit::singleline(&mut self.account_email).desired_width(f32::INFINITY));
                ui.label("Password");
                ui.add(egui::TextEdit::singleline(&mut self.account_password).password(true).desired_width(f32::INFINITY));
                ui.label("Confirm password");
                ui.add(egui::TextEdit::singleline(&mut self.account_password_confirm).password(true).desired_width(f32::INFINITY));
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    if ui
                        .add_enabled(!self.account_in_progress, egui::Button::new("Create account"))
                        .clicked()
                    {
                        submit = true;
                    }
                    if ui.button("Close").clicked() {
                        close_clicked = true;
                    }
                    if self.account_in_progress {
                        ui.spinner();
                    }
                });
                if !self.account_message.is_empty() {
                    ui.add_space(5.0);
                    ui.label(&self.account_message);
                }
            });
        self.show_create_account = is_open && !close_clicked;
        if submit {
            self.begin_account_creation();
        }
    }
}

fn valid_account_name(value: &str) -> bool {
    !value.is_empty()
        && value.chars().all(|character| {
            character.is_alphanumeric() || matches!(character, '.' | '\'' | '-' | '_')
        })
}

fn inspect_world(project_root: &Path) -> WorldStatus {
    let default_port = configured_port(project_root);
    let process_file = project_root
        .join(".local")
        .join("opensim-process.json");
    let recorded = match fs::read(&process_file) {
        Ok(mut bytes) => {
            if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
                bytes.drain(..3);
            }
            match serde_json::from_slice::<ManagedProcess>(&bytes) {
                Ok(state) => Some(state),
                Err(error) => {
                    let port_open = tcp_is_open(default_port);
                    if port_open {
                        return WorldStatus::UnmanagedListener;
                    }
                    return WorldStatus::Attention(format!(
                        "The managed process record could not be read: {error}"
                    ));
                }
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        Err(error) => {
            return WorldStatus::Attention(format!(
                "Could not read the managed process record: {error}"
            ));
        }
    };

    let Some(recorded) = recorded else {
        return if tcp_is_open(default_port) {
            WorldStatus::UnmanagedListener
        } else {
            WorldStatus::Stopped
        };
    };

    let expected_runtime = project_root.join("runtime").join("dotnet10").join("dotnet.exe");
    if !same_windows_path(&recorded.dotnet_path, &expected_runtime) {
        return WorldStatus::Attention(
            "The process record points to a different .NET runtime. Use the project scripts to reconcile it."
                .to_owned(),
        );
    }

    let actual_path = match process_image_path(recorded.process_id) {
        Ok(Some(path)) => path,
        Ok(None) => {
            return if tcp_is_open(recorded.http_port) {
                WorldStatus::UnmanagedListener
            } else {
                WorldStatus::Stopped
            };
        }
        Err(error) => {
            return WorldStatus::Attention(format!(
                "Could not inspect the recorded process: {error}"
            ));
        }
    };

    if !same_windows_path(&actual_path, &recorded.dotnet_path) {
        return if tcp_is_open(recorded.http_port) {
            WorldStatus::UnmanagedListener
        } else {
            WorldStatus::Attention(
                "The recorded PID now belongs to a different executable.".to_owned(),
            )
        };
    }

    if tcp_is_open(recorded.http_port) {
        if recorded.ready_utc.is_some() {
            WorldStatus::Running {
                process_id: recorded.process_id,
            }
        } else {
            WorldStatus::Starting {
                process_id: recorded.process_id,
            }
        }
    } else if recorded.ready_utc.is_some() {
        WorldStatus::Unresponsive {
            process_id: recorded.process_id,
        }
    } else {
        WorldStatus::Starting {
            process_id: recorded.process_id,
        }
    }
}

fn configured_port(project_root: &Path) -> u16 {
    let path = project_root.join(".local").join("install.json");
    let Ok(bytes) = fs::read(path) else { return DEFAULT_PORT };
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes) else { return DEFAULT_PORT };
    value
        .get("worldPort")
        .and_then(serde_json::Value::as_u64)
        .and_then(|port| u16::try_from(port).ok())
        .filter(|port| *port >= 1024)
        .unwrap_or(DEFAULT_PORT)
}

fn tcp_is_open(port: u16) -> bool {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&address, CONNECT_TIMEOUT).is_ok()
}

fn read_text_file(path: &Path) -> String {
    let Ok(bytes) = fs::read(path) else {
        return String::new();
    };
    if let Some(utf16) = bytes.strip_prefix(&[0xFF, 0xFE]) {
        let words = utf16
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16_lossy(&words).trim().to_owned();
    }
    String::from_utf8_lossy(&bytes).trim().to_owned()
}

fn same_windows_path(left: &Path, right: &Path) -> bool {
    let left = canonical_or_absolute(left);
    let right = canonical_or_absolute(right);
    normalize_windows_path(&left).eq_ignore_ascii_case(&normalize_windows_path(&right))
}

fn canonical_or_absolute(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn normalize_windows_path(path: &Path) -> String {
    let text = path.to_string_lossy().replace('/', "\\");
    text.strip_prefix(r"\\?\").unwrap_or(&text).to_owned()
}

#[cfg(windows)]
fn process_image_path(process_id: u32) -> Result<Option<PathBuf>, String> {
    use std::{ffi::OsString, os::windows::ffi::OsStringExt};
    use windows_sys::Win32::{
        Foundation::{CloseHandle, GetLastError},
        System::Threading::{
            OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
        },
    };

    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, process_id);
        if process.is_null() {
            let error = GetLastError();
            if error == 87 || error == 1168 {
                return Ok(None);
            }
            return Err(format!("OpenProcess returned Windows error {error}."));
        }

        let mut buffer = vec![0u16; 32_768];
        let mut length = buffer.len() as u32;
        let queried =
            QueryFullProcessImageNameW(process, 0, buffer.as_mut_ptr(), &mut length) != 0;
        let error = if queried { 0 } else { GetLastError() };
        CloseHandle(process);

        if !queried {
            return Err(format!(
                "QueryFullProcessImageNameW returned Windows error {error}."
            ));
        }

        buffer.truncate(length as usize);
        Ok(Some(PathBuf::from(OsString::from_wide(&buffer))))
    }
}

fn find_project_root() -> Result<PathBuf, String> {
    if let Some(override_root) = std::env::var_os("WOZ_WORLD_ROOT") {
        let path = PathBuf::from(override_root);
        if is_project_root(&path) {
            return Ok(path);
        }
        return Err(format!(
            "WOZ_WORLD_ROOT does not contain the Woz's World scripts: {}",
            path.display()
        ));
    }

    let mut starts = Vec::new();
    if let Ok(executable) = std::env::current_exe() {
        if let Some(parent) = executable.parent() {
            starts.push(parent.to_path_buf());
        }
    }
    if let Ok(current) = std::env::current_dir() {
        starts.push(current);
    }

    for start in starts {
        for ancestor in start.ancestors() {
            if is_project_root(ancestor) {
                return Ok(ancestor.to_path_buf());
            }
        }
    }

    Err("Could not locate the Woz's World project. Set WOZ_WORLD_ROOT to its folder.".to_owned())
}

fn is_project_root(path: &Path) -> bool {
    path.join("scripts").join("Start-World.ps1").is_file()
        && path.join("scripts").join("Stop-World.ps1").is_file()
}

fn load_settings(project_root: &Path) -> Settings {
    fs::read(project_root.join(".local").join("world-dock-settings.json"))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn icon_data() -> eframe::egui::IconData {
    // The desktop shortcut embeds the same simple globe artwork as an ICO resource.
    // eframe expects raw RGBA, so draw a small matching vector globe here.
    let width = 64usize;
    let mut rgba = Vec::with_capacity(width * width * 4);
    for y in 0..width {
        for x in 0..width {
            let dx = x as f32 - 31.5;
            let dy = y as f32 - 31.5;
            let distance = (dx * dx + dy * dy).sqrt();
            let color = if distance > 30.0 {
                [0, 0, 0, 0]
            } else if distance > 27.7 {
                [180, 226, 239, 255]
            } else if (dx.abs() < 2.0 && distance < 26.0)
                || ((dy.abs() - 10.0).abs() < 1.5 && dx.abs() < 25.0)
                || ((dy.abs() - 19.0).abs() < 1.5 && dx.abs() < 20.0)
            {
                [92, 154, 181, 255]
            } else {
                [18, 47, 68, 255]
            };
            rgba.extend_from_slice(&color);
        }
    }

    eframe::egui::IconData {
        rgba,
        width: width as u32,
        height: width as u32,
    }
}

fn main() -> eframe::Result<()> {
    let project_root = find_project_root().map_err(|message| {
        eprintln!("{message}");
        eframe::Error::AppCreation(Box::new(io::Error::new(
            io::ErrorKind::NotFound,
            message,
        )))
    })?;
    let settings = load_settings(&project_root);
    let mut viewport = ViewportBuilder::default()
        .with_app_id("woz-world-dock")
        .with_inner_size([510.0, 275.0])
        .with_min_inner_size([490.0, 260.0])
        .with_resizable(false)
        .with_icon(std::sync::Arc::new(icon_data()));
    if settings.always_on_top {
        viewport = viewport.with_always_on_top();
    }

    let native_options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };

    eframe::run_native(
        "Woz's World Dock",
        native_options,
        Box::new(move |_creation_context| {
            Ok(Box::new(WorldDock::new(project_root, settings)))
        }),
    )
}
