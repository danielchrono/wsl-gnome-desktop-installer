//! Sondas de saude do desktop (`Test-WslServiceHealth.ps1`, SSOT).
//!
//! O mesmo texto de comando no Install (etapas 5 e 7) e no Status.
//! Fronteira de I/O: `Get-*` montam o comando (puros, testaveis sem WSL);
//! `is_*` decidem Ok/Fail (chamadores decidem mensagem/throw).

use crate::error::InstallError;
use crate::wsl_cmd;

/// `Get-WslShellActiveCommand`.
pub fn shell_active_command(service: &str) -> String {
    format!("systemctl --user is-active {service}")
}

/// `Get-WslRdpListeningCommand`.
pub fn rdp_listening_command(service: &str, port: u16) -> String {
    format!(
        "systemctl --user is-active {service} && ss -tlnp 2>/dev/null | grep -q ':{port}' && echo OK || echo DOWN"
    )
}

/// Parser de `Test-WslShellActive`: exige `active` exato apos trim
/// (`inactive` nao passa).
pub fn is_shell_active(out: &str) -> bool {
    out.trim() == "active"
}

/// Parser de `Test-WslRdpListening`: `-match 'OK'` (substring).
pub fn is_rdp_listening(out: &str) -> bool {
    out.contains("OK")
}

/// `Test-WslShellActive` (executa via `Invoke-Wsl`; `cfg(windows)`).
pub fn test_shell_active(linux_user: &str, service: &str) -> Result<bool, InstallError> {
    let r = wsl_cmd::invoke_wsl(None, linux_user, &shell_active_command(service))?;
    Ok(is_shell_active(&r.out))
}

/// `Test-WslRdpListening` (executa via `Invoke-Wsl`; `cfg(windows)`).
pub fn test_rdp_listening(
    linux_user: &str,
    service: &str,
    port: u16,
) -> Result<bool, InstallError> {
    let r = wsl_cmd::invoke_wsl(None, linux_user, &rdp_listening_command(service, port))?;
    Ok(is_rdp_listening(&r.out))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shell_command_is_exact() {
        assert_eq!(
            shell_active_command("s.svc"),
            "systemctl --user is-active s.svc"
        );
    }

    #[test]
    fn rdp_command_carries_service_and_port() {
        assert_eq!(
            rdp_listening_command("r.svc", 3390),
            "systemctl --user is-active r.svc && ss -tlnp 2>/dev/null | grep -q ':3390' && echo OK || echo DOWN"
        );
    }

    #[test]
    fn shell_requires_exact_active() {
        assert!(is_shell_active("active"));
        assert!(is_shell_active("  active\n"));
        assert!(!is_shell_active("inactive"));
        assert!(!is_shell_active("activating"));
        assert!(!is_shell_active(""));
    }

    #[test]
    fn rdp_requires_ok() {
        assert!(is_rdp_listening("OK"));
        assert!(!is_rdp_listening("DOWN"));
        assert!(!is_rdp_listening(""));
    }
}
