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

/// Cano comum: script em base64 (alfabeto shell-safe) ate o `bash -s`.
fn helper_pipe() -> String {
    format!(
        "echo {} | base64 -d |",
        base64_encode(HELPER_SCRIPT.as_bytes())
    )
}

/// Monta `echo <b64> | base64 -d | <env> bash -s <sub> <args>`.
pub fn helper_invoke_command(uid: &str, subcommand: &str, args: &str) -> String {
    let args = if args.is_empty() {
        String::new()
    } else {
        format!(" {args}")
    };
    format!(
        "{} {} bash -s {subcommand}{args}",
        helper_pipe(),
        crate::vault::session_env(uid)
    )
}

/// `mirror-rank <urls...>`: sem env (curl puro, sem bus).
pub fn mirror_rank_command(mirrors: &[String]) -> String {
    format!("{} bash -s mirror-rank {}", helper_pipe(), mirrors.join(" "))
}

/// `mirror-set <url> '<pwq>'`: sem env (sudo+sed, sem bus).
pub fn mirror_set_command(password_quote: &str, url: &str) -> String {
    format!(
        "{} bash -s mirror-set {url} '{password_quote}'",
        helper_pipe()
    )
}

/// Escolhe o menor tempo entre linhas `TIME <secs> <url>` (FAIL/lixo fora;
/// empate = primeira; tudo-falha = None). Decisao em Rust testavel; o bash
/// so mede.
pub fn pick_fastest_mirror(out: &str) -> Option<(String, f64)> {
    let mut best: Option<(String, f64)> = None;
    for line in out.lines() {
        let Some(rest) = line.strip_prefix("TIME ") else {
            continue;
        };
        let mut parts = rest.splitn(2, ' ');
        let (Some(secs_str), Some(url)) = (parts.next(), parts.next()) else {
            continue;
        };
        if url.trim().is_empty() {
            continue;
        }
        let Ok(secs) = secs_str.parse::<f64>() else {
            continue;
        };
        let replace = match &best {
            Some((_, t)) => secs < *t,
            None => true,
        };
        if replace {
            best = Some((url.to_string(), secs));
        }
    }
    best
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

    #[test]
    fn script_has_mirror_subcommands() {
        for sub in ["mirror-rank)", "mirror-set)"] {
            assert!(HELPER_SCRIPT.contains(sub), "falta subcomando {sub}");
        }
    }

    #[test]
    fn mirror_rank_is_read_only_and_bounded() {
        let body = HELPER_SCRIPT
            .split("mirror-rank)")
            .nth(1)
            .unwrap_or("")
            .split("mirror-set)")
            .next()
            .unwrap_or("");
        assert!(body.contains("curl"), "rank mede de verdade");
        assert!(body.contains("--max-time"), "rank com teto de tempo");
        assert!(body.contains("VERSION_CODENAME"), "codename nativo");
        assert!(!body.contains("sudo"), "rank nao escreve nada");
        assert!(!body.contains("sed -i"), "rank nao escreve nada");
    }

    #[test]
    fn mirror_set_backs_up_and_covers_both_formats() {
        let body = HELPER_SCRIPT
            .split("mirror-set)")
            .nth(1)
            .unwrap_or("")
            .split("version)")
            .next()
            .unwrap_or("");
        assert!(body.contains(".bak-"), "backup antes de trocar");
        assert!(body.contains("sed -i"), "troca inplace");
        assert!(body.contains("ubuntu.sources"), "formato DEB822");
        assert!(body.contains("sources.list"), "formato legado");
        assert!(body.contains("sudo -S"), "sudo nao interativo");
    }

    #[test]
    fn pick_fastest_ignores_failures_and_picks_min() {
        let out = "TIME 1.280882 http://archive.ubuntu.com/ubuntu\nTIME FAIL http://morto/x\nTIME 0.139701 http://br.archive.ubuntu.com/ubuntu\nlixo\nTIME\n";
        let (url, secs) = pick_fastest_mirror(out).unwrap();
        assert_eq!(url, "http://br.archive.ubuntu.com/ubuntu");
        assert!((secs - 0.139701).abs() < 1e-9);
    }

    #[test]
    fn pick_fastest_fail_closed() {
        assert_eq!(pick_fastest_mirror(""), None);
        assert_eq!(pick_fastest_mirror("TIME FAIL a\nTIME FAIL b\n"), None);
        assert_eq!(pick_fastest_mirror("nada a ver\n"), None);
    }

    #[test]
    fn pick_fastest_tie_keeps_first() {
        let out = "TIME 0.5 http://a/x\nTIME 0.5 http://b/x\n";
        assert_eq!(
            pick_fastest_mirror(out).unwrap().0,
            "http://a/x"
        );
    }

    #[test]
    fn mirror_builders_shape() {
        let rank = mirror_rank_command(&[
            "http://a/ubuntu".to_string(),
            "http://b/ubuntu".to_string(),
        ]);
        assert!(rank.contains("bash -s mirror-rank http://a/ubuntu http://b/ubuntu"));
        assert!(!rank.contains("XDG_RUNTIME_DIR"), "rank nao precisa do bus");
        let set = mirror_set_command("pw", "http://b/ubuntu");
        assert!(set.ends_with("bash -s mirror-set http://b/ubuntu 'pw'"));
    }
}
