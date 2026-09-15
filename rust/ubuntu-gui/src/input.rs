//! ViewModel puro (`Test-InstallInput.ps1`): validacao sem I/O, sem global,
//! sem WSL. Tudo retorna dados, nunca escreve na tela nem lanca para fluxo
//! normal (o orquestrador decide mensagem/throw). Coberto sem WSL.

/// Resultado de `Test-LinuxUserName`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserNameCheck {
    pub ok: bool,
    pub reason: &'static str,
}

/// `Test-LinuxUserName`: vazio / `root` reservado / `^[a-z_][a-z0-9_-]*$`
/// case-sensitive.
pub fn test_linux_user_name(name: &str) -> UserNameCheck {
    if name.trim().is_empty() {
        return UserNameCheck {
            ok: false,
            reason: "empty",
        };
    }
    if name == "root" {
        return UserNameCheck {
            ok: false,
            reason: "reserved",
        };
    }
    if !is_valid_linux_user_name(name) {
        return UserNameCheck {
            ok: false,
            reason: "pattern",
        };
    }
    UserNameCheck {
        ok: true,
        reason: "",
    }
}

/// Confirmacao de senha: iguais E nao-vazias (vazia confirma com vazia
/// seria "match" - por isso o `!is_empty` explicito).
pub fn passwords_match(first: &str, second: &str) -> bool {
    !first.is_empty() && first == second
}

fn is_valid_linux_user_name(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c == '_' || c.is_ascii_lowercase() => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

/// Escolha de rede normalizada (`Resolve-NetworkChoice`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkChoice {
    pub normalized: String,
    pub want_mirrored: bool,
}

/// Normaliza a escolha de rede do prompt/TUI (`1` = localhost mirrored,
/// `2` = dinamico). Preserva a regra historica: vazio ou qualquer coisa
/// `!= "2"` vira mirrored.
pub fn resolve_network_choice(net_choice: Option<&str>) -> NetworkChoice {
    let norm = match net_choice {
        None => "1".to_string(),
        Some(s) if s.trim().is_empty() => "1".to_string(),
        Some(s) => s.trim().to_string(),
    };
    let norm = if norm.trim().is_empty() {
        "1".to_string()
    } else {
        norm
    };
    NetworkChoice {
        want_mirrored: norm != "2",
        normalized: norm,
    }
}

/// Default do usuario Linux (`Get-DefaultLinuxUser`): salvo entre runs >
/// windows user sanitizado > `"ubuntu"`. Puro.
pub fn default_linux_user(saved_user: Option<&str>, windows_user: Option<&str>) -> String {
    if let Some(saved) = saved_user {
        if !saved.trim().is_empty() {
            return saved.trim().to_string();
        }
    }
    let def: String = windows_user
        .unwrap_or("")
        .to_lowercase()
        .chars()
        .filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        .collect();
    if def.trim().is_empty() {
        "ubuntu".to_string()
    } else {
        def
    }
}

/// Escolha usar-capturado vs criar-novo (`Resolve-UserMenuChoice`, menu TUI,
/// indice 0 = usar). Pura: vazia volta ao padrao; digitado vai como esta
/// (validacao vem depois, sem mudanca).
pub fn resolve_user_menu_choice(
    menu_index: usize,
    typed_name: Option<&str>,
    default_user: &str,
) -> String {
    if menu_index != 1 {
        return default_user.to_string();
    }
    match typed_name {
        Some(t) if !t.trim().is_empty() => t.to_string(),
        _ => default_user.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_valid_name() {
        let c = test_linux_user_name("daniel");
        assert!(c.ok);
        assert_eq!(c.reason, "");
    }

    #[test]
    fn rejects_root_as_reserved() {
        let c = test_linux_user_name("root");
        assert!(!c.ok);
        assert_eq!(c.reason, "reserved");
    }

    #[test]
    fn rejects_uppercase_and_empty() {
        assert!(!test_linux_user_name("Daniel").ok);
        assert_eq!(test_linux_user_name("Daniel").reason, "pattern");
        assert!(!test_linux_user_name("").ok);
        assert_eq!(test_linux_user_name("").reason, "empty");
        assert!(!test_linux_user_name("1abc").ok);
        assert!(test_linux_user_name("_ok-1").ok);
    }

    #[test]
    fn empty_becomes_mirrored_default() {
        let c = resolve_network_choice(Some(""));
        assert!(c.want_mirrored);
        assert_eq!(resolve_network_choice(None).normalized, "1");
        assert_eq!(resolve_network_choice(Some("   ")).normalized, "1");
    }

    #[test]
    fn two_becomes_dynamic() {
        let c = resolve_network_choice(Some("2"));
        assert!(!c.want_mirrored);
        assert_eq!(c.normalized, "2");
    }

    #[test]
    fn prefers_saved_between_runs() {
        assert_eq!(
            default_linux_user(Some("  salvo  "), Some("Daniel")),
            "salvo"
        );
    }

    #[test]
    fn sanitizes_windows_user_and_falls_back_to_ubuntu() {
        assert_eq!(default_linux_user(Some(""), Some("Daniel-1")), "daniel1");
        assert_eq!(default_linux_user(Some(""), Some("---")), "ubuntu");
        assert_eq!(default_linux_user(None, None), "ubuntu");
    }

    #[test]
    fn menu_index_zero_uses_captured() {
        assert_eq!(resolve_user_menu_choice(0, Some("outro"), "salvo"), "salvo");
    }

    #[test]
    fn new_with_name_uses_typed_empty_falls_back() {
        assert_eq!(resolve_user_menu_choice(1, Some("novo1"), "salvo"), "novo1");
        assert_eq!(resolve_user_menu_choice(1, Some("   "), "salvo"), "salvo");
        assert_eq!(resolve_user_menu_choice(1, None, "salvo"), "salvo");
    }

    #[test]
    fn password_confirmation_matches_non_empty() {
        assert!(passwords_match("abc123", "abc123"));
        assert!(!passwords_match("abc123", "abc124"));
        assert!(!passwords_match("abc123", ""));
        assert!(!passwords_match("", "abc123"));
        // Vazia confirma com vazia NAO vale (sem isso, Enter+Enter passava).
        assert!(!passwords_match("", ""));
    }
}
