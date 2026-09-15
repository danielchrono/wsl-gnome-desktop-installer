//! Monta o launcher `.cmd` (`New-LauncherContent.ps1`).
//!
//! Placeholders `_VAL` trocados aqui; assinatura preservada no fixo.
//! Ordem de troca do PowerShell: `APP_NAME`, `DISTRO_VAL`, `LINUXUSER_VAL`,
//! `RDPREWRITE_VAL`, `RDP_PORT_VAL`, `THUMBPRINT_VAL`, `SHELLSVC_VAL`,
//! `RDPSVC_VAL`, `IPDISCOVERY_VAL`.

use crate::constants::defaults;

/// Template byte-identico ao here-string do PowerShell (LF; comeca e termina
/// com `\n` como o bloco `@'...'@`).
pub const LAUNCHER_TEMPLATE: &str = "\n@echo off\nrem APP_NAME - liga o WSL, garante desktop+RDP e abre o mstsc\nsetlocal\nset DISTRO=DISTRO_VAL\nset WSL=C:\\Windows\\System32\\wsl.exe\nset MSTSC=C:\\Windows\\System32\\mstsc.exe\nset RDPPATH=%LOCALAPPDATA%\\Programs\\APP_NAME\\APP_NAME.rdp\nset WSL_IP=127.0.0.1\nIPDISCOVERY_VAL\nif \"%WSL_IP%\"==\"\" (\n  echo Nao foi possivel iniciar o Ubuntu no WSL.\n  pause\n  exit /b 1\n)\n%WSL% -d %DISTRO% -u LINUXUSER_VAL --exec env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start SHELLSVC_VAL RDPSVC_VAL.service >nul 2>&1\nRDPREWRITE_VAL\nstart \"APP_NAME\" \"%MSTSC%\" \"%RDPPATH%\"\n";

/// Bloco de descoberta quando o localhost ja vale (mirrored + RDP de pe).
pub fn discovery_block_fixed() -> String {
    "rem IP fixo via mirrored networking (127.0.0.1)".to_string()
}

/// Bloco de descoberta dinamica: cada clique detecta sozinho via `hostname -I`.
pub fn discovery_block_dynamic() -> String {
    "rem IP descoberto automaticamente a cada clique (hostname -I)\r\nfor /f \"tokens=1\" %%i in ('%WSL% -d %DISTRO% -- hostname -I 2^>nul') do set WSL_IP=%%i".to_string()
}

/// Bloco fixo: nao reescreve o `.rdp` (assinatura continua valida).
pub fn rewrite_block_fixed() -> String {
    "rem IP/porta fixos via mirrored (127.0.0.1:RDP_PORT_VAL) - .rdp assinado, nao alterar"
        .to_string()
}

/// Bloco dinamico: reescreve o `.rdp` + reassina via `rdpsign`.
pub fn rewrite_block_dynamic() -> String {
    "powershell -NoProfile -Command \"(Get-Content '%RDPPATH%') -replace '^full address:s:.*','full address:s:%WSL_IP%:RDP_PORT_VAL' | Set-Content '%RDPPATH%'; & %SystemRoot%\\System32\\rdpsign.exe /sha256 THUMBPRINT_VAL '%RDPPATH%' >nul 2>&1\"".to_string()
}

/// `New-LauncherContent`: troca todos os placeholders, nesta ordem.
#[allow(clippy::too_many_arguments)]
pub fn new_launcher_content(
    app_name: &str,
    distro: &str,
    linux_user: &str,
    rdp_port: u16,
    thumbprint: &str,
    discovery_block: &str,
    rewrite_block: &str,
) -> String {
    let d = defaults();
    LAUNCHER_TEMPLATE
        .replace("APP_NAME", app_name)
        .replace("DISTRO_VAL", distro)
        .replace("LINUXUSER_VAL", linux_user)
        .replace("RDPREWRITE_VAL", rewrite_block)
        .replace("RDP_PORT_VAL", &rdp_port.to_string())
        .replace("THUMBPRINT_VAL", thumbprint)
        .replace("SHELLSVC_VAL", &d.shell_service)
        .replace("RDPSVC_VAL", &d.rdp_service)
        .replace("IPDISCOVERY_VAL", discovery_block)
}

/// Monta o `.cmd` escolhendo os blocos fixo/dinamico pelo probe de localhost.
pub fn launcher_for_endpoint(
    app_name: &str,
    distro: &str,
    linux_user: &str,
    rdp_port: u16,
    thumbprint: &str,
    localhost_live: bool,
) -> String {
    let (disc, rewrite) = if localhost_live {
        (discovery_block_fixed(), rewrite_block_fixed())
    } else {
        (discovery_block_dynamic(), rewrite_block_dynamic())
    };
    new_launcher_content(
        app_name, distro, linux_user, rdp_port, thumbprint, &disc, &rewrite,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> String {
        new_launcher_content(
            "Ubuntu-GUI",
            "Ubuntu",
            "daniel",
            3390,
            "ABC123",
            "rem X",
            "rem Y THUMBPRINT_VAL",
        )
    }

    #[test]
    fn replaces_all_placeholders() {
        let c = sample();
        for token in [
            "DISTRO_VAL",
            "RDP_PORT_VAL",
            "THUMBPRINT_VAL",
            "IPDISCOVERY_VAL",
            "RDPREWRITE_VAL",
            "LINUXUSER_VAL",
            "SHELLSVC_VAL",
            "RDPSVC_VAL",
        ] {
            assert!(!c.contains(token), "sobrou {token}");
        }
    }

    #[test]
    fn embeds_thumbprint_and_user() {
        let c = sample();
        assert!(c.contains("ABC123"));
        assert!(c.contains("daniel"));
    }

    #[test]
    fn fixed_endpoint_preserves_signature() {
        let c = launcher_for_endpoint("Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", true);
        assert!(!c.contains("127.0.0.1:RDP_PORT_VAL"));
        assert!(c.contains("127.0.0.1:3390"));
        assert!(c.contains("nao alterar"));
        assert!(!c.contains("rdpsign"));
        assert!(c.contains("rem IP fixo via mirrored networking (127.0.0.1)"));
    }

    #[test]
    fn dynamic_endpoint_rewrites_and_resigns() {
        let c = launcher_for_endpoint("Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", false);
        assert!(c.contains("full address:s:%WSL_IP%:3390"));
        assert!(c.contains("rdpsign.exe /sha256 ABC123"));
        assert!(c.contains("hostname -I 2^>nul"));
    }
}
