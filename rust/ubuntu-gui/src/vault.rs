//! Gestor de cofre (`Invoke-VaultCredential.ps1` + conquistas da saga):
//! credencial RDP no Secret Service via gnome-keyring/grdctl.
//!
//! Todo acesso ao cofre passa por aqui; retry e mensagens ficam na View
//! (`install`). Construtores + parsers sao puros (cobertos sem WSL); I/O
//! com o daemon fica nas fronteiras `*_live`.
//!
//! Conquistas espelhadas:
//!
//! - sonda em 4 estados (`Unlocked`/`Locked`/`Missing`/`Error`): daemon que
//!   responde sem colecao `login` nao e "daemon fora" (pede restaurar backup,
//!   nao mexer no D-Bus);
//! - criacao via `daemon --daemonize --login` (sem `sudo`, sem `pam.d`,
//!   ja sai destravado; provado ao vivo);
//! - recriacao com backup timestampado + restore automatico (nunca `rm`);
//! - unlock+sonda na MESMA chamada (daemon efemero) com marcadores
//!   `UBUNTUGUI_*`; fail-fast, sem retry cego.

use crate::error::InstallError;
use crate::helper;
use crate::wsl_cmd;

/// `New-WslSessionEnv`: XDG + bus da sessao do usuario.
pub fn session_env(uid: &str) -> String {
    format!(
        "XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
    )
}

/// Estado da sonda (`Get-WslKeyringProbeState`): fail-closed como no PS.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeState {
    Unlocked,
    Locked,
    Missing,
    Error,
}

/// `Test-MissingCollectionOutput`: o daemon RESPONDEU mas nao expoe a
/// colecao (arquivo sumiu ou daemon anterior a ele). Textos observados ao
/// vivo no `busctl` 50.0. Fail-closed: qualquer outro texto nao e Missing.
pub fn is_missing_collection_output(out: &str) -> bool {
    if out.trim().is_empty() {
        return false;
    }
    if out.contains("Unknown object") && out.contains("/aliases/default") {
        return true;
    }
    out.contains("Object does not exist at path") && out.contains("collection/login")
}

/// Parser puro da sonda (`Test-UnlockedPropertyOutput`): fail-closed, so
/// `b false` prova destravado.
pub fn is_unlocked_property_output(out: &str) -> bool {
    out.contains("b false")
}

/// Classifica a sonda: `b false` destravado; `b true` trancado de verdade;
/// Missing = daemon no ar sem colecao; resto = Error (bus fora).
pub fn classify_probe_output(out: &str) -> ProbeState {
    if is_unlocked_property_output(out) {
        ProbeState::Unlocked
    } else if out.contains("b true") {
        ProbeState::Locked
    } else if is_missing_collection_output(out) {
        ProbeState::Missing
    } else {
        ProbeState::Error
    }
}

/// Controle (`Test-WslUnlockExitMeaningful`): senha GARANTIDAMENTE errada
/// (unlock falho nao muda nada). `code != 0` nela = exits significativos.
pub const FALSE_PROBE_PASSWORD: &str = "ubuntugui-sonda-falsa-000";

/// Resultado parseado do unlock+sonda (`UnlockAndProbe-WslKeyring`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnlockProbe {
    pub unlock_code: i64,
    pub probe: String,
    pub unlock_text: String,
    pub state: ProbeState,
}

/// Parser puro do protocolo (`Read-UnlockProbeOutput`): `(codigo, sonda)`.
/// Fail-closed: sem marcador de codigo, `code = -1`.
pub fn parse_unlock_probe_output(out: &str) -> (i64, String) {
    let mut code: i64 = -1;
    let mut probe = String::new();
    for line in out.lines() {
        if let Some(rest) = line.strip_prefix("UBUNTUGUI_UNLOCKCODE=") {
            if let Ok(n) = rest.trim().parse::<i64>() {
                code = n;
            }
        } else if let Some(rest) = line.strip_prefix("UBUNTUGUI_PROBE=") {
            probe = rest.trim().to_string();
        }
    }
    (code, probe)
}

/// Texto do unlock sem os marcadores (`UnlockText`; `(vazio)` se nada sobra).
pub fn unlock_text_output(out: &str) -> String {
    let text: Vec<&str> = out
        .lines()
        .filter(|l| !l.starts_with("UBUNTUGUI_"))
        .collect();
    let joined = text.join("\n").trim().to_string();
    if joined.is_empty() {
        "(vazio)".to_string()
    } else {
        joined
    }
}

