//! Port Rust do modulo PowerShell `UbuntuGui`.
//!
//! Mapeamento PowerShell -> Rust (1:1 por funcao pura):
//!
//! - `UbuntuGui-Constants.ps1` -> [`constants`]
//! - `Write-Feedback.ps1` -> [`feedback`]
//! - `Invoke-WslCommand.ps1` -> [`wsl_cmd`]
//! - `Invoke-VaultCredential.ps1` -> [`vault`]
//! - `Get-PasswordQuote.ps1` -> [`passquote`]
//! - `ConvertFrom-SecureStringPlain.ps1` -> [`secure`]
//! - `ConvertFrom-WslDistroList.ps1` -> [`distro_list`]
//! - `Get-FirstIpAddress.ps1` + `Get-WslIpAddress.ps1` -> [`ip`]
//! - `Test-WslServiceHealth.ps1` -> [`health`]
//! - `Test-InstallInput.ps1` -> [`input`]
//! - `Show-TuiMenu.ps1` -> [`tui`]
//! - `New-RdpFileContent.ps1` -> [`rdp`]
//! - `New-LauncherContent.ps1` -> [`launcher`]
//! - `Save-ResumeState.ps1` -> [`resume`]
//! - `New-PublisherCertificate.ps1` -> [`cert`]
//! - `Install-WslUbuntuGui.ps1` (etapas S0-S7) -> [`install`]
//! - `Get-WslUbuntuGuiStatus.ps1` -> [`status`]
//! - `entry-head/tail.ps1` + `header/footer.cmdpart` -> binario em `src/main.rs`
//!
//! Logica pura compila e testa em qualquer SO (inclusive Linux `--offline`).
//! Execucao Windows/WSL (wsl.exe, DPAPI, cert store, RunOnce, rdpsign,
//! transcript em TEMP) vive atras de `cfg(windows)` com as mesmas mensagens,
//! comandos e exit codes do PowerShell.

pub mod cert;
pub mod constants;
pub mod distro_list;
pub mod error;
pub mod feedback;
pub mod health;
pub mod input;
pub mod install;
pub mod ip;
pub mod launcher;
pub mod passquote;
pub mod rdp;
pub mod resume;
pub mod secure;
pub mod shortcut;
pub mod status;
pub mod tui;
pub mod vault;
pub mod wsl_cmd;

/// Versao do instalador (espelha `$SCRIPT_VERSION = "0.1.0"` + `UbuntuGui.psd1`).
pub const SCRIPT_VERSION: &str = "0.1.0";

/// Sentinela impressa quando a etapa 1 precisa de reboot: o processo sai com
/// codigo 0 (bare `return` no PowerShell) e o RunOnce ja foi escrito, entao o
/// chamador distingue "ok, vai voltar sozinho" de "TUDO PRONTO".
pub const REBOOT_SENTINEL: &str = "REBOOT_REQUIRED";
