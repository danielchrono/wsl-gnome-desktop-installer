//! Orquestrador `Install-WslUbuntuGui.ps1` (etapas S0-S7 + pre-checks).
//!
//! Construtores de comando e decisoes sao puros (testaveis no Linux, com os
//! mesmos textos do PowerShell). Execucao WSL/Windows atras de
//! `cfg(windows)` ([`run_install`]); fora do Windows, erro tipado.

use crate::error::InstallError;

/// Nome do icone (`$ICON_FILE`).
pub const ICON_FILE: &str = "ubuntu.ico";
/// Codinome do Ubuntu alvo, informativo (`$UBUNTU_CODENAME`, 26.04 LTS).
pub const UBUNTU_CODENAME: &str = "resolute";
/// Nome do log de transcript (`$LogFile` em TEMP).
pub const LOG_FILE_NAME: &str = "Ubuntu-GUI-install.log";
/// Nome do arquivo de usuario salvo (`$SavedUserFile`).
pub const SAVED_USER_FILE_NAME: &str = "linux-user.txt";
/// Marcador idempotente do bloco WSLg no `.bashrc`.
pub const BASHRC_MARKER: &str = "WSLg: expoe o socket Wayland";
/// Prefixo APT (`$apt`; via `env`: sudo nao entende `export`).
pub const APT_ENV_PREFIX: &str = "env DEBIAN_FRONTEND=noninteractive";

/// Bloco WSLg no `.bashrc` (idempotente: so adiciona uma vez).
pub const BASHRC_BLOCK: &str = "\n# WSLg: expoe o socket Wayland no runtime dir padrao + tipo de sessao p/ apps GNOME\nif [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then\n  : \"${XDG_RUNTIME_DIR:=/run/user/$(id -u)}\"\n  [ -e \"$XDG_RUNTIME_DIR/wayland-0\" ] || ln -sf /mnt/wslg/runtime-dir/wayland-0 \"$XDG_RUNTIME_DIR/wayland-0\"\nfi\nexport WAYLAND_DISPLAY=\"${WAYLAND_DISPLAY:-wayland-0}\" DISPLAY=\"${DISPLAY:-:0}\" XDG_SESSION_TYPE=\"${XDG_SESSION_TYPE:-wayland}\"\nexport XDG_CURRENT_DESKTOP=\"${XDG_CURRENT_DESKTOP:-ubuntu:GNOME}\"\n";

/// `^\\d+x\\d+$`: resolucao `WxH` valida (monitor ou fallback).
pub fn is_valid_resolution(res: &str) -> bool {
    match res.split_once('x') {
        Some((w, h)) => {
            !w.is_empty()
                && !h.is_empty()
                && w.bytes().all(|b| b.is_ascii_digit())
                && h.bytes().all(|b| b.is_ascii_digit())
        }
        None => false,
    }
}

/// Resposta ao prompt de reboot (`[S/n]`, padrao sim): vazio ou comeca com `s`.
pub fn wants_reboot_now(answer: &str) -> bool {
    answer.trim().is_empty() || answer.trim().to_lowercase().starts_with('s')
}

/// Garante `networkingMode=mirrored` no `.wslconfig` (CRLF, como o PS).
/// Retorna `(conteudo, mudou?)`: sem `networkingMode=` adiciona apos `[wsl2]`
/// (criando o cabecalho se preciso); com a chave, nao toca.
pub fn ensure_wslconfig_mirrored(existing: &str) -> (String, bool) {
    let has_key = existing.lines().any(|l| {
        let t = l.trim_start();
        t.starts_with("networkingMode") && t["networkingMode".len()..].trim_start().starts_with('=')
    });
    if has_key {
        return (existing.to_string(), false);
    }
    let mut lines: Vec<String> = existing.lines().map(str::to_string).collect();
    match lines.iter().position(|l| l.trim() == "[wsl2]") {
        Some(i) => lines.insert(i + 1, "networkingMode=mirrored".to_string()),
        None => {
            lines.insert(0, "networkingMode=mirrored".to_string());
            lines.insert(0, "[wsl2]".to_string());
        }
    }
    (format!("{}\r\n", lines.join("\r\n").trim()), true)
}

// --- etapa 2: usuario + systemd -------------------------------------------

/// `id -u <user> 2>/dev/null || echo MISSING`.
pub fn user_exists_command(linux_user: &str) -> String {
    format!("id -u {linux_user} 2>/dev/null || echo MISSING")
}

/// Criacao: `useradd ... && echo 'u:pwq' | chpasswd && usermod -aG sudo`.
pub fn create_user_command(linux_user: &str, password_quote: &str) -> String {
    format!(
        "useradd -m -s /bin/bash '{linux_user}' && echo '{linux_user}:{password_quote}' | chpasswd && usermod -aG sudo '{linux_user}'"
    )
}

/// Senha do Linux atualizada para a digitada (conta existente: NADA apagado).
pub fn update_password_command(linux_user: &str, password_quote: &str) -> String {
    format!("echo '{linux_user}:{password_quote}' | chpasswd")
}

/// Checagem do `wsl.conf` (systemd + usuario padrao).
pub fn wsl_conf_check_command(linux_user: &str) -> String {
    format!(
        "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && grep -q 'default={linux_user}' /etc/wsl.conf 2>/dev/null && echo OK || echo FIX"
    )
}

/// Escrita do `wsl.conf` (exige `wsl --shutdown` para valer).
pub fn wsl_conf_write_command(linux_user: &str) -> String {
    format!("printf '[boot]\\nsystemd=true\\n[user]\\ndefault={linux_user}\\n' > /etc/wsl.conf")
}

/// Parser de `systemctl is-system-running`: `running` ou `degraded`.
pub fn is_systemd_running(out: &str) -> bool {
    out.contains("running") || out.contains("degraded")
}

// --- etapa 3: pacote GUI ----------------------------------------------------

/// `dpkg -l <pkg> ... && echo OK || echo MISSING`.
pub fn gui_installed_check_command(gui_package: &str) -> String {
    format!("dpkg -l {gui_package} 2>/dev/null | grep -q '^ii' && echo OK || echo MISSING")
}

/// `apt-get update` via sudo com a senha no stdin.
pub fn apt_update_command(password_quote: &str) -> String {
    format!(
        "printf '%s\\n' '{password_quote}' | sudo -S {APT_ENV_PREFIX} apt-get update 2>&1 | tail -n 1"
    )
}

/// `apt-get install -y <pkg> gnome-remote-desktop openssl python3-pil curl`.
pub fn apt_install_command(gui_package: &str, password_quote: &str) -> String {
    format!(
        "printf '%s\\n' '{password_quote}' | sudo -S {APT_ENV_PREFIX} apt-get install -y {gui_package} gnome-remote-desktop openssl python3-pil curl 2>&1 | tail -n 2"
    )
}

/// GDM nunca no WSL (conflita com o Weston do WSLg).
pub fn gdm_disable_command(password_quote: &str, gdm_service: &str, gdm_alias: &str) -> String {
    format!(
        "printf '%s\\n' '{password_quote}' | sudo -S systemctl stop {gdm_service} 2>/dev/null; printf '%s\\n' '{password_quote}' | sudo -S systemctl disable {gdm_service} {gdm_alias} 2>/dev/null | tail -n 1"
    )
}

/// Checagem do bloco WSLg no `.bashrc`.
pub fn bashrc_check_command() -> String {
    format!("grep -q '{BASHRC_MARKER}' ~/.bashrc && echo OK || echo MISSING")
}

// --- etapa 4: shell headless -------------------------------------------------

/// Unit systemd do GNOME headless na resolucao `RES`.
pub fn shell_unit_content(shell_binary: &str, res: &str, restart_sec: u64) -> String {
    format!(
        "\n[Unit]\nDescription=GNOME Shell headless (desktop Ubuntu completo via RDP)\nBefore=gnome-remote-desktop.service\nAfter=dbus.socket\nWants=dbus.socket\n[Service]\nEnvironment=XDG_SESSION_TYPE=wayland\nEnvironment=XDG_CURRENT_DESKTOP=ubuntu:GNOME\nEnvironment=XDG_RUNTIME_DIR=%t\nEnvironment=LIBGL_ALWAYS_SOFTWARE=1\nExecStart=/usr/bin/{shell_binary} --mode=ubuntu --wayland --headless --no-x11 --virtual-monitor {res}\nRestart=on-failure\nRestartSec={restart_sec}\n[Install]\nWantedBy=default.target\n"
    )
}

