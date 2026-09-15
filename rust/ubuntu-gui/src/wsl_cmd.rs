//! Roda `wsl -d <distro> ...` repassando o exit code real do Linux
//! (`Invoke-WslCommand.ps1`).
//!
//! O ViewModel passa `-Distro` explicito (FP: sem dinamico). O fallback
//! antigo (variavel `$DISTRO` do chamador > defaults > `'Ubuntu'`) vive em
//! [`resolve_distro`]: explicito > `None`/vazio > `'Ubuntu'`.

use crate::error::InstallError;

/// Resultado de uma chamada WSL: `@{ Code; Out }` com stdout+stderr juntos
/// por linha (o PowerShell junta `2>&1` com `-join "`n"`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WslResult {
    pub code: i32,
    pub out: String,
}

impl WslResult {
    pub fn ok(out: impl Into<String>) -> Self {
        Self {
            code: 0,
            out: out.into(),
        }
    }
}

/// Resolve a distro-alvo: explicita > vazio > `'Ubuntu'`.
pub fn resolve_distro(distro: Option<&str>) -> &str {
    match distro {
        Some(d) if !d.trim().is_empty() => d,
        _ => "Ubuntu",
    }
}

/// Monta o argv de `wsl -d <distro> -u <user> --exec bash -c <cmd>`
/// (puro, testavel sem WSL).
pub fn build_wsl_argv(distro: &str, as_user: &str, command: &str) -> Vec<String> {
    vec![
        "wsl".to_string(),
        "-d".to_string(),
        distro.to_string(),
        "-u".to_string(),
        as_user.to_string(),
        "--exec".to_string(),
        "bash".to_string(),
        "-c".to_string(),
        command.to_string(),
    ]
}

/// `Invoke-Wsl`: so existe onde `wsl.exe` existe.
#[cfg(windows)]
pub fn invoke_wsl(
    distro: Option<&str>,
    as_user: &str,
    command: &str,
) -> Result<WslResult, InstallError> {
    use std::os::windows::process::CommandExt;
    use std::process::Command;

    // CREATE_NO_WINDOW = 0x08000000: sem flash de console no launcher.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let target = resolve_distro(distro);
    let argv = build_wsl_argv(target, as_user, command);
    let output = Command::new("wsl")
        .args(&argv[1..])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(InstallError::from)?;
    let mut combined = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stderr.is_empty() {
        if !combined.is_empty() {
            combined.push('\n');
        }
        combined.push_str(&stderr);
    }
    // PowerShell: `$out -join "`n"` — linhas unidas por LF, sem CR.
    let out = combined.replace("\r\n", "\n").replace('\r', "\n");
    Ok(WslResult {
        code: output.status.code().unwrap_or(1),
        out,
    })
}

/// Fora do Windows nao ha `wsl.exe`: erro tipado em vez de falhar mudo.
#[cfg(not(windows))]
pub fn invoke_wsl(
    _distro: Option<&str>,
    _as_user: &str,
    _command: &str,
) -> Result<WslResult, InstallError> {
    Err(InstallError::NotSupportedOnLinux("Invoke-Wsl (wsl.exe)"))
}

/// `Invoke-WslRoot`: `Invoke-Wsl "root" ...`.
pub fn invoke_wsl_root(distro: Option<&str>, command: &str) -> Result<WslResult, InstallError> {
    invoke_wsl(distro, "root", command)
}

/// Helper do `Get-WslIpAddress`: `wsl -d <distro> -- hostname -I`.
/// (Sem `-u`: usuario padrao da distro.)
#[cfg(windows)]
pub fn run_wsl_simple(distro: &str, command: &str) -> Result<String, InstallError> {
    use std::process::Command;

    let output = Command::new("wsl")
        .args(["-d", distro, "--", "hostname", "-I"])
        .output()
        .map_err(InstallError::from)?;
    let _ = command;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

#[cfg(not(windows))]
pub fn run_wsl_simple(_distro: &str, _command: &str) -> Result<String, InstallError> {
    Err(InstallError::NotSupportedOnLinux(
        "Get-WslIpAddress (wsl.exe)",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distro_fallback_chain() {
        assert_eq!(resolve_distro(Some("Debian")), "Debian");
        assert_eq!(resolve_distro(Some("")), "Ubuntu");
        assert_eq!(resolve_distro(Some("   ")), "Ubuntu");
        assert_eq!(resolve_distro(None), "Ubuntu");
    }

    #[test]
    fn argv_shape() {
        assert_eq!(
            build_wsl_argv("Ubuntu", "root", "id -u"),
            vec!["wsl", "-d", "Ubuntu", "-u", "root", "--exec", "bash", "-c", "id -u"]
                .into_iter()
                .map(String::from)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn ok_constructor() {
        let r = WslResult::ok("active");
        assert_eq!(r.code, 0);
        assert_eq!(r.out, "active");
    }

    #[cfg(not(windows))]
    #[test]
    fn linux_stub_is_typed_error() {
        let e = invoke_wsl(None, "root", "true").unwrap_err();
        assert!(matches!(e, InstallError::NotSupportedOnLinux(_)));
    }
}
