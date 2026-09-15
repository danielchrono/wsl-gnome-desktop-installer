//! Retomada sozinha apos reboot (`Save-ResumeState.ps1`).
//!
//! Salva respostas (senha em DPAPI, so este usuario le), copia o script em
//! execucao para a pasta do app e agenda reabertura via RunOnce
//! (`HKCU:\...\RunOnce` nome `UbuntuGUIResume`, comando
//! `powershell -NoProfile -ExecutionPolicy Bypass -File "<resume.ps1>" -Resume`).

use serde::{Deserialize, Serialize};

use crate::error::InstallError;

/// Caminho do valor RunOnce (espelha `$RunOncePath`).
pub const RUN_ONCE_PATH: &str = r"HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";
/// Nome do valor RunOnce (espelha `$RunOnceName`).
pub const RUN_ONCE_NAME: &str = "UbuntuGUIResume";
/// Nome do arquivo de estado (espelha `$ResumeFile`).
pub const RESUME_FILE_NAME: &str = "resume-state.json";
/// Nome da copia do instalador (espelha `$ResumePs1`).
pub const RESUME_PS1_NAME: &str = "Install-UbuntuGUI.resume.ps1";
/// Fase gravada no estado (espelha `Phase = "AfterReboot"`).
pub const RESUME_PHASE: &str = "AfterReboot";

/// Estado de retomada (`@{ Phase; LinuxUser; LinuxPassEnc; NetChoice }`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResumeState {
    #[serde(rename = "Phase")]
    pub phase: String,
    #[serde(rename = "LinuxUser")]
    pub linux_user: String,
    #[serde(rename = "LinuxPassEnc")]
    pub linux_pass_enc: String,
    #[serde(rename = "NetChoice")]
    pub net_choice: String,
}

impl ResumeState {
    pub fn new(linux_user: &str, linux_pass_enc: &str, net_choice: &str) -> Self {
        Self {
            phase: RESUME_PHASE.to_string(),
            linux_user: linux_user.to_string(),
            linux_pass_enc: linux_pass_enc.to_string(),
            net_choice: net_choice.to_string(),
        }
    }

    /// `ConvertTo-Json -Compress`.
    pub fn to_json(&self) -> Result<String, InstallError> {
        serde_json::to_string(self).map_err(InstallError::from)
    }

    pub fn from_json(text: &str) -> Result<Self, InstallError> {
        serde_json::from_str(text).map_err(InstallError::from)
    }
}

/// Comando RunOnce que reabre o instalador sozinho apos o reboot.
pub fn run_once_command(resume_ps1: &str) -> String {
    format!("powershell -NoProfile -ExecutionPolicy Bypass -File \"{resume_ps1}\" -Resume")
}

/// Base64 padrao (para o `LinuxPassEnc` DPAPI). Implementacao std-only:
///
/// `[Convert]::ToBase64String` / `FromBase64String`.
const B64_ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn base64_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let mut n: u32 = 0;
        for (i, b) in chunk.iter().enumerate() {
            n |= (*b as u32) << (16 - 8 * i);
        }
        let pad = 3 - chunk.len();
        for i in 0..4 - pad {
            let idx = ((n >> (18 - 6 * i)) & 0x3F) as usize;
            out.push(B64_ALPHABET[idx] as char);
        }
        for _ in 0..pad {
            out.push('=');
        }
    }
    out
}

