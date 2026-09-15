# WSL Gnome-Desktop Installer — v0.1.0 (Rust)

Instalador em `.exe` único: Ubuntu no WSL2 com desktop GNOME completo,
acessível via RDP (atalho no Desktop e no Iniciar, login automático).

> A versão PowerShell (`Install_Gnome-Desktop.cmd`, `source/`, `tools/`)
> foi canonizada na branch **`ps-legacy`**. A `main` é só Rust.

## Uso rápido

1. Compile: `cargo build --release` dentro de `rust/`
   (no Linux p/ Windows: `cargo build --release --target x86_64-pc-windows-msvc`).
2. Rode `ubuntu-gui.exe` (Windows 10 2004+ ou 11).
3. Responda: usuário Linux, senha (2x) e modo de rede
   (`localhost` fixo `127.0.0.1` = padrão recomendado, ou IP dinâmico).
4. Se pedir reboot, o instalador **reabre sozinho** e termina (sem clicar de novo).
5. Duplo clique no atalho **Ubuntu-GUI** e pronto.

`ubuntu-gui.exe --help` lista as flags (`--linux-user`, `--linux-password`,
`--resume <state.json>`, `--no-transcript`, ...).

Totalmente sem paradas (captura tudo na 1a run, sem perguntar 2x):

```bat
ubuntu-gui.exe --unattended --linux-user caiop --linux-password SUA-SENHA
```

(opcional: `--net-choice 2` p/ IP dinâmico; reboot sozinho quando preciso,
retoma sozinho depois; senha com 3 tentativas no modo interativo).

## O que ele faz (7 etapas, idempotente)

1. Habilita o WSL, instala a distro e configura rede (mirrored ou dinâmica).
2. Cria o usuário Linux (**nunca apaga conta existente** — só sincroniza a senha)
   e ativa o systemd.
3. Instala `ubuntu-desktop-minimal` + GNOME Remote Desktop (espelho APT
   mais rápido medido na hora, com backup do `sources`).
4. Sobe o GNOME Shell headless na resolução do seu monitor.
5. Configura RDP com TLS (porta **3390** — a 3389 é a porta do RDP do host e
   o loopback dela é instável entre máquinas; medido: trava sem listener),
   credencial no cofre e controle total.
6. Cria launcher `.cmd`, `.rdp` com login automático **assinado**
   (sem aviso de "fornecedor desconhecido") e atalhos com ícone do Ubuntu.
7. Verificação ponta a ponta.

## Cofre (conquistas espelhadas do legado)

- Sonda classifica `Unlocked` / `Locked` / `Missing` (coleção ausente)
  / `Error` (bus fora) — sem confundir um com o outro;
- Criação via `gnome-keyring-daemon --daemonize --login` (sem `sudo`,
  sem `pam.d`, já sai destravado);
- Recriação com backup timestampado + restore automático se falhar
  (nunca `rm` no `login.keyring`);
- Unlock+sonda na mesma chamada WSL; fail-fast sem retry cego.

## Desenvolver

```sh
cd rust
cargo test      # suite (inclui goldens em ubuntu-gui/tests/)
cargo build --release
```
