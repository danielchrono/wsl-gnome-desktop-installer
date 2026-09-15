//! Helper bash embarcado (`wsl_helper.sh`, via `include_str!`): os 4
//! subcomandos quentes do cofre numa unica fronteira de quoting.
//!
//! Transporte: `echo <base64> | base64 -d | <env> bash -s <sub> [args]`
//! (alfabeto base64 e shell-safe; sem stdin, sem `wsl_cmd` novo). Parsers
//! continuam em [`crate::vault`] sobre a saida identica aos inline.
//! Regra anti-suicidio: pkill e `--login` nunca dividem a chamada
//! (o padrao `[g]...` com o literal na mesma linha mata o proprio shell).

/// Versao do contrato (script marca `UBUNTUGUI_HELPER_VERSION`).
pub const HELPER_VERSION: u32 = 1;

/// Texto do helper (goldens travam subcomandos, `set -u` e sem-CRLF).
pub const HELPER_SCRIPT: &str = include_str!("wsl_helper.sh");

/// Le `UBUNTUGUI_HELPER_VERSION=N` do texto (gate de versao).
pub fn helper_version(script: &str) -> Option<u32> {
    for line in script.lines() {
        let Some(rest) = line.trim().strip_prefix("UBUNTUGUI_HELPER_VERSION=") else {
            continue;
        };
        let rest = rest.trim().trim_matches('"');
        if rest.starts_with('$') || rest.is_empty() {
            continue;
        }
        if let Ok(n) = rest.parse::<u32>() {
            return Some(n);
        }
    }
    None
}

/// `true` quando o script embarcado e o contrato desta versao.
pub fn script_is_current() -> bool {
    helper_version(HELPER_SCRIPT) == Some(HELPER_VERSION)
}

const B64_ALPHABET: &[u8; 64] =
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// base64 puro (sem deps): so o transporte do helper precisa dele.
pub fn base64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(B64_ALPHABET[((n >> 18) & 63) as usize] as char);
        out.push(B64_ALPHABET[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            B64_ALPHABET[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            B64_ALPHABET[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

/// Monta `echo <b64> | base64 -d | <env> bash -s <sub> <args>`.
pub fn helper_invoke_command(uid: &str, subcommand: &str, args: &str) -> String {
    let blob = base64_encode(HELPER_SCRIPT.as_bytes());
    let args = if args.is_empty() {
        String::new()
    } else {
        format!(" {args}")
    };
    format!(
        "echo {blob} | base64 -d | {} bash -s {subcommand}{args}",
        crate::vault::session_env(uid)
    )
}

/// `probe` diagnostico (2>&1 dentro do script).
pub fn helper_probe_command(uid: &str) -> String {
    helper_invoke_command(uid, "probe", "")
}

/// `unlock-probe` mesma-chamada (senha ja escapada por `passquote`).
pub fn helper_unlock_probe_command(password_quote: &str, uid: &str) -> String {
    helper_invoke_command(uid, "unlock-probe", &format!("'{password_quote}'"))
}

/// `login-create` (cria + destravado; pkill fica na chamada anterior).
pub fn helper_login_create_command(password_quote: &str, uid: &str) -> String {
    helper_invoke_command(uid, "login-create", &format!("'{password_quote}'"))
}

/// `keyring-check` OK/MISSING.
pub fn helper_keyring_check_command(uid: &str, keyring_path: &str) -> String {
    helper_invoke_command(uid, "keyring-check", keyring_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_gate_matches_script() {
        assert_eq!(helper_version(HELPER_SCRIPT), Some(HELPER_VERSION));
        assert_eq!(helper_version("sem nada"), None);
        assert_eq!(helper_version("UBUNTUGUI_HELPER_VERSION=x"), None);
    }

    #[test]
    fn script_is_current_and_well_formed() {
        assert!(script_is_current());
        assert!(HELPER_SCRIPT.contains("set -u"));
        assert!(!HELPER_SCRIPT.contains('\r'), "CRLF quebraria o pipe");
        for sub in [
            "probe)",
            "unlock-probe)",
            "login-create)",
            "keyring-check)",
            "version)",
        ] {
            assert!(HELPER_SCRIPT.contains(sub), "falta subcomando {sub}");
        }
    }

    #[test]
    fn login_create_has_no_pkill_anti_suicide() {
        let body = HELPER_SCRIPT
            .split("login-create)")
            .nth(1)
            .unwrap_or("")
            .split("keyring-check)")
            .next()
            .unwrap_or("");
        assert!(
            !body.contains("pkill") && !body.contains("pgrep"),
            "pkill no login-create mataria o proprio shell"
        );
    }

    #[test]
    fn base64_vectors() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn invoke_shape_single_quoting_boundary() {
        let cmd = helper_probe_command("1000");
        assert!(cmd.starts_with("echo "));
        assert!(cmd.contains(" | base64 -d | "));
        assert!(cmd.contains("XDG_RUNTIME_DIR=/run/user/1000"));
        assert!(cmd.ends_with("bash -s probe"));
        let cmd = helper_unlock_probe_command("pw", "1000");
        assert!(cmd.ends_with("bash -s unlock-probe 'pw'"));
    }
}
