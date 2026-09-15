//! Normaliza a saida de `wsl -l -q` (`ConvertFrom-WslDistroList.ps1`).

/// Remove NULs, espacos e linhas vazias.
pub fn convert_from_wsl_distro_list(raw: &[&str]) -> Vec<String> {
    raw.iter()
        .map(|s| s.replace('\0', "").trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_nuls_spaces_and_empties() {
        let out = convert_from_wsl_distro_list(&["Ubuntu\0", "  ", "Debian"]);
        assert_eq!(out, vec!["Ubuntu".to_string(), "Debian".to_string()]);
    }

    #[test]
    fn empty_in_empty_out() {
        assert!(convert_from_wsl_distro_list(&[]).is_empty());
        assert!(convert_from_wsl_distro_list(&["   ", "\0"]).is_empty());
    }
}
