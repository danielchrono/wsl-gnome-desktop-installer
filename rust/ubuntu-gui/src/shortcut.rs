//! Escritor `.lnk` puro std-only (MS-SHLLINK, little-endian).
//!
//! Por que existe: o crate `mslnk` (design original) so compila no Windows
//! (`std::os::windows::ffi`), entao nao e `linux-testavel` nem entra em
//! build `--offline` no Linux. Regra final:
//!
//! - Windows: [`crate::install::build_shortcut_file`] usa `mslnk` (link
//!   completo com IDList, como o `WScript.Shell` do PowerShell);
//! - Linux/testes: este modulo grava um `.lnk` estruturalmente valido
//!   (header + LinkInfo com `LocalBasePath` + StringData ANSI + ShowCommand
//!   7 = `WindowStyle 7`), coberto por goldens aqui.
//!
//! Layout (todos os inteiros little-endian):
//! `ShellLinkHeader` (76B) + `LinkInfo` + StringData(NAME, RELATIVE_PATH,
//! WORKING_DIR, ICON_LOCATION) + terminal `0u32`.

use std::path::Path;

use crate::error::InstallError;

/// GUID `LinkCLSID` (`00021401-0000-0000-C000-000000000046`).
const LINK_CLSID: [u8; 16] = [
    0x01, 0x14, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
];

const HAS_LINK_INFO: u32 = 0x0000_0002;
const HAS_NAME: u32 = 0x0000_0004;
const HAS_RELATIVE_PATH: u32 = 0x0000_0008;
const HAS_WORKING_DIR: u32 = 0x0000_0010;
const HAS_ICON_LOCATION: u32 = 0x0000_0040;

/// `SW_SHOWMINNOACTIVE` = 7 (espelha `WindowStyle = 7` do `WScript.Shell`).
pub const SHOW_MIN_NO_ACTIVE: u32 = 7;

/// Campos do atalho (mesmos do fluxo `WScript.Shell`: alvo, pasta de
/// trabalho, icone (path puro, sem `,0`: o mslnk grava literal e o Windows
/// lia `ico,0,0`), descricao, janela minimizada sem foco).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShortcutSpec {
    pub target: String,
    pub working_dir: String,
    pub icon_location: String,
    pub description: String,
}

impl ShortcutSpec {
    pub fn new(
        target: impl Into<String>,
        working_dir: impl Into<String>,
        icon_location: impl Into<String>,
        description: impl Into<String>,
    ) -> Self {
        Self {
            target: target.into(),
            working_dir: working_dir.into(),
            icon_location: icon_location.into(),
            description: description.into(),
        }
    }
}

fn u16le(v: u16, out: &mut Vec<u8>) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn u32le(v: u32, out: &mut Vec<u8>) {
    out.extend_from_slice(&v.to_le_bytes());
}

/// StringData ANSI: `CountCharacters:u16` + bytes (sem NUL).
fn push_string_data(s: &str, out: &mut Vec<u8>) {
    let bytes = s.as_bytes();
    u16le(bytes.len() as u16, out);
    out.extend_from_slice(bytes);
}

/// Monta os bytes do `.lnk`.
pub fn build_lnk_bytes(spec: &ShortcutSpec) -> Vec<u8> {
    let mut out = Vec::new();

    // --- ShellLinkHeader (76 bytes) ---
    u32le(0x4C, &mut out); // HeaderSize
    out.extend_from_slice(&LINK_CLSID);
    u32le(
        HAS_LINK_INFO | HAS_NAME | HAS_RELATIVE_PATH | HAS_WORKING_DIR | HAS_ICON_LOCATION,
        &mut out,
    ); // LinkFlags
    u32le(0x20, &mut out); // FileAttributes: FILE_ATTRIBUTE_ARCHIVE
    out.extend_from_slice(&[0u8; 24]); // Creation/Access/WriteTime
    u32le(0, &mut out); // FileSize
    u32le(0, &mut out); // IconIndex
    u32le(SHOW_MIN_NO_ACTIVE, &mut out); // ShowCommand
    u16le(0, &mut out); // HotKey
    out.extend_from_slice(&[0u8; 10]); // Reserved1(2) + Reserved2(4) + Reserved3(4)

    // --- LinkInfo (LocalBasePath = alvo) ---
    let local: Vec<u8> = spec
        .target
        .as_bytes()
        .iter()
        .cloned()
        .chain(std::iter::once(0))
        .collect();
    let suffix: &[u8] = b"\0";
    // VolumeID minimo: Size=0x10, DriveType=DRIVE_FIXED(3), Serial=0, Label=empty.
    let volume: Vec<u8> = {
        let mut v = Vec::new();
        u32le(0x10, &mut v);
        u32le(3, &mut v);
        u32le(0, &mut v);
        u32le(0x10, &mut v);
        v
    };
    let header_size: u32 = 0x1C;
    let volume_off: u32 = header_size;
    let local_off: u32 = header_size + volume.len() as u32;
    let suffix_off: u32 = local_off + local.len() as u32;
    let info_size: u32 = suffix_off + suffix.len() as u32;
    u32le(info_size, &mut out); // LinkInfoSize
    u32le(header_size, &mut out); // LinkInfoHeaderSize
    u32le(0x0000_0001, &mut out); // VolumeIDAndLocalBasePath
    u32le(volume_off, &mut out);
    u32le(local_off, &mut out);
    u32le(0, &mut out); // CommonNetworkRelativeLinkOffset
    u32le(suffix_off, &mut out); // CommonPathSuffixOffset
    out.extend_from_slice(&volume);
    out.extend_from_slice(&local);
    out.extend_from_slice(suffix);

    // --- StringData (ordem fixa da spec) ---
    push_string_data(&spec.description, &mut out); // NAME_STRING
    push_string_data(&spec.target, &mut out); // RELATIVE_PATH
    push_string_data(&spec.working_dir, &mut out); // WORKING_DIR
    push_string_data(&spec.icon_location, &mut out); // ICON_LOCATION

    // --- ExtraData terminal ---
    u32le(0, &mut out);
    out
}