/// Caminho da unit no home do usuario.
pub fn shell_unit_path(shell_service: &str) -> String {
    format!("~/.config/systemd/user/{shell_service}")
}

/// Reinicia so se nao houver Shell rodando exatamente nesta resolucao.
pub fn shell_current_command(shell_binary: &str, res: &str) -> String {
    format!("pgrep -af '{shell_binary}.*--virtual-monitor {res}' | grep -qv 'bin/sh' && echo CURRENT || echo STALE")
}

// --- etapa 5: RDP + cofre -----------------------------------------------------

/// Checagem do cert TLS autoassinado.
pub fn tls_cert_check_command(tls_cert_path: &str) -> String {
    format!("test -f {tls_cert_path} && echo OK || echo MISSING")
}

/// Criacao do cert TLS (`openssl req ... -days <tls_days>`).
pub fn tls_cert_create_command(tls_cert_path: &str, tls_key_path: &str, tls_days: u32) -> String {
    format!(
        "mkdir -p ~/.local/share/gnome-remote-desktop && openssl req -x509 -newkey rsa:2048 -keyout {tls_key_path} -out {tls_cert_path} -days {tls_days} -nodes -subj '/CN=ubuntu-wsl'"
    )
}

/// Pre-voo da `--rdp-port` explicita: porta ocupada AGORA? Aviso apenas —
/// a verificacao pos-apply e o gate real, e rerun com a mesma porta ocupada
/// pelo proprio RDP anterior nao pode falhar.
pub fn probe_tcp_port(host: &str, port: u16, timeout_ms: u64) -> bool {
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;
    let addr: SocketAddr = match format!("{host}:{port}").parse() {
        Ok(a) => a,
        Err(_) => return false,
    };
    TcpStream::connect_timeout(&addr, Duration::from_millis(timeout_ms)).is_ok()
}

/// Aplica TLS/porta + habilita e reinicia o RDP.
pub fn rdp_apply_command(
    tls_cert_path: &str,
    tls_key_path: &str,
    rdp_port: u16,
    rdp_service: &str,
) -> String {
    format!(
        "grdctl rdp set-tls-cert {tls_cert_path} 2>/dev/null; grdctl rdp set-tls-key {tls_key_path} 2>/dev/null; grdctl rdp set-port {rdp_port} 2>/dev/null; grdctl rdp disable-view-only 2>/dev/null; grdctl rdp enable 2>/dev/null; systemctl --user enable {rdp_service} 2>/dev/null; systemctl --user restart {rdp_service} 2>&1 | tail -n 1"
    )
}

// --- etapa 6: icone + atalhos --------------------------------------------------

/// `C:\...` -> `/mnt/c/...` (sintaxe compativel; pura e testavel).
pub fn windows_path_to_wsl(path: &str) -> String {
    if path.len() >= 2 && path.as_bytes()[1] == b':' {
        let drive = path[..1].to_lowercase();
        let rest = path[2..].replace('\\', "/");
        format!("/mnt/{drive}{rest}")
    } else {
        path.replace('\\', "/")
    }
}

/// `(16 ,16),(32 ,32),...` para o `sizes=[...]` do PIL.
pub fn icon_sizes_arg(icon_sizes: &[u32]) -> String {
    icon_sizes
        .iter()
        .map(|s| format!("({s} ,{s})"))
        .collect::<Vec<_>>()
        .join(",")
}

/// `curl` do icone oficial + conversao multi-tamanho via PIL no WSL.
pub fn icon_build_command(icon_url: &str, wsl_ico_path: &str, sizes_arg: &str) -> String {
    format!(
        "curl -sL --max-time 60 -o /tmp/cof.png '{icon_url}' && python3 -c `\"from PIL import Image; im=Image.open('/tmp/cof.png').convert('RGBA'); S=max(im.size); sq=Image.new('RGBA',(S,S),(0,0,0,0)); sq.paste(im,((S-im.width)//2,(S-im.height)//2),im); sq.save('{wsl_ico_path}',sizes=[{sizes_arg}])`\""
    )
}

/// `wsl --install -d <distro> --no-launch`: instala SEM abrir o OOBE
/// interativo (que pediria usuario/senha/metricas de novo no console - a
/// etapa 2 ja provisiona tudo sozinha via useradd/chpasswd). Sem
/// `--no-launch`, o instalador do Ubuntu gruda no console e a run trava
/// nele antes mesmo do reboot programado.
pub fn wsl_install_argv(distro: &str) -> Vec<String> {
    vec![
        "wsl".to_string(),
        "--install".to_string(),
        "-d".to_string(),
        distro.to_string(),
        "--no-launch".to_string(),
    ]
}

/// Comando de reboot com conta regressiva (+ dica `shutdown /a`).
pub fn shutdown_reboot_command(delay_sec: u64) -> String {
    format!("shutdown /r /t {delay_sec} /c \"Ubuntu-GUI: reiniciando p/ continuar a instalacao sozinho\"")
}

// --- etapa 7: verificacao -------------------------------------------------------

/// Checagem da etapa 7 (`@{ N; C; Want }`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifyCheck {
    pub name: String,
    pub command: String,
    pub want: String,
}

/// As 3 sondas ponta a ponta (Shell, Dock, RDP).
pub fn verify_checks(shell_service: &str, rdp_service: &str, rdp_port: u16) -> Vec<VerifyCheck> {
    vec![
        VerifyCheck {
            name: "Shell headless ativo".to_string(),
            command: crate::health::shell_active_command(shell_service),
            want: "^active$".to_string(),
        },
        VerifyCheck {
            name: "Dock do Ubuntu ativo".to_string(),
            command: "gnome-extensions list --enabled 2>/dev/null | grep -q ubuntu-dock && echo YES || echo NO".to_string(),
            want: "YES".to_string(),
        },
        VerifyCheck {
            name: format!("RDP ouvindo :{rdp_port}"),
            command: crate::health::rdp_listening_command(rdp_service, rdp_port),
            want: "OK".to_string(),
        },
    ]
}

/// `$r.Out -match $t.Want`: `^x$` = igualdade apos trim; resto = substring.
pub fn check_output_matches(out: &str, want: &str) -> bool {
    if let Some(inner) = want.strip_prefix('^').and_then(|s| s.strip_suffix('$')) {
        out.trim() == inner
    } else {
        out.contains(want)
    }
}

/// Extrai o build do Windows da saida de `cmd /c ver`
/// (`Microsoft Windows [Version 10.0.22621.1]` -> `22621`).
pub fn parse_windows_build(ver_output: &str) -> Option<u32> {
    let v = ver_output.split("Version").nth(1)?;
    let mut parts = v.split('.');
    parts.next()?;
    parts.next()?;
    parts
        .next()?
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .ok()
}

/// Resultado do instalador: `Done` = TUDO PRONTO; `RebootRequired` = etapa 1
/// escreveu o RunOnce e saiu (bare `return` no PS -> exit 0 + sentinela).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallOutcome {
    Done,
    RebootRequired,
}

/// Tentativas de digitacao da senha antes do fail-fast (errar a confirmacao
/// nao mata o run na primeira).
pub const PASSWORD_MAX_ATTEMPTS: u32 = 3;

/// Opcoes do instalador (params de `Install-WslUbuntuGui` + `--resume` e
/// transcript do `main`, que substituem head/tail/header/footer).
#[derive(Debug, Clone, Default)]
pub struct InstallOptions {
    pub linux_user: Option<String>,
    pub linux_password: Option<String>,
    pub net_choice: Option<String>,
    pub resume_file: Option<std::path::PathBuf>,
    pub distro: Option<String>,
    pub gui_package: Option<String>,
    pub fallback_resolution: Option<String>,
    pub rdp_port: Option<u16>,
    pub app_name: Option<String>,
    pub no_tui: bool,
    pub transcript: Option<std::path::PathBuf>,
}

