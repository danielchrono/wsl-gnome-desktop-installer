//! Certificado de publicador (`New-PublisherCertificate.ps1`): assinar o
//! `.rdp` para sumir o aviso "fornecedor desconhecido".
//!
//! Idempotente via script find-or-create ([`publisher_cert_script`]) que usa
//! a mesma primitiva do PS (`New-SelfSignedCertificate`, reaproveita de
//! `CurrentUser\My` por `Subject -eq`, grava em `My` + `TrustedPublishers`)
//! e devolve o thumbprint pelo marcador ([`parse_thumbprint_output`]).
//! O `generate_self_signed` (rcgen) fica como item testavel no Linux da
//! matriz; nao e usado no Windows (rcgen gera ECDSA sem chave persistida,
//! inutil para o `rdpsign`).

use crate::error::InstallError;

/// Extra `CN=...` de um subject `CN=nome` (formato de `PublisherSubject`).
pub fn common_name_of_subject(subject: &str) -> &str {
    subject.strip_prefix("CN=").unwrap_or(subject)
}

/// `Where-Object { $_.Subject -eq $Subject } | Select-Object -First 1`:
/// igualdade exata sobre os subjects do store `My`.
pub fn find_existing_subject<'a>(subjects: &[&'a str], want: &str) -> Option<&'a str> {
    subjects.iter().copied().find(|s| *s == want)
}

/// Certificado autoassinado gerado (PEM cert + PEM key + DER).
#[derive(Debug, Clone)]
pub struct GeneratedCert {
    pub cert_pem: String,
    pub key_pem: String,
    pub cert_der: Vec<u8>,
    /// Validade em dias (`NotAfter - NotBefore`, espelha `AddYears`).
    pub validity_days: i64,
}

/// Gera um CodeSigning autoassinado com rcgen (`NotAfter = +CertYears`).
///
/// Equivale a `New-SelfSignedCertificate -Type CodeSigningCert -Subject
/// $Subject -NotAfter (Get-Date).AddYears($CertYears)`. Funciona no Linux
/// (puro Rust) — item `cert rcgen gen` da matriz linux.
pub fn generate_self_signed(subject: &str, years: u32) -> Result<GeneratedCert, InstallError> {
    use rcgen::{
        CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, KeyPair, KeyUsagePurpose,
    };

    let mut params = CertificateParams::new(vec![])
        .map_err(|e| InstallError::CertFailed(format!("rcgen params: {e}")))?;
    params
        .distinguished_name
        .push(DnType::CommonName, common_name_of_subject(subject));
    params.is_ca = IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];
    params.extended_key_usages = vec![ExtendedKeyUsagePurpose::CodeSigning];
    let now = time::OffsetDateTime::now_utc();
    let validity_days = 365 * years as i64;
    params.not_before = now;
    params.not_after = now + time::Duration::days(validity_days);
    let key_pair =
        KeyPair::generate().map_err(|e| InstallError::CertFailed(format!("rcgen key: {e}")))?;
    let cert = params
        .self_signed(&key_pair)
        .map_err(|e| InstallError::CertFailed(format!("rcgen self-sign: {e}")))?;
    Ok(GeneratedCert {
        cert_pem: cert.pem(),
        key_pem: key_pair.serialize_pem(),
        cert_der: cert.der().to_vec(),
        validity_days,
    })
}