/// Unlock + sonda parseados e classificados (mesma ordem do PS).
pub fn classify_unlock_probe(out: &str) -> UnlockProbe {
    let (unlock_code, probe) = parse_unlock_probe_output(out);
    let state = if unlock_code < 0 || probe.trim().is_empty() {
        ProbeState::Error
    } else {
        classify_probe_output(&probe)
    };
    UnlockProbe {
        unlock_code,
        probe,
        unlock_text: unlock_text_output(out),
        state,
    }
}

/// Comando de `Test-WslKeyringUnlocked`: sonda barata sem prompt
/// (pular unlock quando ja destravado). Diagnostico usa o helper `probe`.
pub fn keyring_unlocked_command(uid: &str) -> String {
    format!(
        "{} busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>/dev/null",
        session_env(uid)
    )
}

/// Mata SOMENTE daemons proprios (`Repair` parcial sem root): o padrao
/// `[g]...` nunca divide a linha com o literal (anti-suicidio: pkill com o
/// literal na mesma linha mata o proprio shell - SIGTERM observado).
/// Chamada WSL sempre SEPARADA do `--login`.
pub fn pkill_keyring_command() -> String {
    "pkill -f '[g]nome-keyring-daemon' 2>/dev/null; sleep 1; echo REINICIADO".to_string()
}

/// Prestart (`Start-WslKeyringDaemon`): sobe o daemon como o proprio usuario
/// ANTES de tudo. Idempotente (`--start` com daemon rodando = no-op).
pub fn start_daemon_command(uid: &str) -> String {
    format!(
        "{} gnome-keyring-daemon --start >/dev/null 2>&1",
        session_env(uid)
    )
}

/// `date` do backup timestampado (`Reset-WslLoginKeyring`).
pub fn date_command() -> String {
    "date +%Y%m%d-%H%M%S".to_string()
}

/// `mv` do original para `login.keyring.bak-<ts>` (antes de recriar).
pub fn backup_command(keyring_path: &str, timestamp: &str) -> String {
    format!("mv {keyring_path} {keyring_path}.bak-{timestamp} 2>/dev/null; echo MOVED")
}

/// `mv` de volta (restore automatico quando criar falha).
pub fn restore_command(backup_path: &str, keyring_path: &str) -> String {
    format!("mv {backup_path} {keyring_path} 2>/dev/null; echo RESTORED")
}

/// Comando de `Set-WslRdpCredential`.
///
/// `env` e obrigatorio apos `timeout` (timeout executa o 1o argumento como
/// programa: prefixo `VAR=x` puro falharia).
pub fn set_rdp_credential_command(
    linux_user: &str,
    password_quote: &str,
    uid: &str,
    timeout_sec: u64,
) -> String {
    format!(
        "timeout {timeout_sec} env {} grdctl rdp set-credentials '{linux_user}' '{password_quote}' 2>&1 | tail -n 5",
        session_env(uid)
    )
}

/// Comando de `Test-WslRdpCredential`: verifica de verdade no daemon (o
/// cofre existir nao basta: item vazio tambem conta).
pub fn test_credential_command(uid: &str) -> String {
    format!(
        "{} grdctl status 2>/dev/null | grep -E 'Username:' | grep -qv '(empty)' && echo YES || echo NO",
        session_env(uid)
    )
}

/// Parser de `Test-WslRdpCredential`: `grdctl` responde YES/NO.
pub fn is_credential_set(out: &str) -> bool {
    out.trim() == "YES"
}

// --- fronteiras de I/O (via `Invoke-Wsl`; `cfg(windows)` real) ------------

