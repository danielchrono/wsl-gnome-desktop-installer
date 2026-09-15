//! Monta o launcher `.cmd` (`New-LauncherContent.ps1`).
//!
//! Placeholders `_VAL` trocados aqui; assinatura preservada no fixo.
//! Ordem de troca do PowerShell: `APP_NAME`, `DISTRO_VAL`, `LINUXUSER_VAL`,
//! `RDPREWRITE_VAL`, `RDP_PORT_VAL`, `THUMBPRINT_VAL`, `SHELLSVC_VAL`,
//! `RDPSVC_VAL`, `IPDISCOVERY_VAL`.

use crate::constants::defaults;

/// Template byte-identico ao here-string do PowerShell (LF; comeca e termina
/// com `\n` como o bloco `@'...'@`).
/// Abre uma COPIA por clique (`RUNRDP`): o mstsc grava estado de sessao de
/// volta no `.rdp` que abre (ex.: modo de tela), e qualquer byte diferente
/// invalida a assinatura — o original assinado fica intacto para sempre.
/// Preferencia sem arquivo: o helper grava a credencial no Cofre do Windows
/// (`TERMSRV/host`) e o mstsc abre via `/v:` — sem `.rdp` aberto, sem dialogo
/// de fornecedor (paridade com `New-LauncherContent.ps1`; o `.rdp` segue como
/// fallback quando o helper falha).
pub const LAUNCHER_TEMPLATE: &str = "\n@echo off\nrem APP_NAME - liga o WSL, garante desktop+RDP e abre o mstsc\nsetlocal\nset DISTRO=DISTRO_VAL\nset WSL=C:\\Windows\\System32\\wsl.exe\nset MSTSC=C:\\Windows\\System32\\mstsc.exe\nset RDPPATH=%LOCALAPPDATA%\\Programs\\APP_NAME\\APP_NAME.rdp\nset RUNRDP=%TEMP%\\APP_NAME-run.rdp\nset CREDHELPER=%LOCALAPPDATA%\\Programs\\APP_NAME\\APP_NAME-Cred.ps1\nset WSL_IP=127.0.0.1\nIPDISCOVERY_VAL\nif \"%WSL_IP%\"==\"\" (\n  echo Nao foi possivel iniciar o Ubuntu no WSL.\n  pause\n  exit /b 1\n)\n%WSL% -d %DISTRO% -u LINUXUSER_VAL --exec env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start SHELLSVC_VAL RDPSVC_VAL.service >nul 2>&1\ncopy /y \"%RDPPATH%\" \"%RUNRDP%\" >nul\nRDPREWRITE_VAL\npowershell -NoProfile -ExecutionPolicy Bypass -File \"%CREDHELPER%\" \"%RUNRDP%\" \"%WSL_IP%\" RDP_PORT_VAL >nul 2>&1\nif errorlevel 1 (start \"APP_NAME\" \"%MSTSC%\" \"%RUNRDP%\") else (start \"APP_NAME\" %MSTSC% /v:%WSL_IP%:RDP_PORT_VAL /w:RDP_W_VAL /h:RDP_H_VAL)\n";