/// Garante o certificado de publicador (Windows): reaproveita de `My` por
/// Subject ou gera + grava em `My` e `TrustedPublishers`. Retorna o
/// thumbprint (SHA-1 hex maiusculo, como `$pubCert.Thumbprint`).
///
/// Delega a criacao ao `New-SelfSignedCertificate` (a mesma primitiva do
/// `New-PublisherCertificate.ps1`): so ele cria RSA-2048 **com a chave
/// privada persistida no store** — sem ela o `rdpsign` recusa o cert com
/// `0x8009200B`. O caminho anterior (rcgen gera ECDSA, e o add via DER nao
/// persiste chave) produzia um cert inutil para assinatura.
#[cfg(windows)]
pub fn ensure_publisher_certificate(subject: &str, years: u32) -> Result<String, InstallError> {
    use std::os::windows::process::CommandExt;
    // CREATE_NO_WINDOW = 0x08000000: sem flash de console (como `wsl_cmd`).
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let script = publisher_cert_script(subject, years);
    let out = std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script.as_str(),
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(InstallError::from)?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    if let Some(tp) = parse_thumbprint_output(&stdout) {
        return Ok(tp);
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    let mut tail: Vec<String> = stdout
        .lines()
        .chain(stderr.lines())
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect();
    if tail.len() > 3 {
        tail = tail[tail.len() - 3..].to_vec();
    }
    if tail.is_empty() {
        tail.push("(sem saida)".to_string());
    }
    Err(InstallError::CertFailed(format!(
        "publicador nao garantido ({})",
        tail.join(" | ")
    )))
}

/// Script find-or-create do publicador (mesma primitiva do PS legado, numa
/// unica chamada): reaproveita de `My` por Subject exato **com chave
/// privada** ou cria CodeSigning autoassinado em `My` + `TrustedPublishers`.
/// O `HasPrivateKey` descarta o cert sem chave que o caminho antigo (DER
/// sem chave) deixou no store — sem ele o `rdpsign` seguiria falhando.
/// Imprime `UBUNTUGUI_THUMBPRINT=<40 hex>`; sem CRLF (vai no argv).
pub fn publisher_cert_script(subject: &str, years: u32) -> String {
    format!(
        "$c = Get-ChildItem Cert:\\CurrentUser\\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object {{ $_.Subject -eq '{subject}' -and $_.HasPrivateKey }} | Select-Object -First 1; if (-not $c) {{ $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject '{subject}' -CertStoreLocation Cert:\\CurrentUser\\My -NotAfter (Get-Date).AddYears({years}); $s = New-Object Security.Cryptography.X509Certificates.X509Store('TrustedPublishers','CurrentUser'); $s.Open('ReadWrite'); $s.Add($c); $s.Close() }}; 'UBUNTUGUI_THUMBPRINT=' + $c.Thumbprint"
    )
}

/// Parser fail-closed do marcador (40 hex; `.NET Thumbprint` ja e
/// maiusculo, normaliza de todo jeito).
pub fn parse_thumbprint_output(out: &str) -> Option<String> {
    for line in out.lines() {
        if let Some(rest) = line.strip_prefix("UBUNTUGUI_THUMBPRINT=") {
            let tp = rest.trim();
            if tp.len() == 40 && tp.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Some(tp.to_ascii_uppercase());
            }
        }
    }
    None
}

/// SHA-1 em hex maiusculo (formato do thumbprint .NET). Implementacao
/// std-only para nao puxar crate so para isso. Spec executavel do formato
/// (so usada em testes: o thumbprint de producao vem do store via
/// `parse_thumbprint_output`).
#[cfg(test)]
fn sha1_hex_upper(data: &[u8]) -> String {
    let digest = sha1(data);
    digest.iter().map(|b| format!("{b:02X}")).collect()
}

#[cfg(test)]
fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h: [u32; 5] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0];
    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for block in msg.chunks_exact(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                block[4 * i],
                block[4 * i + 1],
                block[4 * i + 2],
                block[4 * i + 3],
            ]);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let (mut a, mut b, mut c, mut d, mut e) = (h[0], h[1], h[2], h[3], h[4]);
        for i in 0..80 {
            let (f, k) = match i {
                0..=19 => ((b & c) | ((!b) & d), 0x5A827999),
                20..=39 => (b ^ c ^ d, 0x6ED9EBA1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDC),
                _ => (b ^ c ^ d, 0xCA62C1D6),
            };
            let tmp = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(w[i]);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = tmp;
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
    }
    let mut out = [0u8; 20];
    for (i, v) in h.iter().enumerate() {
        out[4 * i..4 * i + 4].copy_from_slice(&v.to_be_bytes());
    }
    out
}

