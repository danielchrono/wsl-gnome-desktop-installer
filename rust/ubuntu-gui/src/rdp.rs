//! Monta as linhas do `.rdp` com login automatico (`New-RdpFileContent.ps1`).
//!
//! Senha em blob DPAPI (so este usuario le), serializada como
//! `password 51:b:<hex>` com hex minusculo (`$_.ToString('x2')`).
//! `authentication level:i:0` = nao avisar: cert autoassinado
//! (loopback/WSL, sem MITM pratico).

use crate::error::InstallError;

/// `New-RdpFileContent`: ordem das linhas espelha o PowerShell — `screen
/// mode` + `bpp` + `dynamic resolution`, resolucao (se `WxH`), endereco, usuario,
/// flags (SEM `password 51:b:`: o rdpsign deforma a linha longa e quebra a
/// assinatura; a senha vai no sidecar `-Cred.txt` para o Cofre).
/// Resolucao fora de `^(\d+)x(\d+)$` e ignorada (WxH-gate).
pub fn new_rdp_file_content(
    rdp_host: &str,
    rdp_port: u16,
    linux_user: &str,
    resolution: &str,
) -> Vec<String> {
    let mut rdp = vec![
        // 1 = janela (2 = tela cheia); paridade com o PS — maximizar continua possivel.
        "screen mode id:i:1".to_string(),
        "session bpp:i:32".to_string(),
        // Zoom para caber na janela (sem scroll); com a sessao no tamanho da
        // area util, o maximizado fica 1:1 sem blur.
        "smart sizing:i:1".to_string(),
        // dynamic resolution: chave exploratoria (ignorada por mstsc desconhecido);
        // o beneficio real e a remocao do smart sizing, que bloqueava o redimensionamento
        // dinamico do xrdp — sem ele o servidor ja acompanha a janela por padrao.
        "dynamic resolution:i:1".to_string(),
        // USB do host na sessao (paridade com o PS).
        "usbdevicestoredirect:s:*".to_string(),
    ];
    if let Some((w, h)) = split_resolution(resolution) {
        rdp.push(format!("desktopwidth:i:{w}"));
        rdp.push(format!("desktopheight:i:{h}"));
    }
    rdp.push(format!("full address:s:{rdp_host}:{rdp_port}"));
    rdp.push(format!("username:s:{linux_user}"));
    // Senha omitida do .rdp: o rdpsign deforma a linha `password 51:b:<hex>` longa
    // (528 chars) e invalida a assinatura; a credencial vai no sidecar `-Cred.txt`.
    rdp.push("prompt for credentials:i:0".to_string());
    rdp.push("enablecredsspsupport:i:1".to_string());
    rdp.push("authentication level:i:0".to_string());
    rdp.push("promptcredentialonce:i:1".to_string());
    rdp.push("negotiate security layer:i:1".to_string());
    rdp
}

/// Parse puro de `WxH` (`$Resolution -match '^(\d+)x(\d+)$'`).
pub fn split_resolution(resolution: &str) -> Option<(String, String)> {
    let (w, h) = resolution.split_once('x')?;
    if !w.is_empty()
        && !h.is_empty()
        && w.bytes().all(|b| b.is_ascii_digit())
        && h.bytes().all(|b| b.is_ascii_digit())
    {
        Some((w.to_string(), h.to_string()))
    } else {
        None
    }
}