/// Helper que grava a credencial RDP no Cofre do Windows (paridade com
/// `New-CredHelperContent.ps1`): estatico, sem placeholder — recebe
/// `RdpPath`, `Host` e `Port` por argumento. Fonte: sidecar `-Cred.txt`
/// (o `.rdp` assinado nao serve: o rdpsign deforma a linha longa
/// `password 51:b:` e a extracao quebra; o `.rdp` segue como fallback).
/// Falha nunca e fatal: o launcher volta ao `.rdp`.
pub const CRED_HELPER_SCRIPT: &str = r#"param([string]$RdpPath, [string]$RdpHost, [int]$RdpPort)
try {
  $u = ''; $h = ''
  $sidecar = $PSCommandPath -replace '\.ps1$', '.txt'
  if (Test-Path $sidecar) {
    $sc = [IO.File]::ReadAllLines($sidecar)
    if ($sc.Count -ge 2) { $u = $sc[0].Trim(); $h = $sc[1] -replace '[^0-9a-fA-F]', '' }
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h)) {
    $lines = [IO.File]::ReadAllLines($RdpPath)
    $u = @($lines | Where-Object { $_ -like 'username:s:*' })[0] -replace '^username:s:', ''
    $h = @($lines | Where-Object { $_ -like 'password 51:b:*' })[0] -replace '^password 51:b:', ''
    $u = "$u".Trim()
    $h = "$h" -replace '[^0-9a-fA-F]', ''
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h) -or ($h.Length % 2 -eq 1)) { exit 1 }
  $raw = New-Object byte[] ($h.Length / 2)
  for ($i = 0; $i -lt $h.Length; $i += 2) { $raw[$i / 2] = [Convert]::ToByte($h.Substring($i, 2), 16) }
  Add-Type -AssemblyName System.Security
  $pass = [Text.Encoding]::Unicode.GetString([Security.Cryptography.ProtectedData]::Unprotect($raw, $null, 'CurrentUser'))
  if ([string]::IsNullOrEmpty($pass)) { exit 1 }
  $cs = 'using System; using System.Runtime.InteropServices; public static class CredMan { [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct CREDENTIAL { public UInt32 Flags; public UInt32 Type; [MarshalAs(UnmanagedType.LPWStr)] public string TargetName; [MarshalAs(UnmanagedType.LPWStr)] public string Comment; public UInt64 LastWritten; public UInt32 CredentialBlobSize; public IntPtr CredentialBlob; public UInt32 Persist; public UInt32 AttributeCount; public IntPtr Attributes; [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias; [MarshalAs(UnmanagedType.LPWStr)] public string UserName; } [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CredWriteW")] public static extern bool Write(ref CREDENTIAL cred, UInt32 flags); public static bool Save(string target, string user, string secret) { byte[] b = System.Text.Encoding.Unicode.GetBytes(secret); IntPtr p = Marshal.AllocCoTaskMem(b.Length); Marshal.Copy(b, 0, p, b.Length); CREDENTIAL c = new CREDENTIAL(); c.Flags = 0; c.Type = 1; c.TargetName = target; c.CredentialBlobSize = (UInt32)b.Length; c.CredentialBlob = p; c.Persist = 3; c.UserName = user; bool ok = Write(ref c, 0); Marshal.FreeCoTaskMem(p); return ok; } }'
  Add-Type -TypeDefinition $cs -Language CSharp
  $ok = $true
  foreach ($t in @("TERMSRV/$RdpHost", "TERMSRV/${RdpHost}:$RdpPort")) { if (-not [CredMan]::Save($t, $u, $pass)) { $ok = $false } }
  if (-not $ok) { exit 1 }
} catch { exit 1 }
exit 0
"#;

/// Conteudo do sidecar `-Cred.txt`: usuario na 1a linha, blob DPAPI em hex
/// na 2a (o helper le dai; o `.rdp` assinado deforma a linha longa).
pub fn cred_sidecar_content(linux_user: &str, password_hex: &str) -> String {
    format!("{linux_user}\n{password_hex}\n")
}

/// Bloco de descoberta quando o localhost ja vale (mirrored + RDP de pe).
pub fn discovery_block_fixed() -> String {
    "rem IP fixo via mirrored networking (127.0.0.1)".to_string()
}

/// Bloco de descoberta dinamica: cada clique detecta sozinho via `hostname -I`.
pub fn discovery_block_dynamic() -> String {
    "rem IP descoberto automaticamente a cada clique (hostname -I)\r\nfor /f \"tokens=1\" %%i in ('%WSL% -d %DISTRO% -- hostname -I 2^>nul') do set WSL_IP=%%i".to_string()
}

/// Bloco fixo: nao reescreve a copia (assinatura continua valida).
pub fn rewrite_block_fixed() -> String {
    "rem IP/porta fixos via mirrored (127.0.0.1:RDP_PORT_VAL) - copia assinada, nao alterar"
        .to_string()
}

/// Bloco dinamico: reescreve a COPIA + reassina via `rdpsign` (o original
/// nunca e tocado no clique).
pub fn rewrite_block_dynamic() -> String {
    "powershell -NoProfile -Command \"(Get-Content '%RUNRDP%') -replace '^full address:s:.*','full address:s:%WSL_IP%:RDP_PORT_VAL' | Set-Content '%RUNRDP%'; & %SystemRoot%\\System32\\rdpsign.exe /sha256 THUMBPRINT_VAL '%RUNRDP%' >nul 2>&1\"".to_string()
}