/// Fora do Windows nao ha cert store: so gerar (rcgen) e erro tipado no
/// `ensure`.
#[cfg(not(windows))]
pub fn ensure_publisher_certificate(_subject: &str, _years: u32) -> Result<String, InstallError> {
    Err(InstallError::NotSupportedOnLinux(
        "cert store CurrentUser\\My",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subject_helpers() {
        assert_eq!(
            common_name_of_subject("CN=Ubuntu-GUI RDP"),
            "Ubuntu-GUI RDP"
        );
        assert_eq!(
            find_existing_subject(&["CN=Outro", "CN=Ubuntu-GUI RDP"], "CN=Ubuntu-GUI RDP"),
            Some("CN=Ubuntu-GUI RDP")
        );
        assert_eq!(
            find_existing_subject(&["CN=Outro"], "CN=Ubuntu-GUI RDP"),
            None
        );
    }

    #[test]
    fn rcgen_generates_self_signed() {
        let gen = generate_self_signed("CN=Ubuntu-GUI RDP", 10).unwrap();
        assert!(gen.cert_pem.contains("-----BEGIN CERTIFICATE-----"));
        assert!(gen.key_pem.contains("PRIVATE KEY"));
        assert!(!gen.cert_der.is_empty());
    }

    #[test]
    fn cert_script_carries_subject_years_and_marker() {
        let s = publisher_cert_script("CN=Ubuntu-GUI RDP", 10);
        assert!(s.contains("CN=Ubuntu-GUI RDP"));
        assert!(s.contains("HasPrivateKey"));
        assert!(s.contains("AddYears(10)"));
        assert!(s.contains("New-SelfSignedCertificate -Type CodeSigningCert"));
        assert!(s.contains("UBUNTUGUI_THUMBPRINT="));
        assert!(!s.contains('\r'), "CRLF quebraria o argv do powershell");
    }

    #[test]
    fn thumbprint_parser_accepts_marker_and_rejects_garbage() {
        let good = "Publicador confiavel criado\nUBUNTUGUI_THUMBPRINT=A9993E364706816ABA3E25717850C26C9CD0D89D\n";
        assert_eq!(
            parse_thumbprint_output(good),
            Some("A9993E364706816ABA3E25717850C26C9CD0D89D".to_string())
        );
        // Sem marcador, curto ou nao-hex: fail-closed.
        assert_eq!(parse_thumbprint_output("ok sem marcador\n"), None);
        assert_eq!(parse_thumbprint_output("UBUNTUGUI_THUMBPRINT=ABC123\n"), None);
        assert_eq!(
            parse_thumbprint_output(
                "UBUNTUGUI_THUMBPRINT=ZZZZ3E364706816ABA3E25717850C26C9CD0D89D\n"
            ),
            None
        );
        assert_eq!(parse_thumbprint_output(""), None);
    }

    #[test]
    fn sha1_matches_nist_vector() {
        // SHA-1("abc") (FIPS 180-4; conferido contra `sha1sum` e hashlib).
        assert_eq!(
            sha1_hex_upper(b"abc"),
            "A9993E364706816ABA3E25717850C26C9CD0D89D"
        );
    }

    #[test]
    fn generated_thumbprint_is_upper_hex_sha1_of_der() {
        // Formato do `$cert.Thumbprint`: 40 hex maiusculos do SHA-1 do DER.
        let gen = generate_self_signed("CN=Ubuntu-GUI RDP", 10).unwrap();
        let tp = sha1_hex_upper(&gen.cert_der);
        assert_eq!(tp.len(), 40);
        assert!(tp.bytes().all(|b| b.is_ascii_hexdigit()));
        assert!(tp.bytes().all(|b| !b.is_ascii_lowercase()));
    }

    #[test]
    fn rcgen_cert_honors_cert_years() {
        let gen = generate_self_signed("CN=Ubuntu-GUI RDP", 10).unwrap();
        assert_eq!(gen.validity_days, 3650);
        let gen1 = generate_self_signed("CN=Ubuntu-GUI RDP", 1).unwrap();
        assert_eq!(gen1.validity_days, 365);
    }
}