/// Reporter: imprime `Step/Ok/Warn/Fail` e acumula falhas (substitui
/// `$script:Failures` + transcript para as nossas linhas; saida de comandos
/// externos nao vai ao log — melhor que o PS, cujo log guardava a senha).
pub struct Reporter {
    failures: Vec<String>,
    log: Option<std::fs::File>,
}

impl Reporter {
    pub fn new(log_path: Option<&std::path::Path>) -> Self {
        let log = log_path.and_then(|p| {
            if let Some(parent) = p.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(p)
                .ok()
        });
        Self {
            failures: Vec::new(),
            log,
        }
    }

    fn emit(&mut self, line: String) {
        println!("{line}");
        if let Some(f) = self.log.as_mut() {
            use std::io::Write;
            let _ = writeln!(f, "{line}");
        }
    }

    pub fn step(&mut self, msg: &str) {
        self.emit(crate::feedback::step(msg));
    }

    pub fn ok(&mut self, msg: &str) {
        self.emit(crate::feedback::ok(msg));
    }

    pub fn warn(&mut self, msg: &str) {
        self.emit(crate::feedback::warn(msg));
    }

    pub fn fail(&mut self, msg: String) {
        let (line, _) = crate::feedback::fail(&crate::feedback::FeedbackState::new(), &msg);
        self.failures.push(msg);
        self.emit(line);
    }

    pub fn say(&mut self, line: &str) {
        self.emit(line.to_string());
    }

    pub fn failures(&self) -> &[String] {
        &self.failures
    }
}

/// Execucao completa S0-S7 (Windows). Fora do Windows: erro tipado.
#[cfg(not(windows))]
pub fn run_install(_opts: &InstallOptions) -> Result<InstallOutcome, InstallError> {
    Err(InstallError::NotSupportedOnLinux(
        "Install-WslUbuntuGui (wsl.exe)",
    ))
}

