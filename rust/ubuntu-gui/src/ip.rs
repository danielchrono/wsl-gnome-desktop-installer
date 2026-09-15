//! Primeiro IP do WSL (`Get-FirstIpAddress.ps1` + `Get-WslIpAddress.ps1`).
//!
//! `Get-WslIpAddress` e o SSOT do comando (antes copiado 3x no Install):
//! `hostname -I` pode vir com varios IPs + espacos; o parse vive em
//! [`first_ip_address`].

use crate::error::InstallError;
use crate::wsl_cmd;

/// Primeiro IP de `hostname -I` (pode vir com varios + espacos).
///
/// Retorna `None` para entrada vazia/só-espacos (o PowerShell retorna `$null`).
pub fn first_ip_address(hostname_i: &str) -> Option<String> {
    hostname_i.split_whitespace().next().map(|s| s.to_string())
}

/// Comando SSOT lido no WSL para descobrir o IP.
pub fn wsl_ip_command() -> &'static str {
    "hostname -I"
}

/// `Get-WslIpAddress`: roda `wsl -d <distro> -- hostname -I` e extrai o
/// primeiro IP. Execucao real atras de `cfg(windows)` (via [`wsl_cmd`]).
pub fn get_wsl_ip_address(distro: &str) -> Result<Option<String>, InstallError> {
    let out = wsl_cmd::run_wsl_simple(distro, wsl_ip_command())?;
    Ok(first_ip_address(&out))
}

/// Parse puro do stdout de `hostname -I` (testavel sem WSL).
pub fn parse_wsl_ip_output(out: &str) -> Option<String> {
    first_ip_address(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn takes_first_ip() {
        assert_eq!(
            first_ip_address(" 192.168.1.5 10.0.0.2 "),
            Some("192.168.1.5".to_string())
        );
    }

    #[test]
    fn blank_returns_none() {
        assert_eq!(first_ip_address("   "), None);
        assert_eq!(first_ip_address(""), None);
    }

    #[test]
    fn parses_mocked_wsl_output() {
        assert_eq!(
            parse_wsl_ip_output("10.1.2.3 10.1.2.4 "),
            Some("10.1.2.3".to_string())
        );
    }
}
