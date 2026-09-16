//! Icone do `.exe` no Explorer: compila `assets/ubuntu-gui.rc` com o
//! `windres` do MinGW (mesmo toolchain que linka o binario) e linka o `.o`
//! via rustc-link-arg-bins. Sem SDK/`rc.exe`, sem crate nova.
//! Sem `windres` no PATH: aviso e build segue sem icone (nao quebra CI/Linux).
//! Fora do Windows: no-op (o `include_bytes!` do atalho vale em todo SO).
//!
//! Regen do logo: `python3 /tmp/make_ico.py` (gera `assets/ubuntu.ico`).

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn find_on_path(names: &[&str]) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for dir in env::split_paths(&path) {
        for name in names {
            let cand = dir.join(name);
            if cand.is_file() {
                return Some(cand);
            }
        }
    }
    None
}

fn main() {
    println!("cargo:rerun-if-changed=assets/ubuntu-gui.rc");
    println!("cargo:rerun-if-changed=assets/ubuntu.ico");
    if env::var("CARGO_CFG_WINDOWS").is_err() {
        return;
    }
    let assets =
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("assets");
    let obj = PathBuf::from(env::var("OUT_DIR").unwrap()).join("ubuntu-gui.o");
    let Some(windres) =
        find_on_path(&["x86_64-w64-mingw32-windres.exe", "windres.exe"])
    else {
        println!("cargo:warning=windres ausente no PATH; exe sem icone");
        return;
    };
    let ok = Command::new(&windres)
        .arg("ubuntu-gui.rc")
        .arg("--target=pe-x86-64")
        .arg("-o")
        .arg(&obj)
        .current_dir(&assets)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if ok && obj.is_file() {
        println!("cargo:rustc-link-arg-bins={}", obj.display());
    } else {
        println!("cargo:warning=windres falhou; exe sem icone");
    }
}