/// Prestart com espera limitada: `true` se o servico responde no bus em ate
/// ~10s. `false` nunca aborta o chamador (o `--login` tenta mesmo assim).
pub fn start_keyring_daemon_live(
    distro: Option<&str>,
    linux_user: &str,
    uid: &str,
) -> bool {
    let _ = wsl_cmd::invoke_wsl(distro, linux_user, &start_daemon_command(uid));
    for _ in 0..10 {
        if let Ok((state, _)) = probe_state_live(distro, linux_user, uid) {
            if state != ProbeState::Error {
                return true;
            }
        }
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    false
}

/// Sonda diagnostica via helper (`Get-WslKeyringProbeState`).
pub fn probe_state_live(
    distro: Option<&str>,
    linux_user: &str,
    uid: &str,
) -> Result<(ProbeState, String), InstallError> {
    let r = wsl_cmd::invoke_wsl(distro, linux_user, &helper::helper_probe_command(uid))?;
    let out = r.out.trim().to_string();
    Ok((classify_probe_output(&out), out))
}

/// Unlock + sonda na MESMA chamada via helper (`UnlockAndProbe`).
pub fn unlock_and_probe_live(
    distro: Option<&str>,
    linux_user: &str,
    password_quote: &str,
    uid: &str,
) -> Result<UnlockProbe, InstallError> {
    let r = wsl_cmd::invoke_wsl(
        distro,
        linux_user,
        &helper::helper_unlock_probe_command(password_quote, uid),
    )?;
    Ok(classify_unlock_probe(&r.out))
}

/// Sobe daemon NOVO com `--login` (`Start-WslLoginKeyringDaemon`): pkill em
/// chamada separada (anti-suicidio), depois helper `login-create`.
pub fn start_login_daemon_live(
    distro: Option<&str>,
    linux_user: &str,
    password_quote: &str,
    uid: &str,
) -> Result<(bool, ProbeState, String), InstallError> {
    let _ = wsl_cmd::invoke_wsl(distro, linux_user, &pkill_keyring_command())?;
    let r = wsl_cmd::invoke_wsl(
        distro,
        linux_user,
        &helper::helper_login_create_command(password_quote, uid),
    )?;
    let out = r.out.trim().to_string();
    let state = classify_probe_output(&out);
    Ok((state != ProbeState::Error, state, out))
}

/// Cria quando ausente (`New-WslLoginKeyring`): idempotente, sem sudo/pam.d.
pub fn ensure_login_keyring_live(
    distro: Option<&str>,
    linux_user: &str,
    password_quote: &str,
    uid: &str,
    keyring_path: &str,
) -> Result<(bool, bool), InstallError> {
    let r = wsl_cmd::invoke_wsl(
        distro,
        linux_user,
        &helper::helper_keyring_check_command(uid, keyring_path),
    )?;
    if r.out.contains("OK") {
        return Ok((true, false));
    }
    let _ = start_login_daemon_live(distro, linux_user, password_quote, uid)?;
    let r2 = wsl_cmd::invoke_wsl(
        distro,
        linux_user,
        &helper::helper_keyring_check_command(uid, keyring_path),
    )?;
    let created = r2.out.contains("OK");
    Ok((created, created))
}

/// Recria com backup (`Reset-WslLoginKeyring`): restore automatico se falhar.
pub fn reset_login_keyring_live(
    distro: Option<&str>,
    linux_user: &str,
    password_quote: &str,
    uid: &str,
    keyring_path: &str,
) -> Result<(bool, String), InstallError> {
    let ts = wsl_cmd::invoke_wsl(distro, linux_user, &date_command())?
        .out
        .trim()
        .to_string();
    let backup = format!("{keyring_path}.bak-{ts}");
    let _ = wsl_cmd::invoke_wsl(distro, linux_user, &format!("mv {keyring_path} {backup} 2>/dev/null; echo MOVED"))?;
    let (created, _) =
        ensure_login_keyring_live(distro, linux_user, password_quote, uid, keyring_path)?;
    if !created {
        let _ = wsl_cmd::invoke_wsl(distro, linux_user, &restore_command(&backup, keyring_path))?;
        return Ok((false, backup));
    }
    Ok((true, backup))
}

/// Fronteiras de I/O do caminho antigo estavel (store/status).
pub fn set_rdp_credential_live(
    linux_user: &str,
    password_quote: &str,
    uid: &str,
    timeout_sec: u64,
) -> Result<wsl_cmd::WslResult, InstallError> {
    wsl_cmd::invoke_wsl(
        None,
        linux_user,
        &set_rdp_credential_command(linux_user, password_quote, uid, timeout_sec),
    )
}

pub fn test_credential_live(linux_user: &str, uid: &str) -> Result<bool, InstallError> {
    let r = wsl_cmd::invoke_wsl(None, linux_user, &test_credential_command(uid))?;
    Ok(is_credential_set(&r.out))
}

pub fn test_keyring_unlocked_live(linux_user: &str, uid: &str) -> Result<bool, InstallError> {
    let r = wsl_cmd::invoke_wsl(None, linux_user, &keyring_unlocked_command(uid))?;
    Ok(is_unlocked_property_output(&r.out))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_env_shape() {
        assert_eq!(
            session_env("1000"),
            "XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
        );
    }

    #[test]
    fn only_b_false_proves_unlocked_fail_closed() {
        assert!(is_unlocked_property_output("b false"));
        assert!(!is_unlocked_property_output("b true"));
        assert!(!is_unlocked_property_output(""));
        assert!(!is_unlocked_property_output(
            "Failed to get property: No such interface"
        ));
    }

    #[test]
    fn missing_texts_from_live_busctl_50() {
        assert!(is_missing_collection_output(
            "Failed to get property Locked on interface org.freedesktop.Secret.Collection: Unknown object '/org/freedesktop/secrets/aliases/default'."
        ));
        assert!(is_missing_collection_output(
            "Failed to get property Locked on interface org.freedesktop.Secret.Collection: Object does not exist at path \u{201c}/org/freedesktop/secrets/collection/login\u{201d}"
        ));
    }

    #[test]
    fn missing_is_fail_closed() {
        for out in ["b true", "b false", "", "Failed to connect to bus: No such file"] {
            assert!(!is_missing_collection_output(out), "falso Missing: {out}");
        }
    }

    #[test]
    fn probe_states_cover_all_cases() {
        assert_eq!(classify_probe_output("b false"), ProbeState::Unlocked);
        assert_eq!(classify_probe_output("b true"), ProbeState::Locked);
        assert_eq!(
            classify_probe_output("Unknown object '/org/freedesktop/secrets/aliases/default'."),
            ProbeState::Missing
        );
        assert_eq!(
            classify_probe_output("Object does not exist at path /org/freedesktop/secrets/collection/login"),
            ProbeState::Missing
        );
        assert_eq!(
            classify_probe_output("Failed to connect to bus"),
            ProbeState::Error
        );
        assert_eq!(classify_probe_output(""), ProbeState::Error);
    }

    #[test]
    fn unlock_probe_parses_markers_and_classifies() {
        let u = classify_unlock_probe("UBUNTUGUI_UNLOCKCODE=0\nUBUNTUGUI_PROBE=b true");
        assert_eq!(u.unlock_code, 0);
        assert_eq!(u.probe, "b true");
        assert_eq!(u.state, ProbeState::Locked);
        assert_eq!(u.unlock_text, "(vazio)");
        let u = classify_unlock_probe("SSH_AUTH_SOCK=/x\nUBUNTUGUI_UNLOCKCODE=0\nUBUNTUGUI_PROBE=b false");
        assert_eq!(u.state, ProbeState::Unlocked);
        assert_eq!(u.unlock_text, "SSH_AUTH_SOCK=/x");
    }

    #[test]
    fn unlock_probe_without_markers_is_error_fail_closed() {
        let u = classify_unlock_probe("qualquer lixo");
        assert_eq!(u.unlock_code, -1);
        assert_eq!(u.state, ProbeState::Error);
    }

    #[test]
    fn unlock_probe_missing_maps_to_missing() {
        let u = classify_unlock_probe(
            "UBUNTUGUI_UNLOCKCODE=0\nUBUNTUGUI_PROBE=Object does not exist at path /org/freedesktop/secrets/collection/login",
        );
        assert_eq!(u.unlock_code, 0);
        assert_eq!(u.state, ProbeState::Missing);
    }

    #[test]
    fn prestart_is_plain_start_with_env() {
        let cmd = start_daemon_command("1000");
        assert!(cmd.contains("gnome-keyring-daemon --start"));
        assert!(cmd.contains("XDG_RUNTIME_DIR=/run/user/1000"));
        assert!(!cmd.contains("get-property"), "sonda fica na chamada seguinte");
    }

    #[test]
    fn pkill_has_no_literal_anti_suicide() {
        let cmd = pkill_keyring_command();
        assert!(cmd.contains("pkill -f '[g]nome-keyring-daemon'"));
        assert!(
            !cmd.contains("gnome-keyring-daemon --"),
            "literal com o padrao mata o proprio shell"
        );
    }

    #[test]
    fn backup_restore_shapes() {
        assert_eq!(
            backup_command("K", "20260915-000000"),
            "mv K K.bak-20260915-000000 2>/dev/null; echo MOVED"
        );
        assert_eq!(
            restore_command("K.bak-1", "K"),
            "mv K.bak-1 K 2>/dev/null; echo RESTORED"
        );
        assert_eq!(date_command(), "date +%Y%m%d-%H%M%S");
    }

    #[test]
    fn set_credential_uses_timeout_env() {
        let cmd = set_rdp_credential_command("daniel", "pw", "1000", 60);
        assert!(cmd.starts_with("timeout 60 env "));
        assert!(cmd.contains("grdctl rdp set-credentials 'daniel' 'pw'"));
    }

    #[test]
    fn credential_yes_no_parser() {
        assert!(is_credential_set("YES"));
        assert!(is_credential_set("  YES\n"));
        assert!(!is_credential_set("NO"));
        assert!(!is_credential_set(""));
    }
}
