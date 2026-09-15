//! Gestor de cofre (`Invoke-VaultCredential.ps1`): credencial RDP no
//! Secret Service via gnome-keyring/grdctl.
//!
//! Todo acesso ao cofre passa por aqui: elimina a duplicacao entre Install
//! (etapa 5) e `Get-WslUbuntuGuiStatus` e nunca engole resultado. I/O com o
//! daemon fica nas fronteiras `*_live`; retry e mensagens ficam na View.
//! Construtores de comando + parsers sao puros (cobertos sem WSL).

use crate::error::InstallError;
use crate::wsl_cmd;

/// `New-WslSessionEnv`: XDG + bus da sessao do usuario.
pub fn session_env(uid: &str) -> String {
    format!(
        "XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
    )
}

/// Comando de `Unlock-WslKeyring`.
///
/// `PIPESTATUS[1]` e o exit do unlock (sem ele, o `tail` mascarava tudo
/// com 0). `!= 0` = senha nao confere ou daemon fora: o chamador falha
/// rapido com instrucao (nunca retry cego que queima 2x60s).
pub fn unlock_keyring_command(password_quote: &str, uid: &str) -> String {
    format!(
        "printf '%s' '{password_quote}' | {} gnome-keyring-daemon --unlock 2>&1 | tail -n 3; exit ${{PIPESTATUS[1]}}",
        session_env(uid)
    )
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

/// Parser puro da sonda (`Test-UnlockedPropertyOutput`): fail-closed, so
/// `b false` prova destravado.
pub fn is_unlocked_property_output(out: &str) -> bool {
    out.contains("b false")
}

/// Comando de `Test-WslKeyringUnlocked`: sonda sem prompt — colecao
/// `default` destravada? Le a propriedade Locked via busctl (retorna na
/// hora, nunca abre prompt). Qualquer duvida = `false`: melhor falhar rapido
/// com instrucao do que travar 60s no set-credentials.
pub fn keyring_unlocked_command(uid: &str) -> String {
    format!(
        "{} busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>/dev/null",
        session_env(uid)
    )
}

/// Fronteiras de I/O (executam via `Invoke-Wsl`; `cfg(windows)` real,
/// fora dele erro tipado). Chamadores decidem Ok/Fail/throw.
pub fn unlock_keyring_live(
    linux_user: &str,
    password_quote: &str,
    uid: &str,
) -> Result<wsl_cmd::WslResult, InstallError> {
    wsl_cmd::invoke_wsl(
        None,
        linux_user,
        &unlock_keyring_command(password_quote, uid),
    )
}

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
    fn unlock_keeps_pipestatus_exit() {
        let cmd = unlock_keyring_command("pw", "1000");
        assert!(cmd.contains("gnome-keyring-daemon --unlock"));
        assert!(cmd.contains("exit ${PIPESTATUS[1]}"));
        assert!(cmd.contains("XDG_RUNTIME_DIR=/run/user/1000"));
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

    #[test]
    fn only_b_false_proves_unlocked_fail_closed() {
        assert!(is_unlocked_property_output("b false"));
        assert!(!is_unlocked_property_output("b true"));
        assert!(!is_unlocked_property_output(""));
        assert!(!is_unlocked_property_output(
            "Failed to get property: No such interface"
        ));
    }
}
