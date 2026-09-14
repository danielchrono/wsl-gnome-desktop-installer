# WSL Gnome-Desktop Installer — v0.1.0

Instalador em arquivo único: Ubuntu no WSL2 com desktop GNOME completo,
acessível via RDP (atalho no Desktop e no Iniciar, login automático).

## Uso rápido

1. Baixe `Install_Gnome-Desktop.cmd`, duplo clique (Windows 10 2004+ ou 11).
2. Responda: usuário Linux, senha (2x) e modo de rede
   (`[1]` localhost fixo `127.0.0.1` = padrão recomendado, `[2]` IP dinâmico).
3. Se pedir reboot, o instalador **reabre sozinho** e termina (sem clicar de novo).
4. Duplo clique no atalho **Ubuntu-GUI** e pronto.

## O que ele faz (7 etapas, idempotente)

1. Habilita o WSL, instala a distro e configura rede (mirrored ou dinâmica).
2. Cria o usuário Linux (**nunca apaga conta existente** — só sincroniza a senha)
   e ativa o systemd.
3. Instala `ubuntu-desktop-minimal` + GNOME Remote Desktop.
4. Sobe o GNOME Shell headless na resolução do seu monitor.
5. Configura RDP com TLS (porta **3390** — a 3389 é bloqueada no loopback
   pelo Windows 11, erro `0x708`), credencial no cofre e controle total.
6. Cria launcher `.cmd`, `.rdp` com login automático **assinado**
   (sem aviso de "fornecedor desconhecido") e atalhos com ícone do Ubuntu.
7. Verificação ponta a ponta.

## Arquivos

| Arquivo | Papel |
|---|---|
| `Install_Gnome-Desktop.cmd` | Entregável: extrai o PowerShell embutido e executa (**gerado — não editar**) |
| `source/Public/` | `Install-WslUbuntuGui` (instalador), `Get-WslUbuntuGuiStatus` (leitura) |
| `source/Private/` | Helpers (RDP, launcher, cofre, WSL, feedback) + `UbuntuGui-Constants.ps1` (todos os tunables: portas, timeouts, retries, paths) |
| `source/UbuntuGui.psd1` | Manifesto do módulo (versão, exports) |
| `tools/build_single.py` | Build: `python3 tools/build_single.py` regenera o `.cmd` |
| `tests/test-install-ubuntu-gui.py` | Regressão: `python3 tests/test-install-ubuntu-gui.py` |
| `tests/UbuntuGui.Tests.ps1` | Pester: `Invoke-Pester -Script tests/UbuntuGui.Tests.ps1` |

## Uso como módulo (comunidade)

```powershell
Import-Module ./source/UbuntuGui.psd1
Install-WslUbuntuGui                        # interativo
Get-WslUbuntuGuiStatus -LinuxUser daniel | Format-List   # somente leitura
```

Artefatos: `output/UbuntuGui/` (gerado, formato PSGallery — publicar com
`Publish-Module` quando houver API key). Para contribuir: edite `source/`,
rode o build + as duas suites; nunca edite o `.cmd` à mão.

## Segurança

- Senhas pedidas via `SecureString`; nunca gravadas em texto claro
  (DPAPI no `.rdp`/retomada, cofre `login` no Linux).
- TLS e assinatura `.rdp` usam certificados autoassinados locais.
- RDP escuta em todas as interfaces: prefira senha forte em rede compartilhada.

## Problemas conhecidos

| Erro | Causa | Correção |
|---|---|---|
| `0x708` sessão de console | RDP via `127.0.0.1:3389` bloqueado | v0.1.0 usa a porta 3390 |
| `0x904` não conecta | Credencial RDP vazia no daemon | instalador verifica de verdade (`grdctl status`) |
| Aviso "fornecedor desconhecido" | `.rdp` sem assinatura | instalador assina (cert próprio confiável) |

## Licença

MIT — veja `LICENSE`.
