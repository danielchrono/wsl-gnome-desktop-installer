//! SSOT de diagnostico da pipeline (`Write-Feedback.ps1` + `Reporter`).
//!
//! TODO retorno visivel (linha no console, linha no log, acumulo de falha)
//! nasce em [`DiagLog::emit`]: o call site declara `(nivel, codigo, texto)` e
//! o modulo gera os efeitos. Nada de `println!` solto nem vetor de falhas
//! paralelo fora daqui.
//!
//! Formatos de linha byte-identicos ao PowerShell (paridade): os prefixos
//! vivem em [`crate::feedback`] e este modulo so escolhe qual usar.
//!
//! Concorrencia: threads NUNCA emitem direto (embaralharia o log). Cada worker
//! coleta num [`DiagBuf`] e a thread principal despeja com [`DiagLog::drain`]
//! na ordem deterministica do join — o log de um run paralelo sai na mesma
//! ordem do sequencial.

use std::io::Write;

/// Total de etapas da pipeline (cabecalhos `N/7` gerados, nunca digitados).
pub const STEPS_TOTAL: u8 = 7;

/// Nivel do evento (define o prefixo canonico da linha).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Step,
    Ok,
    Warn,
    Fail,
    Info,
}

/// Um retorno da pipeline: nivel + codigo estavel + texto livre.
/// O codigo (`S3_APT_OK`, `S6_RDP_SIGNED`...) e para `grep` no log; o texto
/// segue byte-identico ao PowerShell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diag {
    level: Level,
    code: &'static str,
    text: String,
}

impl Diag {
    pub fn new(level: Level, code: &'static str, text: impl Into<String>) -> Self {
        Self {
            level,
            code,
            text: text.into(),
        }
    }

    pub fn step(code: &'static str, text: impl Into<String>) -> Self {
        Self::new(Level::Step, code, text)
    }

    pub fn ok(code: &'static str, text: impl Into<String>) -> Self {
        Self::new(Level::Ok, code, text)
    }

    pub fn warn(code: &'static str, text: impl Into<String>) -> Self {
        Self::new(Level::Warn, code, text)
    }

    pub fn fail(code: &'static str, text: impl Into<String>) -> Self {
        Self::new(Level::Fail, code, text)
    }

    pub fn info(code: &'static str, text: impl Into<String>) -> Self {
        Self::new(Level::Info, code, text)
    }

    pub fn level(&self) -> Level {
        self.level
    }

    pub fn code(&self) -> &'static str {
        self.code
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    /// Render canonico da linha (paridade byte-identica com o PowerShell).
    pub fn render(&self) -> String {
        match self.level {
            Level::Step => crate::feedback::step(&self.text),
            Level::Ok => crate::feedback::ok(&self.text),
            Level::Warn => crate::feedback::warn(&self.text),
            Level::Fail => {
                let (line, _) =
                    crate::feedback::fail(&crate::feedback::FeedbackState::new(), &self.text);
                line
            }
            Level::Info => self.text.clone(),
        }
    }
}

/// Cabecalho de etapa gerado (`N/7 titulo`): o numero nunca e digitado no
/// call site, entao reordenar/renumerar etapas nao dessincroniza o log.
pub fn step_header(n: u8, title: &str) -> String {
    format!("{n}/{STEPS_TOTAL} {title}")
}

/// Coletor sem console para workers paralelos: acumula eventos e o dono
/// despeja via [`DiagLog::drain`] depois do join (ordem deterministica).
#[derive(Debug, Default)]
pub struct DiagBuf {
    events: Vec<Diag>,
}

impl DiagBuf {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, diag: Diag) {
        self.events.push(diag);
    }

    pub fn events(&self) -> &[Diag] {
        &self.events
    }
}

/// Log da pipeline: console + arquivo + falhas acumuladas (substitui
/// `$script:Failures` + transcript para as nossas linhas; saida de comandos
/// externos nao vai ao log — melhor que o PS, cujo log guardava a senha).
pub struct DiagLog {
    failures: Vec<String>,
    log: Option<std::fs::File>,
}

impl DiagLog {
    pub fn new(log_path: Option<&std::path::Path>) -> Self {
        let log = log_path.and_then(|p| {
            if let Some(parent) = p.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(p)
                .ok()
        });
        Self {
            failures: Vec::new(),
            log,
        }
    }

    /// UNICO gerador de retornos: imprime, grava e acumula falha (se `Fail`).
    pub fn emit(&mut self, diag: Diag) {
        let line = diag.render();
        println!("{line}");
        if let Some(f) = self.log.as_mut() {
            let _ = writeln!(f, "{line}");
        }
        if diag.level() == Level::Fail {
            self.failures.push(diag.text().to_string());
        }
    }

    /// Cabecalho de etapa com numero gerado (`begin_step(3, "Pacote")` vira
    /// `3/7 Pacote`; codigo do evento: `S3_BEGIN`).
    pub fn begin_step(&mut self, code: &'static str, n: u8, title: &str) {
        self.emit(Diag::step(code, step_header(n, title)));
    }

    pub fn step(&mut self, msg: &str) {
        self.emit(Diag::step("STEP", msg));
    }

    pub fn ok(&mut self, msg: &str) {
        self.emit(Diag::ok("OK", msg));
    }

    pub fn warn(&mut self, msg: &str) {
        self.emit(Diag::warn("WARN", msg));
    }

    pub fn fail(&mut self, msg: String) {
        self.emit(Diag::fail("FAIL", msg));
    }

    pub fn say(&mut self, line: &str) {
        self.emit(Diag::info("NOTE", line));
    }

    /// Despeja o coletor de um worker ja com join, na ordem de chegada
    /// (o chamador ordena os joins para reproduzir a ordem sequencial).
    pub fn drain(&mut self, buf: DiagBuf) {
        for diag in buf.events {
            self.emit(diag);
        }
    }

    pub fn failures(&self) -> &[String] {
        &self.failures
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_matches_powershell_prefixes() {
        assert_eq!(Diag::step("C", "x").render(), "\n==> x");
        assert_eq!(Diag::ok("C", "x").render(), "  [OK] x");
        assert_eq!(Diag::warn("C", "x").render(), "  [AVISO] x");
        assert_eq!(Diag::fail("C", "x").render(), "  [FALHA] x");
        assert_eq!(Diag::info("C", "raw").render(), "raw");
    }

    #[test]
    fn step_header_numbers_are_generated() {
        assert_eq!(step_header(1, "WSL"), "1/7 WSL");
        assert_eq!(step_header(7, "Fim"), "7/7 Fim");
    }

    #[test]
    fn emit_accumulates_only_failures() {
        let mut log = DiagLog::new(None);
        log.ok("tudo bem");
        assert!(log.failures().is_empty());
        log.warn("quase");
        assert!(log.failures().is_empty());
        log.fail("quebrou".to_string());
        assert_eq!(log.failures(), &["quebrou".to_string()]);
    }

    #[test]
    fn drain_preserves_worker_order_and_failures() {
        let mut log = DiagLog::new(None);
        let mut buf = DiagBuf::new();
        buf.push(Diag::ok("S7_A", "primeiro"));
        buf.push(Diag::fail("S7_B", "segundo"));
        buf.push(Diag::ok("S7_C", "terceiro"));
        log.drain(buf);
        assert_eq!(log.failures(), &["segundo".to_string()]);
    }

    #[test]
    fn codes_travel_with_events() {
        let d = Diag::ok("S3_APT_OK", "instalado");
        assert_eq!(d.code(), "S3_APT_OK");
        assert_eq!(d.level(), Level::Ok);
    }
}