pub fn base64_decode(text: &str) -> Result<Vec<u8>, InstallError> {
    let clean: Vec<u8> = text.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    if !clean.len().is_multiple_of(4) {
        return Err(InstallError::ResumeUnreadable(
            "base64: tamanho invalido".to_string(),
        ));
    }
    let val = |c: u8| -> Result<u32, InstallError> {
        match c {
            b'A'..=b'Z' => Ok((c - b'A') as u32),
            b'a'..=b'z' => Ok((c - b'a' + 26) as u32),
            b'0'..=b'9' => Ok((c - b'0' + 52) as u32),
            b'+' => Ok(62),
            b'/' => Ok(63),
            _ => Err(InstallError::ResumeUnreadable(format!(
                "base64: caractere invalido '{c}'"
            ))),
        }
    };
    let mut out = Vec::with_capacity(clean.len() / 4 * 3);
    for quad in clean.chunks(4) {
        let pad = quad.iter().rev().take_while(|&&c| c == b'=').count();
        if pad > 2 {
            return Err(InstallError::ResumeUnreadable(
                "base64: padding invalido".to_string(),
            ));
        }
        let mut n: u32 = 0;
        for (i, &c) in quad.iter().enumerate() {
            if c == b'=' {
                if i < 4 - pad {
                    return Err(InstallError::ResumeUnreadable(
                        "base64: padding no meio".to_string(),
                    ));
                }
            } else {
                n |= val(c)? << (18 - 6 * i);
            }
        }
        for i in 0..3 - pad {
            out.push(((n >> (16 - 8 * i)) & 0xFF) as u8);
        }
    }
    Ok(out)
}

/// Protege a senha com DPAPI `CurrentUser` e devolve base64 (Windows).
/// Fora do Windows: erro tipado.
#[cfg(windows)]
pub fn protect_password_base64(linux_pass: &str) -> Result<String, InstallError> {
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Security::Cryptography::{CryptProtectData, CRYPT_INTEGER_BLOB};

    let plain = linux_pass.as_bytes();
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
        let enc = base64_encode(bytes);
        // v0.61: LocalFree recebe Option<HLOCAL>; HLOCAL wrapa o ponteiro.
        let _ = LocalFree(Some(windows::Win32::Foundation::HLOCAL(blob_out.pbData as *mut _)));
        Ok(enc)
    }
}

#[cfg(not(windows))]
pub fn protect_password_base64(_linux_pass: &str) -> Result<String, InstallError> {
    Err(InstallError::NotSupportedOnLinux("DPAPI CryptProtectData"))
}

/// Desprotege o `LinuxPassEnc` (Windows). Fora: erro tipado.
#[cfg(windows)]
pub fn unprotect_password_base64(enc: &str) -> Result<String, InstallError> {
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};

    let cipher = base64_decode(enc)?;
    let blob_in = CRYPT_INTEGER_BLOB {
        cbData: cipher.len() as u32,
        pbData: cipher.as_ptr() as *mut u8,
    };
    let mut blob_out = CRYPT_INTEGER_BLOB::default();
    // SAFETY: buffers validos durante a chamada; `LocalFree` apos copiar.
    unsafe {
        CryptUnprotectData(&blob_in, None, None, None, None, 0, &mut blob_out).map_err(|e| {
            InstallError::ResumeUnreadable(format!("DPAPI CryptUnprotectData: {e}"))
        })?;
        let bytes = std::slice::from_raw_parts(blob_out.pbData, blob_out.cbData as usize);
        let s = String::from_utf8(bytes.to_vec()).map_err(|e| {
            InstallError::ResumeUnreadable(format!("estado de retomada nao-UTF8: {e}"))
        })?;
        // v0.61: LocalFree recebe Option<HLOCAL>; HLOCAL wrapa o ponteiro.
        let _ = LocalFree(Some(windows::Win32::Foundation::HLOCAL(blob_out.pbData as *mut _)));
        Ok(s)
    }
}

#[cfg(not(windows))]
pub fn unprotect_password_base64(_enc: &str) -> Result<String, InstallError> {
    Err(InstallError::NotSupportedOnLinux(
        "DPAPI CryptUnprotectData",
    ))
}

/// Escreve o valor RunOnce (Windows, via `winreg`). Fora: erro tipado.
#[cfg(windows)]
pub fn write_run_once(value: &str) -> Result<(), InstallError> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let key = hkcu
        .open_subkey_with_flags(
            r"Software\Microsoft\Windows\CurrentVersion\RunOnce",
            winreg::enums::KEY_SET_VALUE,
        )
        .map_err(|e| InstallError::Io(format!("RunOnce open: {e}")))?;
    key.set_value(RUN_ONCE_NAME, &value)
        .map_err(|e| InstallError::Io(format!("RunOnce write: {e}")))?;
    Ok(())
}