/// Serializa o blob DPAPI como hex minusculo (`ToString('x2')` por byte).
pub fn blob_to_hex(blob: &[u8]) -> String {
    let mut out = String::with_capacity(blob.len() * 2);
    for b in blob {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

/// Protege a senha com DPAPI `CurrentUser` e devolve o hex para o `.rdp`.
///
/// No Windows usa `CryptProtectData` (equivale a
/// `[ProtectedData]::Protect(Unicode.GetBytes(pass), $null, 'CurrentUser')`).
/// Fora do Windows: erro tipado (sem DPAPI nao ha blob valido).
#[cfg(windows)]
pub fn protect_password_hex(linux_pass: &str) -> Result<String, InstallError> {
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Security::Cryptography::{CryptProtectData, CRYPT_INTEGER_BLOB};

    let plain: Vec<u8> = linux_pass
        .encode_utf16()
        .flat_map(|u| u.to_le_bytes())
        .collect();
    let blob_in = CRYPT_INTEGER_BLOB {
        cbData: plain.len() as u32,
        pbData: plain.as_ptr() as *mut u8,
    };
    let mut blob_out = CRYPT_INTEGER_BLOB::default();
    // SAFETY: buffers validos durante a chamada; `LocalFree` apos copiar.
    unsafe {
        CryptProtectData(&blob_in, None, None, None, None, 0, &mut blob_out)
            .map_err(|e| InstallError::Io(format!("DPAPI CryptProtectData: {e}")))?;
        let bytes = std::slice::from_raw_parts(blob_out.pbData, blob_out.cbData as usize);
        let hex = blob_to_hex(bytes);
        // v0.61: LocalFree recebe Option<HLOCAL>; HLOCAL wrapa o ponteiro.
        let _ = LocalFree(Some(windows::Win32::Foundation::HLOCAL(blob_out.pbData as *mut _)));
        Ok(hex)
    }
}

#[cfg(not(windows))]
pub fn protect_password_hex(_linux_pass: &str) -> Result<String, InstallError> {
    Err(InstallError::NotSupportedOnLinux("DPAPI CryptProtectData"))
}

/// O `.rdp` tem assinatura apos o `rdpsign`? Casa `signature:s:` nos bytes
/// com ou sem NULs: o `rdpsign` reescreve o arquivo em UTF-16LE e a busca
/// textual direta nao casa (`s\0i\0g\0...`) — checar so exit code 0 + texto
/// UTF-8 dizia "falhou" com o arquivo assinado.
pub fn rdp_has_signature(bytes: &[u8]) -> bool {
    let needle = b"signature:s:";
    if bytes.windows(needle.len()).any(|w| w == needle) {
        return true;
    }
    let filtered: Vec<u8> = bytes.iter().copied().filter(|&b| b != 0).collect();
    filtered.windows(needle.len()).any(|w| w == needle)
}

/// Assina o `.rdp` com `rdpsign.exe /sha256` (warn-only se falhar, como no
/// PowerShell: o aviso de fornecedor pode continuar, nao e fatal).
#[cfg(windows)]
pub fn sign_rdp_file(rdp_path: &std::path::Path, thumbprint: &str) -> bool {
    use std::process::Command;

    let system_root = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".to_string());
    let rdpsign = format!("{system_root}\\System32\\rdpsign.exe");
    let status = Command::new(&rdpsign)
        .args(["/sha256", thumbprint, &rdp_path.to_string_lossy()])
        .status();
    match status {
        Ok(s) if s.success() => std::fs::read(rdp_path)
            .map(|b| rdp_has_signature(&b))
            .unwrap_or(false),
        _ => false,
    }
}

#[cfg(not(windows))]
pub fn sign_rdp_file(_rdp_path: &std::path::Path, _thumbprint: &str) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<String> {
        new_rdp_file_content("127.0.0.1", 3390, "daniel", "1600x900")
    }

    #[test]
    fn no_password_blob_in_signed_file() {
        // Senha omitida: o rdpsign deforma linhas longas e quebra a assinatura.
        assert!(sample().iter().all(|l| !l.starts_with("password 51:b:")));
    }

    #[test]
    fn carries_address_and_user() {
        let joined = sample().join("\n");
        assert!(joined.contains("full address:s:127.0.0.1:3390"));
        assert!(joined.contains("username:s:daniel"));
    }

    #[test]
    fn carries_resolution_and_auto_login() {
        let rdp = sample();
        assert!(rdp.contains(&"desktopwidth:i:1600".to_string()));
        assert!(rdp.contains(&"desktopheight:i:900".to_string()));
        assert!(rdp.contains(&"prompt for credentials:i:0".to_string()));
        // Senha nao esta no .rdp; vai no sidecar -Cred.txt.
        assert!(!rdp.iter().any(|l| l.starts_with("password 51:b:")));
        // NLA mantida (enablecredsspsupport e negotiate security layer).
        assert!(rdp.iter().any(|l| l.starts_with("enablecredsspsupport")));
        assert!(rdp.iter().any(|l| l.starts_with("negotiate security layer")));
        // Zoom sem scroll (com a sessao na area util, o maximizado fica 1:1).
        assert!(rdp.contains(&"smart sizing:i:1".to_string()));
        assert!(rdp.contains(&"dynamic resolution:i:1".to_string()));
    }

    #[test]
    fn no_self_signed_cert_warning() {
        assert!(sample().contains(&"authentication level:i:0".to_string()));
    }

    #[test]
    fn exact_line_order() {
        assert_eq!(
            sample(),
            vec![
                "screen mode id:i:1",
                "session bpp:i:32",
                "smart sizing:i:1",
                "dynamic resolution:i:1",
                "usbdevicestoredirect:s:*",
                "desktopwidth:i:1600",
                "desktopheight:i:900",
                "full address:s:127.0.0.1:3390",
                "username:s:daniel",
                "prompt for credentials:i:0",
                "enablecredsspsupport:i:1",
                "authentication level:i:0",
                "promptcredentialonce:i:1",
                "negotiate security layer:i:1",
            ]
            .into_iter()
            .map(String::from)
            .collect::<Vec<_>>()
        );
    }

    #[test]
    fn invalid_resolution_skips_w_h_lines() {
        let rdp = new_rdp_file_content("h", 3390, "u", "abc");
        assert!(!rdp.iter().any(|l| l.starts_with("desktopwidth")));
        assert!(!rdp.iter().any(|l| l.starts_with("desktopheight")));
        // WxH-gate: parcial nao entra.
        let rdp = new_rdp_file_content("h", 3390, "u", "1600x");
        assert!(!rdp.iter().any(|l| l.starts_with("desktopwidth")));
    }

    #[test]
    fn hex_is_lowercase_per_byte() {
        assert_eq!(blob_to_hex(&[0x0A, 0xBB, 0x00, 0xFF]), "0abb00ff");
    }

    #[test]
    fn signature_found_in_utf8_and_utf16le() {
        // UTF-8 direto (como gravamos).
        assert!(rdp_has_signature(b"full address:s:x\nsignature:s:AQAB\n"));
        // UTF-16LE (como o rdpsign reescreve): ASCII intercalado com NUL.
        let wide: Vec<u8> = "signature:s:AQAB"
            .bytes()
            .flat_map(|b| [b, 0])
            .collect();
        assert!(rdp_has_signature(&wide));
        assert!(!rdp_has_signature(b"full address:s:x\n"));
        assert!(!rdp_has_signature(&[]));
    }

    #[cfg(not(windows))]
    #[test]
    fn dpapi_stub_is_typed() {
        assert!(matches!(
            protect_password_hex("x"),
            Err(InstallError::NotSupportedOnLinux(_))
        ));
    }
}
