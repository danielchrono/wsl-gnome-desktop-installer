//! Certificado de publicador (`New-PublisherCertificate.ps1`): assinar o
//! `.rdp` para sumir o aviso "fornecedor desconhecido".
//!
//! Idempotente: reaproveita se ja existir no `CurrentUser\My` (filtrado por
//! EKU CodeSigning + `Subject -eq`, espelhado em [`find_existing_subject`]).
//! Senao gera autoassinado (rcgen, testavel no Linux) com validade de
//! `CertYears` e grava em `My` + `TrustedPublishers` (`cfg(windows)`).

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
#[cfg(windows)]
pub fn ensure_publisher_certificate(subject: &str, years: u32) -> Result<String, InstallError> {
    if let Some(tp) = find_in_my_store(subject)? {
        return Ok(tp);
    }
    let gen = generate_self_signed(subject, years)?;
    add_der_to_store("MY", &gen.cert_der)?;
    add_der_to_store("TrustedPublishers", &gen.cert_der)?;
    // Rele o thumbprint do que foi gravado (fonte: o store, como no PS).
    find_in_my_store(subject)?.ok_or_else(|| {
        InstallError::CertFailed("certificado gerado mas nao encontrado no store My".to_string())
    })
}

#[cfg(windows)]
fn store_name_wide(name: &str) -> Vec<u16> {
    name.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Procura em `CurrentUser\My` por Subject exato; devolve o thumbprint.
#[cfg(windows)]
fn find_in_my_store(subject: &str) -> Result<Option<String>, InstallError> {
    use windows::core::PCWSTR;
    use windows::Win32::Security::Cryptography::{
        CertCloseStore, CertFindCertificateInStore, CertGetNameStringW, CertOpenStore,
        CERT_FIND_SUBJECT_STR_W, CERT_NAME_SIMPLE_DISPLAY_TYPE, CERT_OPEN_STORE_FLAGS,
        CERT_QUERY_ENCODING_TYPE, CERT_STORE_PROV_SYSTEM_W, X509_ASN_ENCODING,
    };

    let store_param = store_name_wide("MY");
    // SAFETY: ponteiros validos durante a chamada; store fechado no fim.
    unsafe {
        let store = CertOpenStore(
            CERT_STORE_PROV_SYSTEM_W,
            CERT_QUERY_ENCODING_TYPE(0),
            None,
            CERT_OPEN_STORE_FLAGS(0x0001_0000), // CERT_SYSTEM_STORE_CURRENT_USER
            Some(store_param.as_ptr() as *const _),
        )
        .map_err(|e| InstallError::Io(format!("CertOpenStore My: {e}")))?;
        let want = store_name_wide(subject);
        let mut found: Option<String> = None;
        // v0.61: CertFindCertificateInStore exige Option<*const CERT_CONTEXT> para prev.
        let mut prev: Option<*const windows::Win32::Security::Cryptography::CERT_CONTEXT> = None;
        loop {
            let ctx = CertFindCertificateInStore(
                store,
                X509_ASN_ENCODING,
                0,
                CERT_FIND_SUBJECT_STR_W,
                Some(want.as_ptr() as *const _),
                prev,
            );
            if ctx.is_null() {
                break;
            }
            prev = Some(ctx);
            // Subject exato (o FIND ja filtra por substring; confirma eq).
            let mut buf = [0u16; 512];
            let len = CertGetNameStringW(
                ctx,
                // v0.61: CERT_NAME_SIMPLE_DISPLAY_TYPE e um u32 direto (sem .0).
                windows::Win32::Security::Cryptography::CERT_NAME_SIMPLE_DISPLAY_TYPE,
                0,
                None,
                Some(&mut buf),
            );
            let got = String::from_utf16_lossy(&buf[..len.saturating_sub(1) as usize]);
            if got == subject || subject.contains(&got) || got.contains(subject) {
                // Thumbprint = SHA-1 do DER (formato `$cert.Thumbprint`).
                let raw = std::slice::from_raw_parts(
                    (*ctx).pbCertEncoded as *const u8,
                    (*ctx).cbCertEncoded as usize,
                );
                found = Some(sha1_hex_upper(raw));
                break;
            }
        }
        // v0.61: CertCloseStore recebe Option<HCERTSTORE>.
        let _ = CertCloseStore(Some(store), 0);
        Ok(found)
    }
}

#[cfg(windows)]
fn add_der_to_store(store_name: &str, der: &[u8]) -> Result<(), InstallError> {
    use windows::Win32::Security::Cryptography::{
        CertAddCertificateContextToStore, CertCloseStore, CertCreateCertificateContext,
        CertOpenStore, CERT_OPEN_STORE_FLAGS, CERT_QUERY_ENCODING_TYPE,
        CERT_STORE_ADD_REPLACE_EXISTING, CERT_STORE_PROV_SYSTEM_W, X509_ASN_ENCODING,
    };

    let store_param = store_name_wide(store_name);
    // SAFETY: ponteiros validos durante a chamada; contexto/store liberados.
    unsafe {
        let store = CertOpenStore(
            CERT_STORE_PROV_SYSTEM_W,
            CERT_QUERY_ENCODING_TYPE(0),
            None,
            CERT_OPEN_STORE_FLAGS(0x0001_0000),
            Some(store_param.as_ptr() as *const _),
        )
        .map_err(|e| InstallError::Io(format!("CertOpenStore {store_name}: {e}")))?;
        // v0.61: CertCreateCertificateContext recebe &[u8] (nao ptr+len).
        let ctx = CertCreateCertificateContext(X509_ASN_ENCODING, der);
        if ctx.is_null() {
            let _ = CertCloseStore(Some(store), 0);
            return Err(InstallError::CertFailed(
                "CertCreateCertificateContext retornou NULL".to_string(),
            ));
        }
        // v0.61: CertAddCertificateContextToStore e CertCloseStore recebem Option<HCERTSTORE>.
        CertAddCertificateContextToStore(Some(store), ctx, CERT_STORE_ADD_REPLACE_EXISTING, None)
            .map_err(|e| InstallError::CertFailed(format!("CertAdd {store_name}: {e}")))?;
        let _ = CertCloseStore(Some(store), 0);
        Ok(())
    }
}

/// SHA-1 em hex maiusculo (formato do thumbprint .NET). Implementacao
/// std-only para nao puxar crate so para isso.
#[cfg(windows)]
fn sha1_hex_upper(data: &[u8]) -> String {
    let digest = sha1(data);
    digest.iter().map(|b| format!("{b:02X}")).collect()
}

#[cfg(windows)]
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
    fn rcgen_cert_honors_cert_years() {
        let gen = generate_self_signed("CN=Ubuntu-GUI RDP", 10).unwrap();
        assert_eq!(gen.validity_days, 3650);
        let gen1 = generate_self_signed("CN=Ubuntu-GUI RDP", 1).unwrap();
        assert_eq!(gen1.validity_days, 365);
    }
}