/// Janela do mstsc no `/v:` a partir de `WxH` (`1600x900` padrao, como o PS:
/// `$rdpW = 1600; $rdpH = 900` e so troca quando o `WxH` casa inteiro).
pub fn rdp_window_size(resolution: &str) -> (u32, u32) {
    if let Some((w, h)) = crate::rdp::split_resolution(resolution) {
        if let (Ok(w), Ok(h)) = (w.parse::<u32>(), h.parse::<u32>()) {
            return (w, h);
        }
    }
    (1600, 900)
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
    rdp_width: u32,
    rdp_height: u32,
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
        .replace("RDP_W_VAL", &rdp_width.to_string())
        .replace("RDP_H_VAL", &rdp_height.to_string())
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
    resolution: &str,
) -> String {
    let (disc, rewrite) = if localhost_live {
        (discovery_block_fixed(), rewrite_block_fixed())
    } else {
        (discovery_block_dynamic(), rewrite_block_dynamic())
    };
    let (w, h) = rdp_window_size(resolution);
    new_launcher_content(
        app_name, distro, linux_user, rdp_port, thumbprint, &disc, &rewrite, w, h,
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
            1600,
            900,
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
            "RDP_W_VAL",
            "RDP_H_VAL",
        ] {
            assert!(!c.contains(token), "sobrou {token}");
        }
    }

    #[test]
    fn vault_first_without_file_and_rdp_fallback() {
        // Sem arquivo aberto, sem dialogo de fornecedor (o `.rdp` segue
        // como fallback quando o helper do Cofre falha).
        let c = sample();
        assert!(c.contains("set CREDHELPER="));
        assert!(c.contains("Ubuntu-GUI-Cred.ps1"));
        assert!(
            c.contains("-File \"%CREDHELPER%\" \"%RUNRDP%\" \"%WSL_IP%\" 3390"),
            "helper nao chamado: {c}"
        );
        assert!(
            c.contains(
                "if errorlevel 1 (start \"Ubuntu-GUI\" \"%MSTSC%\" \"%RUNRDP%\") \
                 else (start \"Ubuntu-GUI\" %MSTSC% /v:%WSL_IP%:3390 /w:1600 /h:900)"
            ),
            "ramo /v: ausente: {c}"
        );
    }

    #[test]
    fn window_size_follows_resolution_with_default() {
        assert_eq!(rdp_window_size("1600x900"), (1600, 900));
        assert_eq!(rdp_window_size("800x600"), (800, 600));
        assert_eq!(rdp_window_size("abc"), (1600, 900));
        assert_eq!(rdp_window_size("1600x"), (1600, 900));
        let c = launcher_for_endpoint(
            "Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", true, "800x600",
        );
        assert!(c.contains("/w:800 /h:600"), "janela fora do pedido: {c}");
    }

    #[test]
    fn cred_helper_writes_vault_entries() {
        // Paridade com `New-CredHelperContent.ps1`: sidecar primeiro,
        // `.rdp` como fallback sanitizado, e grava `TERMSRV/` via DPAPI.
        for needle in [
            "param([string]$RdpPath, [string]$RdpHost, [int]$RdpPort)",
            "$sidecar = $PSCommandPath -replace '\\.ps1$', '.txt'",
            "password 51:b:",
            "0-9a-fA-F",
            "Length % 2 -eq 1",
            "ProtectedData",
            "Unprotect",
            "CredWriteW",
            "TERMSRV/",
        ] {
            assert!(
                CRED_HELPER_SCRIPT.contains(needle),
                "helper sem {needle}"
            );
        }
    }

    #[test]
    fn cred_sidecar_carries_user_and_blob() {
        let c = cred_sidecar_content("daniel", "aabb");
        let mut lines = c.lines();
        assert_eq!(lines.next(), Some("daniel"));
        assert_eq!(lines.next(), Some("aabb"));
    }

    #[test]
    fn embeds_thumbprint_and_user() {
        let c = sample();
        assert!(c.contains("ABC123"));
        assert!(c.contains("daniel"));
    }

    #[test]
    fn fixed_endpoint_preserves_signature() {
        let c = launcher_for_endpoint(
            "Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", true, "1600x900",
        );
        assert!(!c.contains("127.0.0.1:RDP_PORT_VAL"));
        assert!(c.contains("127.0.0.1:3390"));
        assert!(c.contains("nao alterar"));
        assert!(!c.contains("rdpsign"));
        assert!(c.contains("rem IP fixo via mirrored networking (127.0.0.1)"));
    }

    #[test]
    fn click_opens_a_copy_never_the_signed_original() {
        // O mstsc grava estado de sessao no .rdp que abre: abrir o original
        // invalidava a assinatura no primeiro clique.
        for local in [true, false] {
            let c = launcher_for_endpoint(
                "Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", local, "1600x900",
            );
            assert!(c.contains("copy /y \"%RDPPATH%\" \"%RUNRDP%\""), "sem copia: {c}");
            assert!(
                c.contains("start \"Ubuntu-GUI\" \"%MSTSC%\" \"%RUNRDP%\""),
                "abre o original: {c}"
            );
            // Ler o original como fonte da copia pode; escrever, nunca.
            assert!(
                !c.contains("Set-Content '%RDPPATH%'"),
                "original reescrito no clique: {c}"
            );
        }
    }

    #[test]
    fn dynamic_endpoint_rewrites_and_resigns() {
        let c = launcher_for_endpoint(
            "Ubuntu-GUI", "Ubuntu", "daniel", 3390, "ABC123", false, "1600x900",
        );
        assert!(c.contains("full address:s:%WSL_IP%:3390"));
        assert!(c.contains("rdpsign.exe /sha256 ABC123"));
        assert!(c.contains("hostname -I 2^>nul"));
        // Reescrita e reassinatura na COPIA (o original fica intacto).
        assert!(c.contains("'%RUNRDP%'"));
        assert!(!c.contains("'%RDPPATH%'"));
    }
}
