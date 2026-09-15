"""Regressao do instalador de arquivo unico (acompanha src/*.ps1 via build).
Cobre os defeitos ja encontrados uma vez: auto-colisao do marcador,
escapes dobrados no cabecalho e quebra de linha final.
Uso:  python3 tools/build_single.py && python3 tests/test-install-ubuntu-gui.py
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import build_single

DST = os.path.join(ROOT, 'Install_Gnome-Desktop.cmd')
BS = chr(92)
LF = chr(10)
WS = chr(32) + chr(9) + chr(10) + chr(13)

fails = []


def check(name, cond):
    print(('PASS ' if cond else 'FAIL ') + name)
    if not cond:
        fails.append(name)


src = build_single.build_body()
dst = io.open(DST, encoding='utf-8', newline='').read()

parts = dst.split(':::PS1-BODY-START')
check('marcador START unico', len(parts) == 2)
sub = parts[1].split(':::PS1-BODY-END') if len(parts) == 2 else []
check('marcador END unico e final', len(sub) == 2 and sub[1].strip(WS) == '')
head = parts[0]
check('sem barra dupla no cabecalho', (BS + BS) not in head)
check('cauda sem aspas frageis', 'Trim() + [char]10' in head)
if len(sub) == 2:
    check('extracao identica ao build', sub[0].strip(WS) + LF == src.strip(WS) + LF)
check('cmd em dia com o build (nao editar a mao)', build_single.build_cmd() == dst)

check('rdp auto-login (DPAPI+blob)', 'ProtectedData' in src and 'password 51:b:' in src)
check('rewrite de IP no launcher', 'full address:s:' in src and 'Set-Content' in src)
check('rewrite so quando IP muda (sem churn)', 'RDP_CUR' in src and 'if not "%RDP_CUR%"' in src)
check('reassina so se rdpsign existir (sem erro vermelho)', "Test-Path ''%SYS32%\\rdpsign.exe''" in src)
check('rewrite nunca esvazia o rdp (leitura guardada)', "$c = Get-Content ''%RDPPATH%''" in src and "if ($c -match ''^full address:s:'')" in src)
check('log com senha removido no sucesso', 'Remove-Item $LogFile' in src)
check('ramo mirrored', 'networkingMode=mirrored' in src and '22621' in src)
check('localhost fixo ou fallback', "'127.0.0.1'" in src and 'IPDISCOVERY_VAL' in src)
check('probe decide endpoint', 'LocalhostLive' in src and 'Test-NetConnection' in src)
check('porta fora da 3389 (evita 0x708 no loopback)', '= 3390' in src and '= 3389' not in src)
check('grdctl fixa a porta', 'grdctl rdp set-port' in src and '$RDP_PORT' in src)
check('sem grep hardcoded :3389', "grep -q ':3389'" not in src)
check('verificacao usa a variavel de porta', '"RDP ouvindo :3389"' not in src)
check('credencial avisa a demora', 'CredTimeoutSec' in src and 'por tentativa' in src)
check('retry da credencial centralizado', 'CredRetries' in src and 'Tentativa $i/' in src)
check('tunables em UbuntuGui-Constants', 'UbuntuGuiDefaults' in src and 'MinBuildMirrored' in src and 'TlsCertDays' in src)
check('tls/restart mostra progresso', 'Aplicando TLS/porta' in src)
check('credencial verificada no daemon (nao so cofre)', 'grdctl status' in src and '(empty)' in src)
check('view-only desativado', 'disable-view-only' in src)
check('cofre desbloqueado antes do set-credentials', 'gnome-keyring-daemon --unlock' in src and 'XDG_RUNTIME_DIR=/run/user/$Uid' in src)
check('rdp sem aviso de cert autoassinado', "'authentication level:i:0'" in src)
check('rdp abre em janela (nao tela cheia)', "'screen mode id:i:1'" in src)
check('rdp redireciona USB do host', "'usbdevicestoredirect:s:*'" in src)
check('login sem aviso via Cofre do Windows (TERMSRV)', 'CredWriteW' in src and 'TERMSRV/' in src and 'Unprotect' in src and '-Cred.ps1' in src)
check('launcher prefere mstsc sem arquivo (fallback preservado)', 'CREDHELPER' in src and '/v:%WSL_IP%:RDP_PORT_VAL' in src and '"%RDPPATH%"' in src)
check('launcher abre mstsc no tamanho pedido (/w /h)', '/w:RDP_W_VAL' in src and '/h:RDP_H_VAL' in src and 'RdpWidth' in src)
check('rdp assinado (rdpsign)', 'rdpsign.exe' in src and 'signature:s:' in src)
check('publicador confiavel idempotente', 'TrustedPublishers' in src and 'CN=Ubuntu-GUI RDP' in src)
check('launcher fixo preserva assinatura', 'RDPREWRITE_VAL' in src and 'nao alterar' in src)
check('launcher dinamico reassina', 'THUMBPRINT_VAL' in src)
check('modo de rede selecionavel', 'Modo de rede' in src and '[2] IP dinamico' in src)
check('mascarado 127.0.0.1 e o padrao', 'WantMirrored' in src and '-ne "2"' in src)
check('mascarado exige build com fallback', 'WantMirrored -and' in src and '22621' in src)
check('dinamico avisa deteccao por clique', 'automaticamente a cada clique' in src)
check('trava anti-apagar user existente', 'NADA sera apagado' in src and 'nunca e apagada' in src)
check('senha sincronizada p/ user existente', 'Senha do Linux atualizada' in src)
check('root reservado', "eq 'root'" in src and 'reservado' in src)
check('usuario salvo entre runs', 'linux-user.txt' in src and 'SavedUserFile' in src)
check('sem abrir o app ubuntu (--no-launch)', '--no-launch' in src and 'Sem prompt duplo' in src)
check('retomada via RunOnce', 'RunOnce' in src and 'UbuntuGUIResume' in src)
check('flag -Resume', '[switch]$Resume' in src)
check('flag -Unattended chega ao Install', '[switch]$Unattended' in src and '-Unattended:$Unattended' in src)
check('unattended: fail-fast + reboot sozinho', '-Unattended exige -LinuxUser e -LinuxPassword' in src and 'Modo nao assistido: reiniciando sozinho' in src)
check('cmd repassa args (%*)', '"%TEMP%\\Install-UbuntuGUI.ps1" %*' in dst)
check('estado com senha DPAPI', 'resume-state.json' in src and 'LinuxPassEnc' in src)
check('reboot com conta regressiva', 'shutdown /r' in src and 'shutdown /a' in src)
check('tenta sem reboot antes', 'sem reboot - seguindo sozinho' in src)
check('apt espera DNS do WSL pos-reboot', 'getent hosts archive.ubuntu.com' in src and 'Aguardando rede do WSL' in src)
check('apt recupera dpkg interrompido', 'dpkg --configure -a' in src and 'apt-get install -f -y' in src)
check('apt com backoff entre tentativas', 'AptRetrySec' in src and 'antes da tentativa' in src)
check('apt com barra ao vivo (stdio herdado)', 'barra ao vivo abaixo' in src and '--exec bash -c "printf' in src)
check('icone: curl com retry e erro visivel', '--retry-all-errors' in src and '--show-error' in src)
check('rdpsign ausente nao mata (avisa e segue)', 'Sysnative' in src and 'pulando assinatura' in src)
check('icone: python via base64 sem aspas aninhadas', 'base64 -d > /tmp/mkico.py' in src and 'python3 /tmp/mkico.py' in src and 'python3 -c' not in src)
check('launcher resolve System32 via Sysnative', 'set SYS32=' in src and 'set MSTSC=%SYS32%' in src and 'not exist "%MSTSC%"' in src)
check('senha com retry (nao mata o run)', 'PasswordMaxAttempts' in src and 'tente de novo' in src and 'Test-PasswordConfirmation' in src)
check('CFA: libera com permissao, atalho nunca fatal', 'ControlledFolderAccessAllowedApplications' in src and 'EnableControlledFolderAccess' in src and 'Atalhos nao criados' not in src)
check('cert TLS confiavel no Root (sem admin)', "X509Store('Root', 'CurrentUser')" in src)
check('cert sem unroll de bytes no construtor', '(,$tlsBytes)' in src)
check('mstsc: tamanho e exit code diagnosticados', 'Download do mstsc suspeito' in src and 'ExitCode' in src)
check('mstsc reinstalado sozinho quando ausente', 'linkid=2247659' in src and 'Cliente RDP (mstsc) restaurado' in src)
check('mstsc: so executa se assinado Microsoft', 'Authenticode' in src and 'Microsoft Corporation' in src)
check('reserva RDP via FreeRDP no WSL quando sem mstsc', 'freerdp3-x11' in src and 'freerdp2-x11' in src and 'sdl-freerdp' in src)
check('launcher usa reserva do WSL se mstsc ausente', 'FREERDP_VAL' in src and 'W_RDP_VAL' in src and 'xfreerdp' in src)
check('elevacao relanca o proprio cmd (caixa preta)', "'%~f0'" in head and 'Verb RunAs' in head)
check('elevacao repassa argumentos do cmd', "'%*'" in head)
check('ps1 nao re-eleva quando vem do cmd', 'UBUNTUGUI_FROM_CMD' in src and 'UBUNTUGUI_FROM_CMD' in head)
check('titulo impresso uma vez (entry-head manda)', src.count('UbuntuGuiBannerShown') == 2 and 'if (-not $script:UbuntuGuiBannerShown)' in src)
check('rdpsign procurado em System32 e Sysnative (todo contexto)', 'System32\\rdpsign.exe' in src and 'Sysnative\\rdpsign.exe' in src and 'Where-Object { Test-Path $_ }' in src)
check('auto-elevacao com UAC (sem bypass)', '-Verb RunAs' in src and 'Auto-elevacao' in src and 'Unattended nunca relanca' in src)
check('build carimbado (id deterministico)', '__BUILD_ID__' not in src and '$SCRIPT_BUILD' in src)
check('build id e hex de 12', re.search(r'\$SCRIPT_BUILD = "[0-9a-f]{12}"', src) is not None)
check('limpa retomada no sucesso', 'Clear-ResumeState' in src)
check('versao 0.1.0', 'SCRIPT_VERSION' in src and '"0.1.0"' in src)
tracked = []
for dp, _, fns in os.walk(ROOT):
    if 'output' in dp.split(os.sep):
        continue
    for fn in fns:
        if fn.endswith(('.ps1', '.py', '.psd1', '.md', '.cmdpart', '.cmd')):
            tracked.append(os.path.join(dp, fn))
local_paths = [p for p in tracked
               if os.path.basename(p) != 'test-install-ubuntu-gui.py'
               and re.search(r'/home/|/mnt/c/Users|wsl\.localhost|C:\\Users\\|C:/Users/', io.open(p, encoding='utf-8', newline='').read())]
check('sem caminhos absolutos locais (build portatil)', not local_paths)
psd1 = io.open(os.path.join(ROOT, 'source', 'UbuntuGui.psd1'), encoding='utf-8').read()
mver = re.search(r"ModuleVersion\s*=\s*'([^']+)'", psd1)
check('manifesto declara 0.1.0', mver and mver.group(1) == '0.1.0')
check('versoes psd1 e script iguais', mver and ('"%s"' % mver.group(1)) in src)
check('modulo exporta as duas funcoes', 'Install-WslUbuntuGui' in psd1 and 'Get-WslUbuntuGuiStatus' in psd1)
check('funcoes Public no build', 'function Install-WslUbuntuGui' in src and 'function Get-WslUbuntuGuiStatus' in src)
status_src = io.open(os.path.join(ROOT, 'source', 'Public', 'Get-WslUbuntuGuiStatus.ps1'), encoding='utf-8', newline='').read()
install_src = io.open(os.path.join(ROOT, 'source', 'Public', 'Install-WslUbuntuGui.ps1'), encoding='utf-8', newline='').read()
check('status usa defaults centralizados (sem 3390/Ubuntu hardcoded)', 'Get-UbuntuGuiDefaults' in status_src and 'RdpPort = 3390' not in status_src and 'Distro = "Ubuntu"' not in status_src)
check('sondas de saude via helpers unicos', 'Test-WslShellActive' in src and 'Test-WslRdpListening' in src)
check('sem sonda shell inline duplicada', 'systemctl --user is-active $ShellService' not in src and 'systemctl --user is-active $($D.ShellService)' not in src)
check('sem sonda rdp inline duplicada', "ss -tlnp 2>/dev/null | grep -q ':$RDP_PORT'" not in src)
check('ip do wsl via helper unico', 'Get-WslIpAddress -Distro $DISTRO' in src and 'Get-FirstIpAddress (wsl -d $DISTRO' not in src)
check('securestring via helper unico (+ ZeroFreeBSTR)', 'ConvertFrom-SecureStringPlain' in src and src.count('SecureStringToBSTR') == 1 and 'ZeroFreeBSTR' in src)
check('caminho linux-user.txt em fonte unica', '$SavedUserFile' in install_src and '(Join-Path $ProgDir "linux-user.txt")' not in src)
check('novos helpers no build', 'function ConvertFrom-SecureStringPlain' in src and 'function Get-WslIpAddress' in src and 'function Test-WslShellActive' in src and 'function Test-WslRdpListening' in src)
check('sonda do cofre classifica Locked vs Error', 'function Get-WslKeyringProbeState' in src and "'Unlocked'" in src and "'Locked'" in src and "'Error'" in src)
check('sonda distingue colecao ausente (Missing)', 'function Test-MissingCollectionOutput' in src and "'Missing'" in src and 'Cofre ausente' in install_src and 'nunca rm' in install_src)
check('cofre recriado com backup quando senha nao confere', 'function Reset-WslLoginKeyring' in src and 'function New-WslLoginKeyring' in src and 'Cofre recriado' in install_src and 'Cofre destravou apos recriar' in install_src)
check('cofre criado via daemon --login (sem sudo/pam.d)', 'function Start-WslLoginKeyringDaemon' in src and '--daemonize --login' in src and 'pam_gnome_keyring' not in src and 'PamSudoPath' not in install_src)
check('falha do cofre mostra evidencia (unlock + sonda)', 'unlock disse:' in src and 'Sonda do cofre falhou' in src and 'Cofre destravou na re-sonda' in src)
check('re-sonda limitada (sem retry cego)', 'KeyringReprobeSec' in src and 'Start-Sleep -Seconds $KeyringReprobeSec' in src)
check('falha Locked traz detalhe (login/arquivos/daemons)', 'function Get-WslKeyringLockDetail' in src and 'collection/login' in src and "pgrep -fc '[g]nome-keyring-daemon'" in src and 'pgrep -c gnome-keyring-daemon' not in src)
check('reparo cirurgico do bus (sem tocar nos arquivos)', 'function Repair-WslKeyringBus' in src and 'Bus do cofre reparado' in src and 'UBUNTUGUI_FAIL_REPORTED' in src and 'detalhes acima' in src)
check('unlock+sonda mesma chamada (daemon efemero)', 'function UnlockAndProbe-WslKeyring' in src and 'function Read-UnlockProbeOutput' in src and 'UBUNTUGUI_UNLOCKCODE=' in src and 'UBUNTUGUI_PROBE=' in src)
check('unlock/sonda via builders unicos', 'function Get-WslUnlockPipeline' in src and 'function Get-WslKeyringProbeCommand' in src and install_src.count('UnlockAndProbe-WslKeyring -LinuxUser') == 3 and 'Unlock-WslKeyring -LinuxUser' not in install_src)
check('pula unlock se ja destravado + guia seahorse', 'Cofre ja destravado (pulando unlock)' in src and 'seahorse' in src and '$pamUnlocked' in install_src)
check('teste de controle decide senha-errada vs unlock-quebrado', 'function Test-WslUnlockExitMeaningful' in src and 'ubuntugui-sonda-falsa-000' in src and 'Senha incorreta para o cofre existente' in src and 'recriando o cofre' in install_src)
check('prestart do daemon antes do PAM', 'function Start-WslKeyringDaemon' in src and 'gnome-keyring-daemon --start' in src and 'Daemon do cofre no ar' in src)

sys.exit(1 if fails else 0)