/// Execucao completa S0-S7 no Windows. Mensagens, comandos e exit codes
/// identicos ao PowerShell; `RebootRequired` = bare `return` da etapa 1.
#[cfg(windows)]
pub fn run_install(opts: &InstallOptions) -> Result<InstallOutcome, InstallError> {
    use std::io::{BufRead, Write};
    use std::path::PathBuf;
    use std::process::Command;
    use std::time::Duration;

    use crate::{
        cert, distro_list, feedback, health, input, ip, launcher, passquote, rdp, resume, secure,
        tui, vault, wsl_cmd,
    };

    let d = crate::constants::defaults();
    let distro = opts.distro.clone().unwrap_or(d.distro.clone());
    let gui_package = opts.gui_package.clone().unwrap_or(d.gui_package.clone());
    let fallback_res = opts
        .fallback_resolution
        .clone()
        .unwrap_or(d.fallback_resolution.clone());
    let rdp_port = opts.rdp_port.unwrap_or(d.rdp_port);
    let app_name = opts.app_name.clone().unwrap_or(d.app_name.clone());
    let no_tui = opts.no_tui;

    let mut rep = Reporter::new(opts.transcript.as_deref());
    rep.say(&format!("Ubuntu-GUI Installer v{}", crate::SCRIPT_VERSION));

    // ---- pre-checks ------------------------------------------------------
    rep.step("Pre-checagens (Windows, rede, WSL)");
    let ver_out = Command::new("cmd")
        .args(["/c", "ver"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default();
    let build = parse_windows_build(&ver_out).unwrap_or(0);
    if build < 19041 {
        rep.fail(format!(
            "Windows 10 2004+ ou 11 necessario (build {ver_out})"
        ));
    } else {
        rep.ok(&format!("Windows build {build}"));
    }
    let net_ok = std::net::TcpStream::connect_timeout(
        &"archive.ubuntu.com:80"
            .parse()
            .unwrap_or(std::net::SocketAddr::from(([0, 0, 0, 0], 0))),
        Duration::from_secs(5),
    )
    .is_ok();
    if !net_ok {
        rep.warn("Sem resposta de archive.ubuntu.com - a instalacao APT pode falhar");
    } else {
        rep.ok("Rede alcanca o repositorio Ubuntu");
    }
    let mut res = fallback_res.clone();
    match primary_monitor_resolution() {
        Some((w, h)) => {
            let cand = format!("{w}x{h}");
            if is_valid_resolution(&cand) {
                res = cand.clone();
                rep.ok(&format!("Resolucao do monitor: {res}"));
            } else {
                rep.warn(&format!("Resolucao ilegivel, usando {res}"));
            }
        }
        None => rep.warn(&format!("Nao deu pra ler a resolucao, usando {res}")),
    }

    // ---- retomada / perguntas -------------------------------------------
    let prog_dir =
        PathBuf::from(std::env::var("LOCALAPPDATA").unwrap_or_else(|_| r"C:\Temp".to_string()))
            .join("Programs")
            .join(&app_name);
    let resume_file = prog_dir.join(resume::RESUME_FILE_NAME);
    let resume_ps1 = prog_dir.join(resume::RESUME_PS1_NAME);
    let saved_user_file = prog_dir.join(SAVED_USER_FILE_NAME);

    let mut linux_user: String;
    let mut linux_pass: secure::SecureStr;
    let mut net_choice: String;
    let mut resumed = false;

    // `--resume <state.json>`: reaproveita as respostas salvas, sem perguntar
    // (substitui o `-Resume` do head + RunOnce `AfterReboot`: o .exe e
    // reagendado pelo proprio RunOnce com `--resume <arquivo>`).
    let resume_candidate = opts
        .resume_file
        .clone()
        .unwrap_or_else(|| resume_file.clone());
    if opts.resume_file.is_some() {
        match std::fs::read_to_string(&resume_candidate)
            .map_err(|e| InstallError::ResumeUnreadable(e.to_string()))
            .and_then(|t| resume::ResumeState::from_json(&t))
        {
            Ok(st) => match resume::unprotect_password_base64(&st.linux_pass_enc) {
                Ok(pass) => {
                    linux_user = st.linux_user.clone();
                    net_choice = if st.net_choice.trim().is_empty() {
                        "1".to_string()
                    } else {
                        st.net_choice.clone()
                    };
                    linux_pass = secure::SecureStr::new(pass);
                    resumed = true;
                    rep.ok(&format!(
                        "Retomando sozinho apos o reboot (usuario {linux_user})"
                    ));
                }
                Err(_) => {
                    rep.warn("Estado de retomada ilegivel - segue perguntando de novo");
                    linux_user = String::new();
                    linux_pass = secure::SecureStr::new("");
                    net_choice = String::new();
                }
            },
            Err(_) => {
                rep.warn("Estado de retomada ilegivel - segue perguntando de novo");
                linux_user = String::new();
                linux_pass = secure::SecureStr::new("");
                net_choice = String::new();
            }
        }
    } else {
        linux_user = String::new();
        linux_pass = secure::SecureStr::new("");
        net_choice = String::new();
    }

    if !resumed {
        linux_user = opts.linux_user.clone().unwrap_or_default();
        if linux_user.trim().is_empty() {
            let saved_raw = std::fs::read_to_string(&saved_user_file).unwrap_or_default();
            let win_user = std::env::var("USERNAME").unwrap_or_default();
            let def_user = input::default_linux_user(Some(&saved_raw), Some(&win_user));
            if tui::tui_available(no_tui) {
                let opts_menu = vec![format!("Usar '{def_user}'"), "Criar um novo".to_string()];
                let idx = tui::show_single_choice_menu("Usuario Linux", &opts_menu, 0, no_tui);
                let typed = if idx == 1 {
                    print!("Novo usuario Linux: ");
                    let _ = std::io::stdout().flush();
                    let mut t = String::new();
                    let _ = std::io::stdin().lock().read_line(&mut t);
                    t.trim().to_string()
                } else {
                    String::new()
                };
                linux_user = input::resolve_user_menu_choice(idx, Some(&typed), &def_user);
            } else {
                print!("Usuario Linux [{def_user}]: ");
                let _ = std::io::stdout().flush();
                let mut t = String::new();
                let _ = std::io::stdin().lock().read_line(&mut t);
                linux_user = if t.trim().is_empty() {
                    def_user
                } else {
                    t.trim().to_string()
                };
            }
        }
        let check = input::test_linux_user_name(&linux_user);
        if !check.ok && check.reason == "reserved" {
            rep.fail("O usuario 'root' e reservado - escolha outro nome".to_string());
            return Err(InstallError::ReservedUser);
        }
        if !check.ok {
            rep.fail(format!(
                "Usuario '{linux_user}' invalido (use minusculas, numeros, _ ou -)"
            ));
            return Err(InstallError::InvalidLinuxUser);
        }
        if let Some(p) = opts.linux_password.clone() {
            linux_pass = secure::SecureStr::new(p);
        } else {
            // Retry: errar a confirmacao nao mata o run (fail-fast so apos N).
            let mut pass = None;
            for attempt in 1..=PASSWORD_MAX_ATTEMPTS {
                let s1 =
                    tui::read_secure_password(&format!("Senha do usuario {linux_user}"), no_tui);
                let s2 = tui::read_secure_password("Confirme a senha", no_tui);
                if input::passwords_match(s1.expose(), s2.expose()) {
                    pass = Some(s1);
                    break;
                }
                if attempt < PASSWORD_MAX_ATTEMPTS {
                    rep.warn(&format!(
                        "Senhas diferentes ou vazias - tente de novo ({attempt}/{PASSWORD_MAX_ATTEMPTS})"
                    ));
                }
            }
            match pass {
                Some(p) => linux_pass = p,
                None => {
                    rep.fail(
                        "Senhas diferentes ou vazias apos 3 tentativas - rode de novo"
                            .to_string(),
                    );
                    return Err(InstallError::PasswordMismatch);
                }
            }
        }
        rep.ok(&format!("Usuario Linux: {linux_user}"));

        if opts.net_choice.as_ref().is_none_or(|s| s.trim().is_empty()) {
            if tui::tui_available(no_tui) {
                let idx = tui::show_single_choice_menu(
                    "Modo de rede",
                    &[
                        "localhost fixo 127.0.0.1 (recomendado)".to_string(),
                        "IP dinamico a cada clique".to_string(),
                    ],
                    0,
                    no_tui,
                );
                net_choice = if idx == 1 {
                    "2".to_string()
                } else {
                    "1".to_string()
                };
            } else {
                print!("Modo de rede [1] localhost fixo 127.0.0.1 (recomendado) ou [2] IP dinamico a cada clique [1]: ");
                let _ = std::io::stdout().flush();
                let mut t = String::new();
                let _ = std::io::stdin().lock().read_line(&mut t);
                net_choice = t.trim().to_string();
            }
        } else {
            net_choice = opts.net_choice.clone().unwrap_or_default();
        }
        let resolved = input::resolve_network_choice(Some(&net_choice));
        net_choice = resolved.normalized;
        if resolved.want_mirrored {
            rep.ok("Modo: localhost fixo 127.0.0.1 (masked)");
        } else {
            rep.say("  Modo: IP dinamico - o atalho identifica o IP automaticamente a cada clique");
        }
        if resume_file.exists() {
            let _ = resume::clear_run_once();
            let _ = std::fs::remove_file(&resume_file);
            let _ = std::fs::remove_file(&resume_ps1);
            rep.warn("Retomada pendente cancelada (novo run manual)");
        }
    }
    let pwq = passquote::get_password_quote(linux_pass.expose());
    let want_mirrored = input::resolve_network_choice(Some(&net_choice)).want_mirrored;

    // ---- 1. WSL + distro --------------------------------------------------
    rep.step(&format!("1/7 WSL, rede e distro {distro}"));
    let wsl_list = Command::new("wsl")
        .args(["-l", "-q"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default();
    let raw_list: Vec<&str> = wsl_list.lines().collect();
    let distros = distro_list::convert_from_wsl_distro_list(&raw_list);
    if !distros.iter().any(|x| x == &distro) {
        rep.say(&format!("  Instalando WSL + {distro}..."));
        rep.say(&format!("  Sem prompt duplo: o Ubuntu instala sem abrir (o usuario '{linux_user}' e criado sozinho na etapa 2)"));
        let argv = wsl_install_argv(&distro);
        let _ = Command::new(&argv[0]).args(&argv[1..]).status();
        std::thread::sleep(Duration::from_secs(d.fresh_install_wait_sec));
        let probe = Command::new("wsl")
            .args(["-d", &distro, "--", "true"])
            .status()
            .map(|s| s.code().unwrap_or(1))
            .unwrap_or(1);
        if probe == 0 {
            rep.ok("WSL pronto sem reboot - seguindo sozinho");
        } else {
            let enc = resume::protect_password_base64(linux_pass.expose())?;
            let state = resume::build_resume_state(&linux_user, &enc, &net_choice);
            let exe = std::env::current_exe().unwrap_or(prog_dir.join("ubuntu-gui.exe"));
            resume::save_resume_files(&exe, &prog_dir, &state)?;
            rep.ok("Retomada agendada (reabre sozinho apos o reboot)");
            print!("Reiniciar o Windows agora para continuar sozinho? [S/n]: ");
            let _ = std::io::stdout().flush();
            let mut rb = String::new();
            let _ = std::io::stdin().lock().read_line(&mut rb);
            if wants_reboot_now(&rb) {
                rep.say(&format!(
                    "  Reiniciando em {}s (cancele com: shutdown /a)...",
                    d.reboot_delay_sec
                ));
                let _ = Command::new("shutdown")
                    .args([
                        "/r",
                        "/t",
                        &d.reboot_delay_sec.to_string(),
                        "/c",
                        "Ubuntu-GUI: reiniciando p/ continuar a instalacao sozinho",
                    ])
                    .status();
            } else {
                rep.say("  Sem pressa: ao ligar de novo, a instalacao reabre sozinha (sem clicar de novo)");
            }
            return Ok(InstallOutcome::RebootRequired);
        }
    }
    rep.ok(&format!("Distro {distro} presente"));
    let probe = Command::new("wsl")
        .args(["-d", &distro, "--", "true"])
        .status()
        .map(|s| s.code().unwrap_or(1))
        .unwrap_or(1);
    if probe != 0 {
        rep.fail(
            "Distro instalada mas nao inicia - abra o Ubuntu uma vez e rode de novo".to_string(),
        );
        return Err(InstallError::DistroNotStarting);
    }

    let use_mirrored = want_mirrored && build >= d.min_build_mirrored;
    if want_mirrored && build < d.min_build_mirrored {
        rep.warn(&format!(
            "Mirrored exige Win11 22H2+ (build {}+); usando IP dinamico",
            d.min_build_mirrored
        ));
    }
    let mut rdp_host = "127.0.0.1".to_string();
    let mut wsl_restart_needed = false;
    if use_mirrored {
        let wslcfg =
            PathBuf::from(std::env::var("USERPROFILE").unwrap_or_default()).join(".wslconfig");
        let txt = std::fs::read_to_string(&wslcfg).unwrap_or_default();
        let (new_txt, changed) = ensure_wslconfig_mirrored(&txt);
        if changed {
            let _ = std::fs::write(&wslcfg, new_txt);
            wsl_restart_needed = true;
        }
        rep.ok("Mirrored networking (RDP fixo em 127.0.0.1)");
    } else {
        rdp_host = ip::get_wsl_ip_address(&distro)?.unwrap_or_default();
        rep.ok(&format!(
            "IP dinamico - cada clique detecta sozinho ({rdp_host})"
        ));
    }

    // ---- 2. usuario + systemd ----------------------------------------------
    rep.step("2/7 Usuario Linux e systemd");
    let r = wsl_cmd::invoke_wsl_root(Some(&distro), &user_exists_command(&linux_user))?;
    if r.out.contains("MISSING") {
        rep.say(&format!("  Criando usuario {linux_user} (novo)..."));
        let r = wsl_cmd::invoke_wsl_root(Some(&distro), &create_user_command(&linux_user, &pwq))?;
        if r.code != 0 {
            rep.fail(format!("Nao criei o usuario: {}", r.out));
        } else {
            rep.ok(&format!("Usuario {linux_user} criado"));
        }
    } else {
        rep.ok(&format!(
            "Usuario {linux_user} ja existe - NADA sera apagado (home e arquivos intactos)"
        ));
        rep.say("  Atualizando a senha do Linux para a digitada...");
        let rp =
            wsl_cmd::invoke_wsl_root(Some(&distro), &update_password_command(&linux_user, &pwq))?;
        if rp.code == 0 {
            rep.ok("Senha do Linux atualizada");
        } else {
            rep.fail(format!("Nao atualizei a senha: {}", rp.out));
            return Err(InstallError::PasswordNotUpdated);
        }
    }
    let _ = std::fs::create_dir_all(&prog_dir);
    let _ = std::fs::write(&saved_user_file, &linux_user);
    if wsl_cmd::invoke_wsl_root(Some(&distro), &format!("id -u {linux_user} 2>/dev/null"))?.code
        == 0
    {
        rep.ok(&format!("Usuario {linux_user} pronto"));
    }
    let r = wsl_cmd::invoke_wsl_root(Some(&distro), &wsl_conf_check_command(&linux_user))?;
    if r.out.contains("FIX") {
        let _ = wsl_cmd::invoke_wsl_root(Some(&distro), &wsl_conf_write_command(&linux_user))?;
        rep.say("  Reiniciando o WSL para ativar o systemd...");
        let _ = Command::new("wsl").args(["--shutdown"]).status();
        std::thread::sleep(Duration::from_secs(d.wsl_shutdown_wait_sec));
    }
    let r = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        "systemctl is-system-running 2>&1 | head -n 1",
    )?;
    if is_systemd_running(&r.out) {
        rep.ok(&format!("systemd ativo ({})", r.out.trim()));
    } else {
        rep.fail("systemd nao subiu - rode 'wsl --shutdown' e execute de novo".to_string());
        return Err(InstallError::SystemdDown);
    }

    // ---- 3. pacote GUI -------------------------------------------------------
    rep.step(&format!("3/7 Pacote {gui_package} (+ openssl, PIL)"));
    let r = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &gui_installed_check_command(&gui_package),
    )?;
    if r.out.contains("MISSING") {
        rep.say("  apt update + instalacao (~2 GB, demora)...");
        let mut ok = false;
        for i in 1..=d.apt_retries {
            if ok {
                break;
            }
            let _ = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, &apt_update_command(&pwq))?;
            let _ = wsl_cmd::invoke_wsl(
                Some(&distro),
                &linux_user,
                &apt_install_command(&gui_package, &pwq),
            )?;
            ok = wsl_cmd::invoke_wsl(
                Some(&distro),
                &linux_user,
                &format!("dpkg -l {gui_package} 2>/dev/null | grep -q '^ii'"),
            )?
            .code
                == 0;
            if !ok {
                rep.warn(&format!("Tentativa {i} falhou, tentando de novo..."));
            }
        }
        if !ok {
            rep.fail(format!(
                "APT nao concluiu apos {} tentativas - veja o log",
                d.apt_retries
            ));
            return Err(InstallError::AptFailed);
        }
    }
    rep.ok(&format!("{gui_package} instalado"));
    let r = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, "gnome-shell --version 2>&1")?;
    rep.ok(r.out.trim());
    let _ = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &gdm_disable_command(&pwq, &d.gdm_service, &d.gdm_alias),
    )?;
    rep.ok("GDM parado e desabilitado");
    let r = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, &bashrc_check_command())?;
    if r.out.contains("MISSING") {
        wsl_append_stdin(&distro, &linux_user, BASHRC_BLOCK)?;
        rep.ok("Bloco WSLg no .bashrc");
    } else {
        rep.ok("Bloco WSLg ja estava no .bashrc");
    }

    // ---- 4. shell headless -----------------------------------------------------
    rep.step(&format!("4/7 Desktop GNOME headless ({res})"));
    let unit = shell_unit_content(&d.shell_binary, &res, d.shell_restart_sec);
    wsl_write_stdin(
        &distro,
        &linux_user,
        &format!(
            "mkdir -p ~/.config/systemd/user && cat > {}",
            shell_unit_path(&d.shell_service)
        ),
        &unit,
    )?;
    let _ = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &format!(
            "systemctl --user daemon-reload; systemctl --user enable {} 2>&1 | tail -n 1",
            d.shell_service
        ),
    )?;
    let r = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &shell_current_command(&d.shell_binary, &res),
    )?;
    if r.out.contains("STALE") {
        rep.say(&format!("  (Re)iniciando o Shell em {res}..."));
        let _ = wsl_cmd::invoke_wsl(
            Some(&distro),
            &linux_user,
            &format!("systemctl --user restart {}", d.shell_service),
        )?;
        std::thread::sleep(Duration::from_secs(d.shell_restart_wait_sec));
    }
    if health::test_shell_active(&linux_user, &d.shell_service).unwrap_or(false) {
        rep.ok(&format!("GNOME Shell ativo em {res}"));
    } else {
        rep.fail(
            "Shell nao subiu - journal: systemctl --user status gnome-shell-headless".to_string(),
        );
        return Err(InstallError::ShellDown);
    }
    let _ = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, "mkdir -p ~/Desktop")?;

    // ---- 5. RDP + cofre ----------------------------------------------------------
    rep.step("5/7 RDP com TLS e credencial");
    let r = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &tls_cert_check_command(&d.tls_cert_path),
    )?;
    if r.out.contains("MISSING") {
        let _ = wsl_cmd::invoke_wsl(
            Some(&distro),
            &linux_user,
            &tls_cert_create_command(&d.tls_cert_path, &d.tls_key_path, d.tls_cert_days),
        )?;
        rep.ok("Certificado TLS criado");
    }
    let uid = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, "id -u")?
        .out
        .trim()
        .to_string();
    // Prestart leve: daemon no ar antes de tudo (warn-only, nunca aborta;
    // criar via --login cobre o resto).
    if vault::start_keyring_daemon_live(Some(&distro), &linux_user, &uid) {
        rep.ok("Daemon do cofre no ar");
    } else {
        rep.warn("Daemon do cofre nao respondeu - tentando criar via --login mesmo assim");
    }
    // Cria quando ausente (via --login: sem sudo/pam.d, ja sai destravado).
    let (created, fresh) = vault::ensure_login_keyring_live(
        Some(&distro),
        &linux_user,
        &pwq,
        &uid,
        &d.keyring_path,
    )?;
    if fresh {
        rep.ok("Cofre login criado com a senha informada");
    } else if created {
        rep.ok("Cofre login pronto");
    } else {
        rep.fail("Cofre nao criado (confira ~/.local/share/keyrings/login.keyring e backups *.bak* - sem o arquivo nenhum unlock funciona)".to_string());
        return Err(InstallError::KeyringMissing);
    }
    rep.say("  Desbloqueando o cofre...");
    // Pula unlock se ja destravado (ex.: criado agora via --login).
    let (pam_state, _) = vault::probe_state_live(Some(&distro), &linux_user, &uid)?;
    let uk = if pam_state == vault::ProbeState::Unlocked {
        rep.ok("Cofre ja destravado (pulando unlock)");
        vault::UnlockProbe {
            unlock_code: 0,
            probe: "via --login".to_string(),
            unlock_text: "(via --login)".to_string(),
            state: vault::ProbeState::Unlocked,
        }
    } else {
        vault::unlock_and_probe_live(Some(&distro), &linux_user, &pwq, &uid)?
    };
    if uk.unlock_code != 0 {
        rep.fail(format!("Cofre nao desbloqueou com a senha informada ({}) - cofre de outro run? No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo com UMA senha definitiva (nunca rm: sem o arquivo nada funciona)", uk.unlock_text.trim()));
        return Err(InstallError::KeyringLocked);
    }
    if uk.state != vault::ProbeState::Unlocked {
        // Uma repeticao absorve ativacao lenta do D-Bus; depois classifica
        // Locked (cofre de outro run) vs Missing/Error (outro conserto).
        std::thread::sleep(std::time::Duration::from_secs(d.keyring_reprobe_sec));
        let uk2 = vault::unlock_and_probe_live(Some(&distro), &linux_user, &pwq, &uid)?;
        if uk2.state == vault::ProbeState::Unlocked {
            rep.ok("Cofre destravou na re-sonda");
        } else if uk2.state == vault::ProbeState::Missing {
            rep.fail(format!("Colecao login ausente (daemon responde mas sem colecao: arquivo ~/.local/share/keyrings/login.keyring sumiu ou daemon anterior a ele - retorno: {}) - restaure um backup *.bak* para login.keyring (com cp, sem apagar o backup) e rode de novo", uk2.probe));
            return Err(InstallError::KeyringAbsent);
        } else if uk2.state == vault::ProbeState::Error {
            rep.fail(format!("Sonda do cofre falhou (nao e 'trancado': D-Bus/sessao?) - retorno: {} - unlock disse: {} - tente 'wsl --shutdown' e rode de novo", uk2.probe, uk2.unlock_text));
            return Err(InstallError::KeyringLocked);
        } else {
            // Teste de controle: senha GARANTIDAMENTE errada. Rejeitada
            // (!= 0) = exits significativos = senha incorreta de verdade.
            let ctl = vault::unlock_and_probe_live(
                Some(&distro),
                &linux_user,
                vault::FALSE_PROBE_PASSWORD,
                &uid,
            )?;
            if ctl.unlock_code != 0 {
                rep.fail(format!("Senha incorreta para o cofre existente (teste de controle com senha falsa foi rejeitado; unlock disse: {}) - No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo com UMA senha definitiva (nunca rm: sem o arquivo nada funciona)", uk2.unlock_text));
                return Err(InstallError::KeyringLocked);
            }
            rep.warn("Senha nao confere para o cofre existente (unlock por stdin nao valida nada aqui: senha falsa tambem sai 0) - recriando o cofre com a senha informada (backup automatico, original preservado)");
            let (recreated, backup) = vault::reset_login_keyring_live(
                Some(&distro),
                &linux_user,
                &pwq,
                &uid,
                &d.keyring_path,
            )?;
            if !recreated {
                rep.fail(format!("Recriacao falhou de forma inesperada e o original foi restaurado de {backup} - destrave uma vez via Senhas e chaves (seahorse), mantenha ABERTO e rode de novo"));
                return Err(InstallError::KeyringLocked);
            }
            rep.ok(&format!(
                "Cofre recriado com a senha informada (original em {backup})"
            ));
            let (restored_state, _) =
                vault::probe_state_live(Some(&distro), &linux_user, &uid)?;
            if restored_state == vault::ProbeState::Unlocked {
                rep.ok("Cofre destravou apos recriar (via --login)");
            } else {
                let uk3 =
                    vault::unlock_and_probe_live(Some(&distro), &linux_user, &pwq, &uid)?;
                if uk3.state == vault::ProbeState::Unlocked {
                    rep.ok("Cofre destravou apos recriar");
                } else {
                    rep.fail(format!("Cofre recriado mas segue trancado (sonda: {} - unlock disse: {}) - tente 'wsl --shutdown' e rode de novo", uk3.probe, uk3.unlock_text));
                    return Err(InstallError::KeyringLocked);
                }
            }
        }
    }
    rep.say(&format!(
        "  Gravando credencial RDP no cofre (pode levar ate ~{}s por tentativa, nao feche)...",
        d.cred_timeout_sec
    ));
    let mut stored = false;
    let mut last_out = String::new();
    for i in 1..=d.cred_retries {
        if stored {
            break;
        }
        print!("  Tentativa {i}/{}...", d.cred_retries);
        let _ = std::io::stdout().flush();
        let start = std::time::Instant::now();
        let gc = vault::set_rdp_credential_live(&linux_user, &pwq, &uid, d.cred_timeout_sec)?;
        stored = vault::test_credential_live(&linux_user, &uid).unwrap_or(false);
        let secs = start.elapsed().as_secs();
        if stored {
            println!(" ok ({secs}s)");
        } else {
            last_out = gc.out.trim().to_string();
            println!(" ainda nao ({secs}s): {last_out}");
        }
    }
    if !stored {
        rep.fail(format!("Credencial RDP nao gravou no cofre (ultima saida: {last_out} - cofre trancado com outra senha? No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo (nunca rm: sem o arquivo nada funciona))"));
        return Err(InstallError::CredentialNotStored);
    }
    rep.ok("Credencial RDP gravada");
    // Pre-voo da porta explicita (medido: 3389 trava no loopback sem
    // listener; com RDP de verdade funciona - mas o padrao segue 3390).
    if opts.rdp_port.is_some() && probe_tcp_port("127.0.0.1", rdp_port, 1500) {
        rep.warn(&format!("Porta {rdp_port} parece ocupada (pode ser instalacao anterior) - tentando mesmo assim; a verificacao final decide"));
    }
    rep.say(&format!(
        "  Aplicando TLS/porta {rdp_port} e reiniciando o servico..."
    ));
    let _ = wsl_cmd::invoke_wsl(
        Some(&distro),
        &linux_user,
        &rdp_apply_command(&d.tls_cert_path, &d.tls_key_path, rdp_port, &d.rdp_service),
    )?;
    std::thread::sleep(Duration::from_secs(d.rdp_settle_sec));
    if health::test_rdp_listening(&linux_user, &d.rdp_service, rdp_port).unwrap_or(false) {
        rep.ok(&format!("RDP ouvindo na porta {rdp_port}"));
    } else {
        rep.fail("RDP nao subiu".to_string());
        return Err(InstallError::RdpDown);
    }

    // ---- 6. icone + atalhos ----------------------------------------------------------
    rep.step(&format!("6/7 Icone e atalhos ({app_name})"));
    let icons_dir = PathBuf::from(std::env::var("USERPROFILE").unwrap_or_default()).join("Icons");
    let _ = std::fs::create_dir_all(&icons_dir);
    let _ = std::fs::create_dir_all(&prog_dir);
    let ico_path = icons_dir.join(ICON_FILE);
    if !ico_path.exists() {
        let w_ico = windows_path_to_wsl(&ico_path.to_string_lossy());
        let sizes = icon_sizes_arg(&d.icon_sizes);
        let r = wsl_cmd::invoke_wsl(
            Some(&distro),
            &linux_user,
            &icon_build_command(&d.icon_url, &w_ico, &sizes),
        )?;
        if ico_path.exists() {
            rep.ok("Icone Ubuntu baixado e convertido");
        } else {
            rep.warn(&format!(
                "Icone oficial falhou, usando o do mstsc ({})",
                r.out
            ));
        }
    } else {
        rep.ok("Icone ja existia");
    }
    let pub_cert_tp = cert::ensure_publisher_certificate(&d.publisher_subject, d.cert_years)?;
    let localhost_live = if use_mirrored {
        std::net::TcpStream::connect_timeout(
            &format!("127.0.0.1:{rdp_port}")
                .parse()
                .unwrap_or(std::net::SocketAddr::from(([127, 0, 0, 1], rdp_port))),
            Duration::from_secs(2),
        )
        .is_ok()
    } else {
        false
    };
    let (disc_block, rewrite_block, endpoint_note) = if localhost_live {
        rdp_host = "127.0.0.1".to_string();
        rep.ok("RDP responde em localhost (endpoint fixo)");
        (
            launcher::discovery_block_fixed(),
            launcher::rewrite_block_fixed(),
            "",
        )
    } else if use_mirrored {
        rep.ok("RDP via IP dinamico por enquanto (localhost ainda nao vale; rerun fixa)");
        (
            launcher::discovery_block_dynamic(),
            launcher::rewrite_block_dynamic(),
            "",
        )
    } else {
        rep.ok("RDP via IP dinamico (cada clique detecta sozinho)");
        (
            launcher::discovery_block_dynamic(),
            launcher::rewrite_block_dynamic(),
            "",
        )
    };
    let _ = endpoint_note;
    let cmd_path = prog_dir.join(format!("{app_name}.cmd"));
    let cmd_text = launcher::new_launcher_content(
        &app_name,
        &distro,
        &linux_user,
        rdp_port,
        &pub_cert_tp,
        &disc_block,
        &rewrite_block,
    );
    std::fs::write(&cmd_path, cmd_text)?;
    rep.ok(&format!("Script em {}", cmd_path.display()));

    let rdp_path = prog_dir.join(format!("{app_name}.rdp"));
    let hex = rdp::protect_password_hex(linux_pass.expose())?;
    if !localhost_live {
        rdp_host = ip::get_wsl_ip_address(&distro)?.unwrap_or(rdp_host);
    }
    let rdp_lines = rdp::new_rdp_file_content(&rdp_host, rdp_port, &linux_user, &hex, &res);
    std::fs::write(&rdp_path, format!("{}\n", rdp_lines.join("\n")))?;
    if rdp_path.exists() {
        rep.ok(&format!(
            "RDP com login automatico em {}",
            rdp_path.display()
        ));
    } else {
        rep.fail("Arquivo .rdp nao criado".to_string());
        return Err(InstallError::RdpNotCreated);
    }
    if rdp::sign_rdp_file(&rdp_path, &pub_cert_tp) {
        rep.ok("RDP assinado (sem aviso de fornecedor)");
    } else {
        rep.warn("Assinatura do .rdp falhou - o aviso de fornecedor pode continuar");
    }
    let ico_spec = if ico_path.exists() {
        format!("{},0", ico_path.display())
    } else {
        r"C:\Windows\System32\mstsc.exe,0".to_string()
    };
    let desktop = PathBuf::from(std::env::var("USERPROFILE").unwrap_or_default())
        .join("Desktop")
        .join(format!("{app_name}.lnk"));
    let start = PathBuf::from(std::env::var("APPDATA").unwrap_or_default())
        .join(r"Microsoft\Windows\Start Menu\Programs")
        .join(format!("{app_name}.lnk"));
    let mut links_ok = true;
    for lnk in [&desktop, &start] {
        if let Err(e) = write_shortcut(&cmd_path, &prog_dir, &ico_spec, lnk) {
            rep.warn(&format!("atalho {}: {e}", lnk.display()));
            links_ok = false;
        }
    }
    if desktop.exists() && start.exists() && links_ok {
        rep.ok("Atalhos no Desktop e no Iniciar");
    } else {
        rep.fail("Atalhos nao criados".to_string());
        return Err(InstallError::ShortcutsMissing);
    }

    // ---- 7. verificacao ----------------------------------------------------------
    rep.step("7/7 Verificacao ponta a ponta");
    for t in verify_checks(&d.shell_service, &d.rdp_service, rdp_port) {
        let r = wsl_cmd::invoke_wsl(Some(&distro), &linux_user, &t.command)?;
        if check_output_matches(&r.out, &t.want) {
            rep.ok(&t.name);
        } else {
            rep.fail(format!("{} (ret: {})", t.name, r.out.trim()));
        }
    }
    if rdp_path.exists() {
        rep.ok("Login automatico pronto (abre direto, sem senha)");
    } else {
        rep.fail("Arquivo .rdp sumiu".to_string());
        return Err(InstallError::RdpVanished);
    }

    rep.say("");
    let state = feedback::FeedbackState::new();
    let mut live = state;
    for f in rep.failures() {
        live = live.with_failure(f.clone());
    }
    let failures = live.failures();
    if failures.is_empty() {
        if let Some(log) = opts.transcript.as_ref() {
            let _ = std::fs::remove_file(log);
        }
        let _ = resume::clear_run_once();
        let _ = std::fs::remove_file(&resume_file);
        let _ = std::fs::remove_file(&resume_ps1);
        let mut ip = ip::get_wsl_ip_address(&distro)?.unwrap_or_default();
        if localhost_live {
            ip = "127.0.0.1".to_string();
        }
        rep.say("TUDO PRONTO");
        rep.say(&format!(
            "  Desktop : duplo clique em {app_name} (ou mstsc em {ip}:{rdp_port})"
        ));
        rep.say("  Login RDP : automatico (usuario e senha salvos no .rdp)");
        rep.say(&format!("  Resolucao do desktop: {res}"));
        if wsl_restart_needed {
            rep.say("  REINICIE o Windows (ou rode 'wsl --shutdown') p/ valer o mirrored");
        }
        Ok(InstallOutcome::Done)
    } else {
        rep.say("TERMINOU COM FALHAS:");
        for f in failures {
            rep.say(&format!("  - {f}"));
        }
        rep.say("Rode de novo (retoma sozinho) ou veja o log (tem a senha dentro - apague depois)");
        Err(InstallError::FinishedWithFailures)
    }

    #[allow(dead_code)]
    fn unreachable_marker() {}
}

