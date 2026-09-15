//! Le o estado do desktop Ubuntu/WSL (`Get-WslUbuntuGuiStatus.ps1`).
//!
//! Somente leitura, seguro rodar sempre. Padroes centralizados via
//! [`crate::constants::defaults`] (sem `3390`/`Ubuntu` hardcoded).

use crate::error::InstallError;

/// Estado lido (`[pscustomobject]@{ Distro; LinuxUser; RdpPort; ShellActive;
/// RdpListening; CredentialsSet }`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GuiStatus {
    pub distro: String,
    pub linux_user: String,
    pub rdp_port: u16,
    pub shell_active: bool,
    pub rdp_listening: bool,
    pub credentials_set: bool,
}

impl GuiStatus {
    pub fn new(
        distro: &str,
        linux_user: &str,
        rdp_port: u16,
        shell_active: bool,
        rdp_listening: bool,
        credentials_set: bool,
    ) -> Self {
        Self {
            distro: distro.to_string(),
            linux_user: linux_user.to_string(),
            rdp_port,
            shell_active,
            rdp_listening,
            credentials_set,
        }
    }

    /// Resumo de uma linha para o CLI.
    pub fn summary(&self) -> String {
        format!(
            "{}@{} rdp_port={} shell={} rdp={} cred={}",
            self.linux_user,
            self.distro,
            self.rdp_port,
            flag(self.shell_active),
            flag(self.rdp_listening),
            flag(self.credentials_set)
        )
    }

    pub fn healthy(&self) -> bool {
        self.shell_active && self.rdp_listening && self.credentials_set
    }
}

fn flag(b: bool) -> &'static str {
    if b {
        "up"
    } else {
        "down"
    }
}

/// `Get-WslUbuntuGuiStatus`: sondas via helpers unicos (sem duplicar
/// comandos inline). Execucao real `cfg(windows)`; fora, erro tipado.
#[cfg(windows)]
pub fn get_status(
    distro: Option<&str>,
    linux_user: &str,
    rdp_port: Option<u16>,
) -> Result<GuiStatus, InstallError> {
    let d = crate::constants::defaults();
    let distro = distro.unwrap_or(&d.distro);
    let rdp_port = rdp_port.unwrap_or(d.rdp_port);
    let shell_active =
        crate::health::test_shell_active(linux_user, &d.shell_service).unwrap_or(false);
    let rdp_up =
        crate::health::test_rdp_listening(linux_user, &d.rdp_service, rdp_port).unwrap_or(false);
    let uid = crate::wsl_cmd::invoke_wsl(None, linux_user, "id -u")?
        .out
        .trim()
        .to_string();
    let cred_set = crate::vault::test_credential_live(linux_user, &uid).unwrap_or(false);
    Ok(GuiStatus::new(
        distro,
        linux_user,
        rdp_port,
        shell_active,
        rdp_up,
        cred_set,
    ))
}

#[cfg(not(windows))]
pub fn get_status(
    _distro: Option<&str>,
    _linux_user: &str,
    _rdp_port: Option<u16>,
) -> Result<GuiStatus, InstallError> {
    Err(InstallError::NotSupportedOnLinux(
        "Get-WslUbuntuGuiStatus (wsl.exe)",
    ))
}

/// Monta o status a partir das sondas (puro, testavel sem WSL).
pub fn assemble_status(
    distro: Option<&str>,
    linux_user: &str,
    rdp_port: Option<u16>,
    shell_out: &str,
    rdp_out: &str,
    cred_out: &str,
) -> GuiStatus {
    let d = crate::constants::defaults();
    GuiStatus::new(
        distro.unwrap_or(&d.distro),
        linux_user,
        rdp_port.unwrap_or(d.rdp_port),
        crate::health::is_shell_active(shell_out),
        crate::health::is_rdp_listening(rdp_out),
        crate::vault::is_credential_set(cred_out),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_centralized_defaults() {
        let st = assemble_status(None, "daniel", None, "active", "OK", "YES");
        assert_eq!(st.distro, "Ubuntu");
        assert_eq!(st.rdp_port, 3390);
        assert!(st.healthy());
    }

    #[test]
    fn unhealthy_when_any_probe_fails() {
        let st = assemble_status(Some("Debian"), "u", Some(3391), "inactive", "DOWN", "NO");
        assert_eq!(st.distro, "Debian");
        assert_eq!(st.rdp_port, 3391);
        assert!(!st.healthy());
        assert!(st.summary().contains("down"));
    }

    #[test]
    fn summary_shape() {
        let st = assemble_status(None, "daniel", None, "active", "OK", "YES");
        assert_eq!(
            st.summary(),
            "daniel@Ubuntu rdp_port=3390 shell=up rdp=up cred=up"
        );
    }
}
