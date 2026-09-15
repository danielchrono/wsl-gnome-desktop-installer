//! Goldens de regressao (equivale a suite python `~60-substring`):
//! ordem das linhas do `.rdp`, blocos do launcher, nomes de erro, sentinela
//! de reboot, sem caminhos locais e defaults centralizados.

use ubuntu_gui::{REBOOT_SENTINEL, SCRIPT_VERSION};

#[test]
fn rdp_line_order_golden() {
    let rdp =
        ubuntu_gui::rdp::new_rdp_file_content("127.0.0.1", 3390, "daniel", "aabb", "1600x900");
    let text = rdp.join("\n");
    let order = [
        "screen mode id:i:1",
        "session bpp:i:32",
        "smart sizing:i:1",
        "desktopwidth:i:1600",
        "desktopheight:i:900",
        "full address:s:127.0.0.1:3390",
        "username:s:daniel",
        "password 51:b:aabb",
        "prompt for credentials:i:0",
        "enablecredsspsupport:i:1",
        "authentication level:i:0",
        "promptcredentialonce:i:1",
        "negotiate security layer:i:1",
    ];
    let mut pos = 0;
    for line in order {
        let found = text[pos..]
            .find(line)
            .unwrap_or_else(|| panic!("falta: {line}"));
        pos += found + line.len();
    }
}

#[test]
fn launcher_blocks_golden() {
    let fixed = ubuntu_gui::launcher::launcher_for_endpoint(
        "Ubuntu-GUI",
        "Ubuntu",
        "daniel",
        3390,
        "ABC123",
        true,
        "1600x900",
    );
    assert!(fixed.contains("rem IP fixo via mirrored networking (127.0.0.1)"));
    assert!(fixed.contains("127.0.0.1:3390"));
    assert!(fixed.contains("nao alterar"));
    assert!(!fixed.contains("rdpsign"));

    let dyn_ = ubuntu_gui::launcher::launcher_for_endpoint(
        "Ubuntu-GUI",
        "Ubuntu",
        "daniel",
        3390,
        "ABC123",
        false,
        "1600x900",
    );
    assert!(dyn_.contains(
        "for /f \"tokens=1\" %%i in ('%WSL% -d %DISTRO% -- hostname -I 2^>nul') do set WSL_IP=%%i"
    ));
    assert!(dyn_.contains("full address:s:%WSL_IP%:3390"));
    assert!(dyn_.contains("rdpsign.exe /sha256 ABC123"));
    // Cofre primeiro (sem arquivo, sem aviso de fornecedor), `.rdp` de fallback.
    for c in [&fixed, &dyn_] {
        assert!(c.contains("Ubuntu-GUI-Cred.ps1"), "sem helper: {c}");
        assert!(
            c.contains("else (start \"Ubuntu-GUI\" %MSTSC% /v:%WSL_IP%:3390 /w:1600 /h:900)"),
            "sem ramo /v:: {c}"
        );
    }
    for token in [
        "DISTRO_VAL",
        "RDP_PORT_VAL",
        "THUMBPRINT_VAL",
        "IPDISCOVERY_VAL",
        "RDPREWRITE_VAL",
        "LINUXUSER_VAL",
        "RDP_W_VAL",
        "RDP_H_VAL",
    ] {
        assert!(!fixed.contains(token), "sobrou {token} no fixo");
        assert!(!dyn_.contains(token), "sobrou {token} no dinamico");
    }
}

#[test]
fn error_names_golden() {
    use ubuntu_gui::error::InstallError;
    let names = [
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
    for (err, name) in names {
        assert_eq!(err.to_string(), name);
        assert_eq!(err.exit_code(), 1);
    }
}

#[test]
fn reboot_sentinel_and_version_golden() {
    assert_eq!(REBOOT_SENTINEL, "REBOOT_REQUIRED");
    assert_eq!(SCRIPT_VERSION, "0.1.0");
    // InstallOutcome::RebootRequired -> exit 0 + sentinela (bare return do PS).
    assert_eq!(REBOOT_SENTINEL.to_string(), "REBOOT_REQUIRED");
}

#[test]
fn no_local_paths_and_centralized_defaults() {
    // Defaults centralizados: porta/distro vern da fonte unica, nunca hardcoded.
    let d = ubuntu_gui::constants::defaults();
    assert_eq!(d.rdp_port, 3390);           // longe da 3389 do host (0x708 no loopback)
    assert_eq!(d.rdp_fallback_port, 3391);  // fallback automatico via net::choose_rdp_port
    assert_eq!(d.distro, "Ubuntu");
    assert_eq!(d.app_name, "Ubuntu-GUI");
    // Nada de caminho absoluto local nos tunables (build portatil).
    let probe = format!("{:?}", d);
    for bad in [
        "/home/",
        "/mnt/c/Users",
        "wsl.localhost",
        "C:\\Users",
        "C:/Users/",
    ] {
        assert!(!probe.contains(bad), "caminho local em defaults: {bad}");
    }
    // Status usa os mesmos defaults (sem 3390/Ubuntu hardcoded no modulo).
    let st = ubuntu_gui::status::assemble_status(None, "u", None, "active", "OK", "YES");
    assert_eq!(st.rdp_port, d.rdp_port);
    assert_eq!(st.distro, d.distro);
}

#[test]
fn resume_json_golden() {
    let st = ubuntu_gui::resume::ResumeState::new("daniel", "QkJD", "1");
    let json = st.to_json().unwrap();
    assert_eq!(
        json,
        r#"{"Phase":"AfterReboot","LinuxUser":"daniel","LinuxPassEnc":"QkJD","NetChoice":"1"}"#
    );
    assert_eq!(
        ubuntu_gui::resume::run_once_command("C:\\P\\Install-UbuntuGUI.resume.ps1"),
        "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\P\\Install-UbuntuGUI.resume.ps1\" -Resume"
    );
}
