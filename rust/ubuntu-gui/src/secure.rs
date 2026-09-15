//! Senha em memoria (`ConvertFrom-SecureStringPlain.ps1`).
//!
//! SSOT da conversao (antes copiada 3x no Install): `PtrToStringUni` +
//! `ZeroFreeBSTR` juntos — sem o `ZeroFreeBSTR` a senha ficava no BSTR alem
//! do necessario. Aqui o buffer e zerado no `Drop` (crate `zeroize`), que e
//! o equivalente Rust do `ZeroFreeBSTR` imediato.

use zeroize::Zeroize;

/// Equivalente ao `SecureString`: guarda a senha e zera ao descartar.
#[derive(Debug, Default)]
pub struct SecureStr {
    secret: String,
}

impl SecureStr {
    /// Guarda uma senha (uso imediato, sem log — como no Install).
    pub fn new(secret: impl Into<String>) -> Self {
        Self {
            secret: secret.into(),
        }
    }

    /// Converte em texto puro para embutir no bash.
    ///
    /// Equivale a `ConvertFrom-SecureStringPlain`: `$null`/vazio vira `""`.
    pub fn expose(&self) -> &str {
        &self.secret
    }

    /// Apaga agora (alem do `Drop` automatico).
    pub fn clear(&mut self) {
        self.secret.zeroize();
        self.secret.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.secret.is_empty()
    }

    pub fn len(&self) -> usize {
        self.secret.len()
    }
}

impl Drop for SecureStr {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

impl From<&str> for SecureStr {
    fn from(s: &str) -> Self {
        Self::new(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_preserves_password() {
        let s = SecureStr::new("s3nh@!");
        assert_eq!(s.expose(), "s3nh@!");
    }

    #[test]
    fn empty_stays_empty() {
        let s = SecureStr::default();
        assert_eq!(s.expose(), "");
        assert!(s.is_empty());
        let none: Option<SecureStr> = None;
        assert_eq!(none.as_ref().map_or("", |s| s.expose()), "");
    }

    #[test]
    fn clear_empties_buffer() {
        let mut s = SecureStr::new("segredo");
        s.clear();
        assert_eq!(s.expose(), "");
        assert!(s.is_empty());
    }
}