#[cfg(not(windows))]
pub fn write_run_once(_value: &str) -> Result<(), InstallError> {
    Err(InstallError::NotSupportedOnLinux("RunOnce HKCU"))
}

/// Remove o valor RunOnce (Windows). Fora: ok silencioso (nada a limpar).
#[cfg(windows)]
pub fn clear_run_once() -> Result<(), InstallError> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    if let Ok(key) = hkcu.open_subkey_with_flags(
        r"Software\Microsoft\Windows\CurrentVersion\RunOnce",
        winreg::enums::KEY_SET_VALUE,
    ) {
        let _ = key.delete_value(RUN_ONCE_NAME);
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn clear_run_once() -> Result<(), InstallError> {
    Ok(())
}

/// `Save-ResumeState` (parte portavel): monta estado + comando RunOnce.
/// Arquivos/registro ficam com o chamador Windows (`save_resume_files`).
pub fn build_resume_state(
    linux_user: &str,
    linux_pass_enc_b64: &str,
    net_choice: &str,
) -> ResumeState {
    ResumeState::new(linux_user, linux_pass_enc_b64, net_choice)
}

/// Grava `resume-state.json` + copia do instalador + RunOnce (Windows).
/// Fora do Windows: erro tipado antes de tocar no disco.
#[cfg(windows)]
pub fn save_resume_files(
    source_exe: &std::path::Path,
    prog_dir: &std::path::Path,
    state: &ResumeState,
) -> Result<std::path::PathBuf, InstallError> {
    std::fs::create_dir_all(prog_dir)?;
    let resume_ps1 = prog_dir.join("Install-UbuntuGUI.resume.cmd");
    std::fs::copy(source_exe, &resume_ps1)?;
    let resume_file = prog_dir.join(RESUME_FILE_NAME);
    std::fs::write(&resume_file, state.to_json()?)?;
    write_run_once(&run_once_command(&resume_ps1.to_string_lossy()))?;
    Ok(resume_file)
}

#[cfg(not(windows))]
pub fn save_resume_files(
    _source_exe: &std::path::Path,
    _prog_dir: &std::path::Path,
    _state: &ResumeState,
) -> Result<std::path::PathBuf, InstallError> {
    Err(InstallError::NotSupportedOnLinux("Save-ResumeState"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_shape_matches_powershell() {
        let st = ResumeState::new("daniel", "QkJD", "1");
        let json = st.to_json().unwrap();
        assert!(json.contains(r#""Phase":"AfterReboot""#));
        assert!(json.contains(r#""LinuxUser":"daniel""#));
        assert!(json.contains(r#""LinuxPassEnc":"QkJD""#));
        assert!(json.contains(r#""NetChoice":"1""#));
        let back = ResumeState::from_json(&json).unwrap();
        assert_eq!(back, st);
    }

    #[test]
    fn run_once_command_shape() {
        assert_eq!(
            run_once_command("C:\\App\\Install-UbuntuGUI.resume.ps1"),
            "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\App\\Install-UbuntuGUI.resume.ps1\" -Resume"
        );
        assert_eq!(RUN_ONCE_NAME, "UbuntuGUIResume");
    }

    #[test]
    fn base64_known_vector() {
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_decode("Zm9v").unwrap(), b"foo");
        assert_eq!(base64_decode("Zg==").unwrap(), b"f");
        assert_eq!(base64_decode("").unwrap(), b"");
    }

    #[test]
    fn base64_round_trip_binary() {
        let bytes: Vec<u8> = (0u8..=255u8).collect();
        assert_eq!(base64_decode(&base64_encode(&bytes)).unwrap(), bytes);
    }

    #[test]
    fn base64_rejects_garbage() {
        assert!(base64_decode("!!!").is_err());
        assert!(base64_decode("abc").is_err());
    }
}