/// Resolucao do monitor primario (Windows; `None` = usar fallback).
#[cfg(windows)]
fn primary_monitor_resolution() -> Option<(u32, u32)> {
    // Via GetSystemMetrics (sem WinForms): SM_CXSCREEN=0, SM_CYSCREEN=1.
    use windows::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN};
    unsafe {
        let w = GetSystemMetrics(SM_CXSCREEN);
        let h = GetSystemMetrics(SM_CYSCREEN);
        if w > 0 && h > 0 {
            Some((w as u32, h as u32))
        } else {
            None
        }
    }
}

/// Escreve stdin (`$block | wsl ... --exec bash -c "cat >> ~/.bashrc"`).
#[cfg(windows)]
fn wsl_append_stdin(distro: &str, linux_user: &str, block: &str) -> Result<(), InstallError> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("wsl")
        .args([
            "-d",
            distro,
            "-u",
            linux_user,
            "--exec",
            "bash",
            "-c",
            "cat >> ~/.bashrc",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(block.as_bytes());
    }
    let _ = child.wait()?;
    Ok(())
}

/// Escreve a unit systemd via stdin.
#[cfg(windows)]
fn wsl_write_stdin(
    distro: &str,
    linux_user: &str,
    remote_cmd: &str,
    content: &str,
) -> Result<(), InstallError> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new("wsl")
        .args([
            "-d", distro, "-u", linux_user, "--exec", "bash", "-c", remote_cmd,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(content.as_bytes());
    }
    let _ = child.wait()?;
    Ok(())
}

