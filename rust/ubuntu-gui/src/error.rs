//! Erros tipados do instalador: um por `throw` de `Install-WslUbuntuGui`.
//!
//! As mensagens (`Display`) sao byte-identicas as strings dos `throw`
//! PowerShell, porque `entry-tail.ps1` imprime `FALHA: <mensagem>` e sai
//! com codigo 1. `exit_code()` espelha isso: 0 = OK/TUDO-PRONTO (e tambem o
//! bare `return` da etapa 1 que precisa de reboot), 1 = FALHA.

use std::fmt;

/// Todos os throws de `Install-WslUbuntuGui.ps1` + falhas de infra do port.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallError {
    /// `throw "Usuario reservado"`
    ReservedUser,
    /// `throw "Usuario Linux invalido"`
    InvalidLinuxUser,
    /// `throw "Senhas diferentes ou vazias"`
    PasswordMismatch,
    /// `throw "Distro nao inicia"`
    DistroNotStarting,
    /// `throw "Senha nao atualizada"`
    PasswordNotUpdated,
    /// `throw "systemd nao subiu"`
    SystemdDown,
    /// `throw "APT falhou"`
    AptFailed,
    /// `throw "Shell nao subiu"`
    ShellDown,
    /// `throw "Cofre nao criado"`
    KeyringMissing,
    /// `throw "Cofre bloqueado"`
    KeyringLocked,
    /// `throw "Cofre ausente"` (daemon sem colecao login: restaurar backup)
    KeyringAbsent,
    /// `throw "Credencial nao gravada"`
    CredentialNotStored,
    /// `throw "RDP nao subiu"`
    RdpDown,
    /// `throw "RDP nao criado"`
    RdpNotCreated,
    /// `throw "Atalhos nao criados"`
    ShortcutsMissing,
    /// `throw "RDP sumiu"`
    RdpVanished,
    /// `throw "Instalacao terminou com falhas"`
    FinishedWithFailures,
    /// `throw` com mensagem dinamica (`Fail "Nao criei o usuario: ..."`).
    Dynamic(String),
    /// I/O local (arquivos, registro, processo filho).
    Io(String),
    /// Recurso so existe no Windows (wsl.exe, DPAPI, cert store, RunOnce).
    NotSupportedOnLinux(&'static str),
    /// Estado de retomada ilegivel (vira `Warn`, nao throw, no fluxo normal;
    /// erro tipado para o modo `--resume <arquivo>` falhar alto).
    ResumeUnreadable(String),
    /// Falha ao gerar/gravar certificado de publicador.
    CertFailed(String),
}

impl InstallError {
    /// Nome estavel do erro (para goldens e logs).
    pub fn name(&self) -> &'static str {
        match self {
            Self::ReservedUser => "Usuario reservado",
            Self::InvalidLinuxUser => "Usuario Linux invalido",
            Self::PasswordMismatch => "Senhas diferentes ou vazias",
            Self::DistroNotStarting => "Distro nao inicia",
            Self::PasswordNotUpdated => "Senha nao atualizada",
            Self::SystemdDown => "systemd nao subiu",
            Self::AptFailed => "APT falhou",
            Self::ShellDown => "Shell nao subiu",
            Self::KeyringMissing => "Cofre nao criado",
            Self::KeyringLocked => "Cofre bloqueado",
            Self::KeyringAbsent => "Cofre ausente",
            Self::CredentialNotStored => "Credencial nao gravada",
            Self::RdpDown => "RDP nao subiu",
            Self::RdpNotCreated => "RDP nao criado",
            Self::ShortcutsMissing => "Atalhos nao criados",
            Self::RdpVanished => "RDP sumiu",
            Self::FinishedWithFailures => "Instalacao terminou com falhas",
            Self::Dynamic(_) => "dynamic",
            Self::Io(_) => "io",
            Self::NotSupportedOnLinux(_) => "not-supported-on-linux",
            Self::ResumeUnreadable(_) => "resume-unreadable",
            Self::CertFailed(_) => "cert-failed",
        }
    }

    /// Exit code do processo (`entry-tail.ps1`: 0 ok, 1 `FALHA`).
    pub fn exit_code(&self) -> i32 {
        let _ = self;
        1
    }
}

impl fmt::Display for InstallError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Dynamic(m) | Self::Io(m) | Self::ResumeUnreadable(m) | Self::CertFailed(m) => {
                write!(f, "{m}")
            }
            Self::NotSupportedOnLinux(what) => {
                write!(f, "{what} exige Windows (wsl.exe/DPAPI indisponivel)")
            }
            other => write!(f, "{}", other.name()),
        }
    }
}

impl std::error::Error for InstallError {}

impl From<std::io::Error> for InstallError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}

impl From<serde_json::Error> for InstallError {
    fn from(e: serde_json::Error) -> Self {
        Self::ResumeUnreadable(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_throw_names_match_powershell() {
        let cases = [
            (InstallError::ReservedUser, "Usuario reservado"),
            (InstallError::InvalidLinuxUser, "Usuario Linux invalido"),
            (
                InstallError::PasswordMismatch,
                "Senhas diferentes ou vazias",
            ),
            (InstallError::DistroNotStarting, "Distro nao inicia"),
            (InstallError::PasswordNotUpdated, "Senha nao atualizada"),
            (InstallError::SystemdDown, "systemd nao subiu"),
            (InstallError::AptFailed, "APT falhou"),
            (InstallError::ShellDown, "Shell nao subiu"),
            (InstallError::KeyringMissing, "Cofre nao criado"),
            (InstallError::KeyringLocked, "Cofre bloqueado"),
            (InstallError::KeyringAbsent, "Cofre ausente"),
            (InstallError::CredentialNotStored, "Credencial nao gravada"),
            (InstallError::RdpDown, "RDP nao subiu"),
            (InstallError::RdpNotCreated, "RDP nao criado"),
            (InstallError::ShortcutsMissing, "Atalhos nao criados"),
            (InstallError::RdpVanished, "RDP sumiu"),
            (
                InstallError::FinishedWithFailures,
                "Instalacao terminou com falhas",
            ),
        ];
        for (err, want) in cases {
            assert_eq!(err.to_string(), want, "display de {:?}", err);
            assert_eq!(err.name(), want);
            assert_eq!(err.exit_code(), 1);
        }
    }

    #[test]
    fn dynamic_carries_message() {
        let e = InstallError::Dynamic("Nao criei o usuario: x".to_string());
        assert_eq!(e.to_string(), "Nao criei o usuario: x");
        assert_eq!(e.exit_code(), 1);
    }
}
