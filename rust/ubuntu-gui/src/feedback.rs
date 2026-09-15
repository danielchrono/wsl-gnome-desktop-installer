//! View de feedback (`Write-Feedback.ps1`): so render no console, sem decisao.
//!
//! O estado de falhas vive no ViewModel (`Install-WslUbuntuGui`, variavel
//! local); `$script:Failures` segue como compat legada espelhada. Aqui o
//! estado e explicito e imutavel por copia: [`FeedbackState`] nunca e mutado,
//! [`FeedbackState::with_failure`] retorna um novo valor.

/// Estado explicito de falhas (FP): hashtable imutavel por copia.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FeedbackState {
    failures: Vec<String>,
}

impl FeedbackState {
    /// `New-UbuntuGuiFeedbackState`.
    pub fn new() -> Self {
        Self::default()
    }

    /// `Add-UbuntuGuiFailure`: retorna NOVO estado; o original nao muda.
    pub fn with_failure(&self, message: impl Into<String>) -> Self {
        let mut failures = self.failures.clone();
        failures.push(message.into());
        Self { failures }
    }

    /// `Get-UbuntuGuiFailures`.
    pub fn failures(&self) -> &[String] {
        &self.failures
    }

    pub fn has_failures(&self) -> bool {
        !self.failures.is_empty()
    }
}

/// `Step`: `Write-Host "`n==> $msg" -ForegroundColor Cyan`.
pub fn step(msg: &str) -> String {
    format!("\n==> {msg}")
}

/// `Ok`: `Write-Host "  [OK] $msg" -ForegroundColor Green`.
pub fn ok(msg: &str) -> String {
    format!("  [OK] {msg}")
}

/// `Warn`: `Write-Host "  [AVISO] $msg" -ForegroundColor Yellow`.
pub fn warn(msg: &str) -> String {
    format!("  [AVISO] {msg}")
}

/// `Fail`: `Write-Host "  [FALHA] $msg" -ForegroundColor Red` (+ acumula).
pub fn fail(state: &FeedbackState, msg: &str) -> (String, FeedbackState) {
    (format!("  [FALHA] {msg}"), state.with_failure(msg))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accumulates_by_copy_without_mutating_original() {
        let s0 = FeedbackState::new();
        let s1 = s0.with_failure("a");
        assert!(s0.failures().is_empty(), "original mutou");
        assert_eq!(s1.failures(), &["a".to_string()]);
        let s2 = s1.with_failure("b");
        assert_eq!(s2.failures(), &["a".to_string(), "b".to_string()]);
        assert_eq!(s1.failures(), &["a".to_string()]);
    }

    #[test]
    fn render_prefixes_match_powershell() {
        assert_eq!(step("x"), "\n==> x");
        assert_eq!(ok("x"), "  [OK] x");
        assert_eq!(warn("x"), "  [AVISO] x");
        let (line, st) = fail(&FeedbackState::new(), "x");
        assert_eq!(line, "  [FALHA] x");
        assert_eq!(st.failures(), &["x".to_string()]);
    }
}