/// Atalho `.lnk` via mslnk (puro, testavel no Linux); placement no Desktop +
/// Iniciar (pastas Windows, `cfg(windows)`).
#[cfg(windows)]
fn write_shortcut(
    cmd_path: &std::path::Path,
    work_dir: &std::path::Path,
    ico_spec: &str,
    lnk_path: &std::path::Path,
) -> Result<(), InstallError> {
    use mslnk::ShellLink;

    let mut sl =
        ShellLink::new(cmd_path).map_err(|e| InstallError::Io(format!("lnk target: {e}")))?;
    sl.set_working_dir(Some(work_dir.to_string_lossy().into_owned()));
    sl.set_icon_location(Some(ico_spec.to_string()));
    sl.set_name(Some(
        "Abre o desktop GNOME do Ubuntu (WSL) via RDP".to_string(),
    ));
    sl.header_mut()
        .set_show_command(mslnk::ShowCommand::ShowMinNoActive);
    sl.create_lnk(lnk_path)
        .map_err(|e| InstallError::Io(format!("lnk write: {e}")))?;
    Ok(())
}

/// Descricao padrao dos atalhos (espelha `$s.Description` do `WScript.Shell`).
pub const SHORTCUT_DESCRIPTION: &str = "Abre o desktop GNOME do Ubuntu (WSL) via RDP";

