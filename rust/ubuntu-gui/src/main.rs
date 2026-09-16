//! Binario `ubuntu-gui`: substitui `entry-head/tail.ps1` + `header/footer.cmdpart`.
//!
//! - head (`param([switch]$Resume)` + `SCRIPT_VERSION` + transcript em TEMP)
//!   vira args clap [`Args`] (`--resume <state.json>`, `--transcript`,
//!   `--no-transcript`);
//! - tail (`exit 0` / `FALHA: ...` + `exit 1`) vira [`main`] com os mesmos
//!   textos e codigos;
//! - header/footer `.cmdpart` (extrai PS1 para TEMP e executa) somem: o
//!   instalador agora e um `.exe` unico (`cargo build --release` e
//!   `cargo build --release --target x86_64-pc-windows-msvc`).

use std::path::PathBuf;

use clap::{Parser, Subcommand};
use ubuntu_gui::{REBOOT_SENTINEL, SCRIPT_VERSION};

/// Instalador Ubuntu-GUI (port do `Install-WslUbuntuGui` + head/tail).
#[derive(Debug, Parser)]
#[command(name = "ubuntu-gui", version = SCRIPT_VERSION, about = "Instala o Ubuntu no WSL2 com desktop GNOME completo via RDP.")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Usuario Linux (pergunta se omitido; salvo entre runs).
    #[arg(long)]
    linux_user: Option<String>,

    /// Senha do usuario Linux (pede 2x com mascara se omitida).
    #[arg(long)]
    linux_password: Option<String>,

    /// Modo de rede: 1 = localhost fixo 127.0.0.1 (padrao), 2 = IP dinamico.
    #[arg(long)]
    net_choice: Option<String>,

    /// Retoma sozinho apos o reboot a partir do estado (`resume-state.json`).
    /// Substitui o `-Resume` do head + RunOnce `AfterReboot`.
    #[arg(long, value_name = "STATE_JSON")]
    resume: Option<PathBuf>,

    /// Distro WSL (padrao centralizado).
    #[arg(long)]
    distro: Option<String>,

    /// Pacote GUI (padrao centralizado).
    #[arg(long)]
    gui_package: Option<String>,

    /// Resolucao de fallback `WxH` (padrao centralizado).
    #[arg(long)]
    fallback_res: Option<String>,

    /// Porta RDP (padrao: 3390, longe da 3389 do host; se ocupada, cai para 3391 via net::choose_rdp_port).
    /// Se informada explicitamente, substitui a selecao automatica.
    #[arg(long)]
    rdp_port: Option<u16>,

    /// Nome do app/atalhos (padrao centralizado).
    #[arg(long)]
    app_name: Option<String>,

    /// Desliga a TUI (cai para prompts numericos/simples).
    #[arg(long)]
    no_tui: bool,

    /// Roda sem parar em nada: exige --linux-user e --linux-password, rede
    /// cai no padrao (ou --net-choice), reboot sozinho quando preciso.
    #[arg(long)]
    unattended: bool,

    /// Arquivo de transcript (padrao: TEMP/Ubuntu-GUI-install.log).
    #[arg(long)]
    transcript: Option<PathBuf>,

    /// Nao grava transcript.
    #[arg(long, conflicts_with = "transcript")]
    no_transcript: bool,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Le o estado do desktop (somente leitura; port de Get-WslUbuntuGuiStatus).
    Status {
        /// Usuario Linux (obrigatorio, como no PS).
        #[arg(long)]
        linux_user: String,
        /// Distro WSL (padrao centralizado).
        #[arg(long)]
        distro: Option<String>,
        /// Porta RDP (padrao centralizado).
        #[arg(long)]
        rdp_port: Option<u16>,
    },
}

/// Caminho padrao do transcript (TEMP no Windows, /tmp fora).
fn default_transcript_path() -> PathBuf {
    #[cfg(windows)]
    {
        PathBuf::from(std::env::var("TEMP").unwrap_or_else(|_| r"C:\Temp".to_string()))
            .join(ubuntu_gui::install::LOG_FILE_NAME)
    }
    #[cfg(not(windows))]
    {
        PathBuf::from("/tmp").join(ubuntu_gui::install::LOG_FILE_NAME)
    }
}

fn main() {
    let cli = Cli::parse();

    if let Some(Commands::Status {
        linux_user,
        distro,
        rdp_port,
    }) = cli.command
    {
        match ubuntu_gui::status::get_status(distro.as_deref(), &linux_user, rdp_port) {
            Ok(st) => {
                println!("{}", st.summary());
                std::process::exit(if st.healthy() { 0 } else { 1 });
            }
            Err(e) => {
                eprintln!("FALHA: {e}");
                std::process::exit(1);
            }
        }
    }

    let transcript = if cli.no_transcript {
        None
    } else {
        Some(cli.transcript.unwrap_or_else(default_transcript_path))
    };

    let opts = ubuntu_gui::install::InstallOptions {
        linux_user: cli.linux_user,
        linux_password: cli.linux_password,
        net_choice: cli.net_choice,
        resume_file: cli.resume,
        distro: cli.distro,
        gui_package: cli.gui_package,
        fallback_resolution: cli.fallback_res,
        rdp_port: cli.rdp_port,
        app_name: cli.app_name,
        no_tui: cli.no_tui,
        unattended: cli.unattended,
        transcript,
    };

    // tail: `exit 0` no sucesso; etapa 1 com reboot sai 0 + sentinela
    // (RunOnce ja escrito); `FALHA: <msg>` + `exit 1` no erro.
    // A trava segura o console em TODAS as saidas do install (sem ela a
    // janela fecha sozinha e o log voa); `status` nao trava (saida legivel
    // por maquina, pode estar num script com TTY).
    match ubuntu_gui::install::run_install(&opts) {
        Ok(ubuntu_gui::install::InstallOutcome::Done) => exit_install(0, opts.unattended),
        Ok(ubuntu_gui::install::InstallOutcome::RebootRequired) => {
            println!("{REBOOT_SENTINEL}");
            exit_install(0, opts.unattended);
        }
        Err(e) => {
            eprintln!("FALHA: {e}");
            exit_install(1, opts.unattended);
        }
    }
}

/// Saida do install com trava "pressione qualquer tecla" quando ha terminal
/// interativo (nunca no `--unattended`: automacao nao pode parar).
fn exit_install(code: i32, unattended: bool) -> ! {
    use std::io::IsTerminal;
    if ubuntu_gui::tui::should_hold_console(unattended, std::io::stdin().is_terminal()) {
        ubuntu_gui::tui::hold_console();
    }
    std::process::exit(code);
}