/// Grava o `.lnk` no disco.
pub fn write_lnk_file(lnk_path: &Path, spec: &ShortcutSpec) -> Result<(), InstallError> {
    if let Some(parent) = lnk_path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    std::fs::write(lnk_path, build_lnk_bytes(spec))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> ShortcutSpec {
        ShortcutSpec::new(
            r"C:\App\Ubuntu-GUI.cmd",
            r"C:\App",
            r"C:\Icons\ubuntu.ico",
            "Abre o desktop GNOME do Ubuntu (WSL) via RDP",
        )
    }

    #[test]
    fn header_magic_and_clsid() {
        let b = build_lnk_bytes(&sample());
        assert!(b.len() > 76);
        assert_eq!(&b[0..4], &[0x4C, 0x00, 0x00, 0x00]);
        assert_eq!(&b[4..20], &LINK_CLSID);
    }

    #[test]
    fn flags_and_show_command() {
        let b = build_lnk_bytes(&sample());
        let flags = u32::from_le_bytes(b[20..24].try_into().unwrap());
        assert_eq!(flags, 0x5E);
        let show = u32::from_le_bytes(b[60..64].try_into().unwrap());
        assert_eq!(show, SHOW_MIN_NO_ACTIVE);
    }

    #[test]
    fn embeds_target_workdir_icon_and_description() {
        let b = build_lnk_bytes(&sample());
        for needle in [
            r"C:\App\Ubuntu-GUI.cmd".as_bytes(),
            r"C:\App".as_bytes(),
            r"C:\Icons\ubuntu.ico".as_bytes(),
            "Abre o desktop GNOME".as_bytes(),
        ] {
            assert!(
                b.windows(needle.len()).any(|w| w == needle),
                "falta {}",
                String::from_utf8_lossy(needle)
            );
        }
    }

    #[test]
    fn linkinfo_offsets_are_consistent() {
        let b = build_lnk_bytes(&sample());
        let base = 76;
        let size = u32::from_le_bytes(b[base..base + 4].try_into().unwrap()) as usize;
        // Offsets relativos ao inicio do LinkInfo.
        let local_rel = u32::from_le_bytes(b[base + 16..base + 20].try_into().unwrap()) as usize;
        let suffix_rel = u32::from_le_bytes(b[base + 24..base + 28].try_into().unwrap()) as usize;
        assert!(local_rel > 0 && suffix_rel > local_rel);
        assert!(base + size <= b.len());
        // LocalBasePath NUL-terminado dentro do LinkInfo.
        let local = &b[base + local_rel..base + suffix_rel];
        assert_eq!(local.last(), Some(&0));
        assert!(local.starts_with(r"C:\App\Ubuntu-GUI.cmd".as_bytes()));
    }

    #[test]
    fn writes_file_to_disk() {
        // Nome unico por teste: dividir o diretorio com outro teste no mesmo
        // processo causava falha intermitente (um apagava o arquivo do outro).
        let dir = std::env::temp_dir().join(format!("ubuntu-gui-lnk-writes-{}", std::process::id()));
        let lnk = dir.join("Ubuntu-GUI.lnk");
        write_lnk_file(&lnk, &sample()).unwrap();
        let back = std::fs::read(&lnk).unwrap();
        assert_eq!(back, build_lnk_bytes(&sample()));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