/// Construtor de atalho (mesmos campos nas duas plataformas):
/// - Windows: via `mslnk` (link completo com IDList, como o `WScript.Shell`);
/// - Linux/testes: via [`crate::shortcut`] (`.lnk` estruturalmente valido,
///   header + LinkInfo + StringData + ShowCommand 7).
#[cfg(windows)]
pub fn build_shortcut_file(
    target: &std::path::Path,
    work_dir: &std::path::Path,
    ico_spec: &str,
    lnk_path: &std::path::Path,
) -> Result<(), InstallError> {
    let mut sl =
        mslnk::ShellLink::new(target).map_err(|e| InstallError::Io(format!("lnk target: {e}")))?;
    sl.set_working_dir(Some(work_dir.to_string_lossy().into_owned()));
    sl.set_icon_location(Some(ico_spec.to_string()));
    sl.set_name(Some(SHORTCUT_DESCRIPTION.to_string()));
    sl.header_mut()
        .set_show_command(mslnk::ShowCommand::ShowMinNoActive);
    sl.create_lnk(lnk_path)
        .map_err(|e| InstallError::Io(format!("lnk write: {e}")))?;
    Ok(())
}

#[cfg(not(windows))]
pub fn build_shortcut_file(
    target: &std::path::Path,
    work_dir: &std::path::Path,
    ico_spec: &str,
    lnk_path: &std::path::Path,
) -> Result<(), InstallError> {
    crate::shortcut::write_lnk_file(
        lnk_path,
        &crate::shortcut::ShortcutSpec::new(
            target.to_string_lossy(),
            work_dir.to_string_lossy(),
            ico_spec,
            SHORTCUT_DESCRIPTION,
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolution_gate() {
        assert!(is_valid_resolution("1600x900"));
        assert!(!is_valid_resolution("abc"));
        assert!(!is_valid_resolution("1600x"));
        assert!(!is_valid_resolution("1600"));
    }

    #[test]
    fn reboot_answer_defaults_yes() {
        assert!(wants_reboot_now(""));
        assert!(wants_reboot_now("  "));
        assert!(wants_reboot_now("S"));
        assert!(wants_reboot_now("sim"));
        assert!(!wants_reboot_now("n"));
        assert!(!wants_reboot_now("Nao"));
    }

    #[test]
    fn wslconfig_adds_mirrored_once() {
        let (txt, changed) = ensure_wslconfig_mirrored("");
        assert!(changed);
        assert!(txt.contains("[wsl2]"));
        assert!(txt.contains("networkingMode=mirrored"));
        let (txt2, changed2) = ensure_wslconfig_mirrored(&txt);
        assert!(!changed2);
        assert_eq!(txt2, txt);
    }

    #[test]
    fn wslconfig_keeps_existing_key() {
        let (txt, changed) = ensure_wslconfig_mirrored("[wsl2]\r\nnetworkingMode=nat\r\n");
        assert!(!changed);
        assert!(txt.contains("networkingMode=nat"));
    }

    #[test]
    fn user_commands_shape() {
        assert_eq!(
            user_exists_command("daniel"),
            "id -u daniel 2>/dev/null || echo MISSING"
        );
        assert!(create_user_command("daniel", "pw").contains("useradd -m -s /bin/bash 'daniel'"));
        assert!(create_user_command("daniel", "pw").contains("usermod -aG sudo 'daniel'"));
        assert_eq!(
            update_password_command("daniel", "pw"),
            "echo 'daniel:pw' | chpasswd"
        );
    }

    #[test]
    fn wsl_conf_commands() {
        assert!(wsl_conf_check_command("daniel").contains("default=daniel"));
        assert!(wsl_conf_write_command("daniel").contains("systemd=true"));
    }

    #[test]
    fn systemd_parser() {
        assert!(is_systemd_running("running"));
        assert!(is_systemd_running("degraded"));
        assert!(!is_systemd_running("stopped"));
    }

    #[test]
    fn apt_commands_use_env_prefix() {
        assert!(apt_update_command("pw").starts_with(
            "printf '%s\\n' 'pw' | sudo -S env DEBIAN_FRONTEND=noninteractive apt-get update"
        ));
        assert!(apt_install_command("ubuntu-desktop-minimal", "pw")
            .contains("gnome-remote-desktop openssl python3-pil curl"));
    }

    #[test]
    fn shell_unit_and_probe() {
        let unit = shell_unit_content("gnome-shell", "1600x900", 3);
        assert!(unit.contains("ExecStart=/usr/bin/gnome-shell --mode=ubuntu --wayland --headless --no-x11 --virtual-monitor 1600x900"));
        assert!(unit.contains("RestartSec=3"));
        assert!(unit.contains("WantedBy=default.target"));
        assert_eq!(
            shell_unit_path("gnome-shell-headless.service"),
            "~/.config/systemd/user/gnome-shell-headless.service"
        );
        assert!(shell_current_command("gnome-shell", "1600x900")
            .contains("pgrep -af 'gnome-shell.*--virtual-monitor 1600x900'"));
    }

    #[test]
    fn tls_commands() {
        assert!(tls_cert_create_command("c", "k", 825).contains("-days 825"));
        assert!(tls_cert_create_command("c", "k", 825).contains("-subj '/CN=ubuntu-wsl'"));
        assert_eq!(
            tls_cert_check_command("c"),
            "test -f c && echo OK || echo MISSING"
        );
    }

    #[test]
    fn wsl_install_skips_oobe_with_no_launch() {
        assert_eq!(
            wsl_install_argv("Ubuntu"),
            vec!["wsl", "--install", "-d", "Ubuntu", "--no-launch"]
                .into_iter()
                .map(String::from)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn password_retry_allows_three_attempts() {
        assert_eq!(PASSWORD_MAX_ATTEMPTS, 3);
    }

    #[test]
    fn tcp_probe_sees_live_listener() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        assert!(probe_tcp_port("127.0.0.1", port, 1000));
    }

    #[test]
    fn tcp_probe_reports_free_port() {
        let port = {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            listener.local_addr().unwrap().port()
        };
        assert!(!probe_tcp_port("127.0.0.1", port, 500));
    }

    #[test]
    fn rdp_apply_pins_port_and_tls() {
        let cmd = rdp_apply_command("c", "k", 3390, "gnome-remote-desktop");
        assert!(cmd.contains("grdctl rdp set-port 3390"));
        assert!(cmd.contains("disable-view-only"));
        assert!(cmd.contains("systemctl --user restart gnome-remote-desktop"));
    }

    #[test]
    fn windows_path_conversion() {
        assert_eq!(
            windows_path_to_wsl("C:\\Users\\x\\ubuntu.ico"),
            "/mnt/c/Users/x/ubuntu.ico"
        );
        assert_eq!(windows_path_to_wsl("D:\\a"), "/mnt/d/a");
    }

    #[test]
    fn icon_sizes_arg_shape() {
        assert_eq!(icon_sizes_arg(&[16, 32]), "(16 ,16),(32 ,32)");
    }

    #[test]
    fn verify_checks_matchers() {
        let checks = verify_checks("gnome-shell-headless.service", "gnome-remote-desktop", 3390);
        assert_eq!(checks.len(), 3);
        assert_eq!(checks[0].want, "^active$");
        assert!(checks[1].command.contains("ubuntu-dock"));
        assert!(check_output_matches("active", "^active$"));
        assert!(!check_output_matches("inactive", "^active$"));
        assert!(check_output_matches("xxOK", "OK"));
    }

    #[test]
    fn ver_build_parser() {
        assert_eq!(
            parse_windows_build("Microsoft Windows [Version 10.0.22621.1]"),
            Some(22621)
        );
        assert_eq!(parse_windows_build("sem versao"), None);
    }

    #[test]
    fn shutdown_command_shape() {
        assert!(shutdown_reboot_command(30).starts_with("shutdown /r /t 30"));
    }

    #[test]
    fn shortcut_file_builds_valid_lnk() {
        let dir = std::env::temp_dir().join(format!("ubuntu-gui-lnk-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let lnk = dir.join("Ubuntu-GUI.lnk");
        build_shortcut_file(
            std::path::Path::new(r"C:\App\Ubuntu-GUI.cmd"),
            std::path::Path::new(r"C:\App"),
            r"C:\Icons\ubuntu.ico,0",
            &lnk,
        )
        .unwrap();
        let bytes = std::fs::read(&lnk).unwrap();
        // Assinatura MS-SHLLINK: header size 0x4C + GUID LinkCLSID.
        assert!(bytes.len() > 76);
        assert_eq!(&bytes[0..4], &[0x4C, 0x00, 0x00, 0x00]);
        assert_eq!(
            &bytes[4..20],
            &[
                0x01, 0x14, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x46
            ]
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn bashrc_block_has_marker_and_idempotent_check() {
        assert!(BASHRC_BLOCK.contains(BASHRC_MARKER));
        assert!(BASHRC_BLOCK.contains("wayland-0"));
        assert_eq!(
            bashrc_check_command(),
            format!("grep -q '{BASHRC_MARKER}' ~/.bashrc && echo OK || echo MISSING")
        );
    }
}
