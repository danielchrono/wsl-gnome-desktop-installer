//! Fonte unica de tunables tecnicos (`UbuntuGui-Constants.ps1`).
//!
//! `Install-WslUbuntuGui` mapeia para locais curtas (`RDP_PORT`, `MinBuild`,
//! ...); `Private/*` leem via [`defaults`] (vale no modulo e no .cmd).
//! [`defaults`] retorna um clone para o chamador nao mutar a fonte unica
//! (FP: sem estado compartilhado mutavel).

/// Todos os tunables do instalador. Clone raso = `Get-UbuntuGuiDefaults`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UbuntuGuiDefaults {
    pub distro: String,
    pub gui_package: String,
    pub fallback_resolution: String,
    pub rdp_port: u16,
    pub app_name: String,
    pub icon_url: String,
    pub min_build_mirrored: u32,
    pub cred_timeout_sec: u64,
    pub cred_retries: u32,
    pub apt_retries: u32,
    pub rdp_settle_sec: u64,
    pub wsl_shutdown_wait_sec: u64,
    pub shell_restart_wait_sec: u64,
    pub fresh_install_wait_sec: u64,
    pub reboot_delay_sec: u64,
    pub cert_years: u32,
    pub tls_cert_days: u32,
    pub publisher_subject: String,
    pub shell_service: String,
    pub shell_binary: String,
    pub shell_restart_sec: u64,
    pub rdp_service: String,
    pub gdm_service: String,
    pub gdm_alias: String,
    pub keyring_path: String,
    pub tls_cert_path: String,
    pub tls_key_path: String,
    pub pam_sudo_path: String,
    pub icon_sizes: Vec<u32>,
}

/// Model (MVVM): acesso somente-leitura aos defaults. Retorna clone para o
/// chamador nao mutar a fonte unica.
pub fn defaults() -> UbuntuGuiDefaults {
    UbuntuGuiDefaults {
        // Porta longe da 3389 (erro 0x708 no loopback).
        distro: "Ubuntu".to_string(),
        gui_package: "ubuntu-desktop-minimal".to_string(),
        fallback_resolution: "1600x900".to_string(),
        rdp_port: 3390,
        app_name: "Ubuntu-GUI".to_string(),
        icon_url: "https://commons.wikimedia.org/wiki/Special:FilePath/Ubuntu-logo-no-wordmark-solid-o-2022.svg?width=512".to_string(),
        // Win11 22H2+: mirrored networking.
        min_build_mirrored: 22621,
        cred_timeout_sec: 60,
        cred_retries: 2,
        apt_retries: 3,
        rdp_settle_sec: 4,
        wsl_shutdown_wait_sec: 8,
        shell_restart_wait_sec: 12,
        fresh_install_wait_sec: 15,
        reboot_delay_sec: 30,
        cert_years: 10,
        tls_cert_days: 825,
        publisher_subject: "CN=Ubuntu-GUI RDP".to_string(),
        shell_service: "gnome-shell-headless.service".to_string(),
        shell_binary: "gnome-shell".to_string(),
        shell_restart_sec: 3,
        rdp_service: "gnome-remote-desktop".to_string(),
        gdm_service: "gdm3".to_string(),
        gdm_alias: "gdm".to_string(),
        keyring_path: "~/.local/share/keyrings/login.keyring".to_string(),
        tls_cert_path: "~/.local/share/gnome-remote-desktop/rdp-cert.pem".to_string(),
        tls_key_path: "~/.local/share/gnome-remote-desktop/rdp-key.pem".to_string(),
        pam_sudo_path: "/etc/pam.d/sudo".to_string(),
        icon_sizes: vec![16, 32, 48, 128, 256],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn port_away_from_3389() {
        assert_eq!(defaults().rdp_port, 3390);
    }

    #[test]
    fn mirrored_requires_win11_22h2() {
        assert_eq!(defaults().min_build_mirrored, 22621);
    }

    #[test]
    fn sane_retries_and_timeouts() {
        let d = defaults();
        assert_eq!(d.cred_timeout_sec, 60);
        assert_eq!(d.cred_retries, 2);
        assert_eq!(d.apt_retries, 3);
    }

    #[test]
    fn returns_clone_mutation_does_not_leak() {
        let mut a = defaults();
        a.rdp_port = 1;
        assert_eq!(defaults().rdp_port, 3390);
    }

    #[test]
    fn publisher_subject_and_cert_windows() {
        let d = defaults();
        assert_eq!(d.publisher_subject, "CN=Ubuntu-GUI RDP");
        assert_eq!(d.cert_years, 10);
        assert_eq!(d.tls_cert_days, 825);
    }
}
