//! Escapa a senha para embutir em `bash -c "..."` (`Get-PasswordQuote.ps1`).
//!
//! Ordem fixa do PowerShell (relevante: cada passo pode introduzir chars que
//! os passos seguintes escapariam de novo se a ordem mudasse):
//!
//! 1. `'` -> `'\''` (idioma bash para aspas dentro de aspas simples)
//! 2. `` ` `` -> ` `` ` (crase dobra para o PowerShell)
//! 3. `$` -> `` `$ `` (cifrão escapa para o PowerShell)
//! 4. `"` -> `` `" `` (aspa dupla escapa para o PowerShell)

/// `Get-PasswordQuote`: escapa bash + PowerShell, nesta ordem.
pub fn get_password_quote(password: &str) -> String {
    password
        .replace('\'', "'\\''")
        .replace('`', "``")
        .replace('$', "`$")
        .replace('"', "`\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_plain_text() {
        assert_eq!(get_password_quote("abc123"), "abc123");
    }

    #[test]
    fn escapes_apostrophe_for_bash() {
        assert_eq!(get_password_quote("a'b"), "a'\\''b");
    }

    #[test]
    fn escapes_dollar_for_powershell() {
        assert_eq!(get_password_quote("a$b"), "a`$b");
    }

    #[test]
    fn escapes_backtick_and_quote() {
        assert_eq!(get_password_quote("a`\"b"), "a```\"b");
    }

    #[test]
    fn order_apostrophe_then_backtick_then_dollar_then_quote() {
        // O passo 1 introduz `\` mas nenhum passo seguinte toca em `\`;
        // o passo 2 dobra crases antes do passo 4 prefixar `"` com crase.
        assert_eq!(get_password_quote("'"), "'\\''");
        assert_eq!(get_password_quote("`"), "``");
        assert_eq!(get_password_quote("$"), "`$");
        assert_eq!(get_password_quote("\""), "`\"");
        // Traco manual: ' -> '\'' ; ` final dobra; $ -> `$ ; " -> `".
        assert_eq!(get_password_quote("'$\"`"), "'\\''`$`\"``");
    }
}
