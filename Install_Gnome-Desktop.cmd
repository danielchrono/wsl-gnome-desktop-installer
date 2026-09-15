@echo off
rem Instalador Ubuntu GUI em ARQUIVO UNICO: extrai o PowerShell embutido
rem abaixo (texto claro, auditavel) para a pasta TEMP e executa.
setlocal
powershell -NoProfile -Command "$a=':::PS1-BODY'+'-START'; $b=':::PS1-BODY'+'-END'; $t=[IO.File]::ReadAllText('%~f0') -split $a; $u=$t[1] -split $b; [IO.File]::WriteAllText('%TEMP%\Install-UbuntuGUI.ps1',$u[0].Trim() + [char]10)"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\Install-UbuntuGUI.ps1"
echo.
pause
exit /b 0
:::PS1-BODY-START
[CmdletBinding()]
param([switch]$Resume)
$SCRIPT_VERSION = "0.1.0"
try { Start-Transcript -Path (Join-Path $env:TEMP 'Ubuntu-GUI-install.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
# Fonte unica de tunables tecnicos: mude AQUI, nunca espalhado no fluxo.
# Install-WslUbuntuGui mapeia para locais curtas ($RDP_PORT, $MinBuild, ...);
# Private/* leem via $script:UbuntuGuiDefaults (vale no modulo e no .cmd).
$script:UbuntuGuiDefaults = @{
  Distro               = 'Ubuntu'
  GuiPackage           = 'ubuntu-desktop-minimal'
  FallbackResolution   = '1600x900'
  RdpPort              = 3390    # longe da 3389 (erro 0x708 no loopback)
  AppName              = 'Ubuntu-GUI'
  IconUrl              = 'https://commons.wikimedia.org/wiki/Special:FilePath/Ubuntu-logo-no-wordmark-solid-o-2022.svg?width=512'
  MinBuildMirrored     = 22621   # Win11 22H2+: mirrored networking
  CredTimeoutSec       = 60      # timeout por tentativa de set-credentials
  CredRetries          = 2       # tentativas de gravacao no cofre
  KeyringReprobeSec    = 5       # espera antes da re-sonda (corrida de ativacao do D-Bus)
  AptRetries           = 3       # tentativas de apt install
  RdpSettleSec         = 4       # espera pos-restart do RDP
  WslShutdownWaitSec   = 8       # espera pos wsl --shutdown
  ShellRestartWaitSec  = 12      # espera pos-restart do Shell
  FreshInstallWaitSec  = 15      # espera pos wsl --install
  RebootDelaySec       = 30      # shutdown /r /t
  CertYears            = 10      # validade do cert de publicador
  TlsCertDays          = 825     # validade do cert TLS do RDP
  PublisherSubject     = 'CN=Ubuntu-GUI RDP'
  ShellService         = 'gnome-shell-headless.service'
  ShellBinary          = 'gnome-shell'
  ShellRestartSec      = 3
  RdpService           = 'gnome-remote-desktop'
  GdmService           = 'gdm3'
  GdmAlias             = 'gdm'
  KeyringPath          = '~/.local/share/keyrings/login.keyring'
  TlsCertPath          = '~/.local/share/gnome-remote-desktop/rdp-cert.pem'
  TlsKeyPath           = '~/.local/share/gnome-remote-desktop/rdp-key.pem'
  PamSudoPath          = '/etc/pam.d/sudo'
  IconSizes            = @(16, 32, 48, 128, 256)
}

# Model (MVVM): acesso somente-leitura aos defaults. Retorna clone raso para o
# chamador nao mutar a fonte unica (FP: sem estado compartilhado mutavel).
function Get-UbuntuGuiDefaults {
  [CmdletBinding()]
  param()
  $clone = @{}
  foreach ($k in $script:UbuntuGuiDefaults.Keys) { $clone[$k] = $script:UbuntuGuiDefaults[$k] }
  return $clone
}
# View (MVVM): so render no console, sem decisao. O estado de falhas vive no
# ViewModel (Install-WslUbuntuGui, variavel local); $script:Failures segue como
# compat legada espelhada para codigo externo que ainda le o global.
$script:Failures = @()
function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }
function Fail([string]$msg) { Write-Host "  [FALHA] $msg" -ForegroundColor Red; $script:Failures += $msg; $env:UBUNTUGUI_FAIL_REPORTED = '1' }

# Estado explicito (FP): hashtable imutavel por copia. Novo codigo prefere estas.
function New-UbuntuGuiFeedbackState {
  [CmdletBinding()]
  param()
  return @{ Failures = @() }
}
function Add-UbuntuGuiFailure {
  [CmdletBinding()]
  param([hashtable]$State, [string]$Message)
  $base = @()
  if ($State -and $State.Failures) { $base = @($State.Failures) }
  return @{ Failures = @($base + $Message) }
}
function Get-UbuntuGuiFailures {
  [CmdletBinding()]
  param([hashtable]$State)
  if ($State -and $State.ContainsKey('Failures')) { return @($State.Failures) }
  return @($script:Failures)
}
# Roda 'wsl -d <distro> ...' repassando o exit code real do Linux.
# ViewModel passa -Distro explicito (FP: sem dinamico). Chamadas antigas com 2 args
# seguem funcionando via fallback: variavel $DISTRO do chamador > defaults > 'Ubuntu'.
function Invoke-Wsl {
  [CmdletBinding()]
  param([string]$AsUser, [string]$Command, [string]$Distro)
  $TargetDistro = $Distro
  if ([string]::IsNullOrWhiteSpace($TargetDistro)) {
    try { $TargetDistro = $DISTRO } catch { $TargetDistro = $null }
  }
  if ([string]::IsNullOrWhiteSpace($TargetDistro) -and $script:UbuntuGuiDefaults) {
    $TargetDistro = $script:UbuntuGuiDefaults.Distro
  }
  if ([string]::IsNullOrWhiteSpace($TargetDistro)) { $TargetDistro = 'Ubuntu' }
  $out = wsl -d $TargetDistro -u $AsUser --exec bash -c $Command 2>&1
  return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}
function Invoke-WslRoot {
  [CmdletBinding()]
  param([string]$Command, [string]$Distro)
  if ($PSBoundParameters.ContainsKey('Distro')) { return Invoke-Wsl "root" $Command -Distro $Distro }
  return Invoke-Wsl "root" $Command
}
# Gestor de cofre (credencial RDP no Secret Service via gnome-keyring/grdctl).
# Todo acesso ao cofre passa por aqui: elimina a duplicacao entre Install
# (etapa 5) e Get-WslUbuntuGuiStatus e nunca engole resultado (sem Out-Null
# cego). I/O com o daemon fica isolado nestas fronteiras; retry e mensagens
# ficam na View. Cobertura Pester no construtor puro.
function New-WslSessionEnv([string]$Uid) {
  return "XDG_RUNTIME_DIR=/run/user/$Uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$Uid/bus"
}

# Pipeline de unlock (sem exit): printf|unlock|tail. O exit com PIPESTATUS vive
# no chamador, p/ compor unlock+sonda na MESMA chamada WSL (daemon efemero:
# unlock e sonda em chamadas separadas podem falar com instancias diferentes).
function Get-WslUnlockPipeline([string]$PasswordQuote, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return "printf '%s' '$PasswordQuote' | $envPrefix gnome-keyring-daemon --unlock 2>&1 | tail -n 3"
}

# Comando da sonda Locked (com 2>&1: o texto do erro e diagnostico, nao lixo).
function Get-WslKeyringProbeCommand([string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return "$envPrefix busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>&1"
}

# Limpeza cirurgica do bus do cofre (via root, que enxerga todos os donos).
# Mata (a) daemons de OUTRO dono (o PAM recusa socket alheio) e (b) orfaos
# '--unlock' (nascem de unlock sem daemon, nao servem direito, mas ocupam o
# bus e fazem o --start ceder). NUNCA toca num daemon '--start' do proprio
# usuario nem nos arquivos do cofre. '[g]...' evita o pgrep se achar; o
# '$$' evita suicidio. Sem alvo, nao faz nada (FEITO puro).
function Repair-WslKeyringBus([string]$LinuxUser, [string]$Uid, [string]$Distro) {
  $cmd = "for p in `$(pgrep -f '[g]nome-keyring-daemon' 2>/dev/null); do if [ `"`$p`" = `"`$`$`" ]; then continue; fi; ou=`$(stat -c %U /proc/`$p 2>/dev/null || echo GONE); args=`$(tr '\0' ' ' </proc/`$p/cmdline 2>/dev/null); case `"`$ou`" in `"$LinuxUser`") case `"`$args`" in *--unlock*) kill `$p 2>/dev/null && echo `"orfao-`$p`";; esac;; *) kill `$p 2>/dev/null && echo `"estranho-`$p`-`$ou`";; esac; done; if [ -d /run/user/$Uid/keyring ] && [ -n `"`$(find /run/user/$Uid/keyring -not -user $LinuxUser 2>/dev/null)`" ]; then rm -rf /run/user/$Uid/keyring; echo SOCKETS-LIMPOS; fi; echo FEITO"
  $r = Invoke-WslRoot $cmd -Distro $Distro
  $out = if ($r.Out) { $r.Out.Trim() } else { '' }
  return @{ Repaired = [bool]($out -match 'orfao-|estranho-|SOCKETS-LIMPOS'); Detail = $out }
}

# Sobe o daemon como o proprio usuario ANTES do PAM: o gkr-pam falha ao
# inicia-lo sozinho ("couldn't setup credentials: Operation not permitted" no
# auth.log). Idempotente (--start com daemon rodando = no-op). Retorna $true
# se o servico responde no bus em ate ~10s; $false nunca aborta o chamador
# (o PAM tenta subir sozinho como antes).
function Start-WslKeyringDaemon([string]$LinuxUser, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  Invoke-Wsl $LinuxUser "$envPrefix gnome-keyring-daemon --start >/dev/null 2>&1" | Out-Null
  for ($i = 1; $i -le 10; $i++) {
    if ((Get-WslKeyringProbeState -LinuxUser $LinuxUser -Uid $Uid).State -ne 'Error') { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
}

# Cria o login.keyring via PAM do sudo com a senha informada (o PAM cria com o
# authtok quando o arquivo nao existe; revertido em seguida pelo chamador via
# verificacao de /etc/pam.d/sudo). Puro de View (sem Ok/Fail: retorna
# @{ Created; Fresh }). Idempotente: arquivo existente = Created sem tocar PAM.
function New-WslLoginKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$KeyringPath, [string]$PamSudoPath) {
  $r = Invoke-Wsl $LinuxUser "test -f $KeyringPath && echo OK || echo MISSING"
  if ($r.Out -match "OK") { return @{ Created = $true; Fresh = $false } }
  $pamAdd = "printf '%s\nauth optional pam_gnome_keyring.so\nsession optional pam_gnome_keyring.so auto_start\n' '$PasswordQuote' | sudo -S tee -a $PamSudoPath > /dev/null"
  Invoke-Wsl $LinuxUser "$pamAdd && printf '%s\n' '$PasswordQuote' | sudo -S true && printf '%s\n' '$PasswordQuote' | sudo -S sed -i '/pam_gnome_keyring.so/d' $PamSudoPath" | Out-Null
  $r2 = Invoke-Wsl $LinuxUser "test -f $KeyringPath && echo OK || echo MISSING"
  $created = ($r2.Out -match "OK")
  return @{ Created = $created; Fresh = $created }
}

# Recria o login.keyring com a senha informada quando a senha do cofre
# existente nao confere (mismatch: sudo passa, cofre fica trancado). Backup
# com timestamp ANTES; se a criacao falhar, restaura o original e retorna
# Recreated=$false (nunca perde o arquivo). Daemon proprio reiniciado apos
# criar: o servidor carrega o keyring no startup, e sem restart ele serviria
# a colecao velha em memoria. Retorna @{ Recreated; Backup }.
function Reset-WslLoginKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid, [string]$KeyringPath, [string]$PamSudoPath) {
  $ts = (Invoke-Wsl $LinuxUser "date +%Y%m%d-%H%M%S").Out.Trim()
  $backup = "$KeyringPath.bak-$ts"
  Invoke-Wsl $LinuxUser "mv $KeyringPath $backup 2>/dev/null; echo MOVED" | Out-Null
  $kc = New-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PasswordQuote -KeyringPath $KeyringPath -PamSudoPath $PamSudoPath
  if (-not $kc.Created) {
    Invoke-Wsl $LinuxUser "mv $backup $KeyringPath 2>/dev/null; echo RESTORED" | Out-Null
    return @{ Recreated = $false; Backup = $backup }
  }
  Invoke-Wsl $LinuxUser "pkill -f '[g]nome-keyring-daemon' 2>/dev/null; sleep 1; echo REINICIADO" | Out-Null
  Start-WslKeyringDaemon -LinuxUser $LinuxUser -Uid $Uid | Out-Null
  return @{ Recreated = $true; Backup = $backup }
}

# Desbloqueia o cofre 'login' com a senha informada. Retorna @{ Code; Out }.
# Code != 0 = senha nao confere ou daemon fora: o chamador falha rapido com
# instrucao (nunca retry cego que queima 2x60s). PIPESTATUS[1] e o exit do
# unlock (sem ele, o tail mascarava tudo com 0).
function Unlock-WslKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  return Invoke-Wsl $LinuxUser "$(Get-WslUnlockPipeline -PasswordQuote $PasswordQuote -Uid $Uid); exit `${PIPESTATUS[1]}"
}

# Parser puro do protocolo unlock+sonda (marcadores UBUNTUGUI_*). Fail-closed:
# sem marcador de codigo (-1) ou sonda vazia, o chamador trata como Error.
function Read-UnlockProbeOutput([string]$Out) {
  $code = -1; $probe = ''
  foreach ($line in ($Out -split "`n")) {
    if ($line -match '^UBUNTUGUI_UNLOCKCODE=(\d+)\s*$') { $code = [int]$Matches[1] }
    elseif ($line -match '^UBUNTUGUI_PROBE=(.*)$') { $probe = $Matches[1].Trim() }
  }
  return @{ UnlockCode = $code; Probe = $probe }
}

# Unlock + sonda na MESMA invocacao WSL. Retorna @{ UnlockCode; State; Probe;
# UnlockText }. O Code do Invoke-Wsl e ignorado de proposito (o echo final
# sempre sai 0): vale o UnlockCode parseado. UnlockText nunca vem vazio
# (vira '(vazio)') p/ as mensagens de falha nao sairem ocas.
function UnlockAndProbe-WslKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  $unlockPipe = Get-WslUnlockPipeline -PasswordQuote $PasswordQuote -Uid $Uid
  $probeCmd = Get-WslKeyringProbeCommand -Uid $Uid
  $r = Invoke-Wsl $LinuxUser "$unlockPipe; ucode=`${PIPESTATUS[1]}; probe=`$($probeCmd); echo UBUNTUGUI_UNLOCKCODE=`$ucode; echo UBUNTUGUI_PROBE=`$probe"
  $parsed = Read-UnlockProbeOutput -Out $r.Out
  if ($parsed.UnlockCode -lt 0 -or [string]::IsNullOrWhiteSpace($parsed.Probe)) { $state = 'Error' }
  elseif (Test-UnlockedPropertyOutput -Out $parsed.Probe) { $state = 'Unlocked' }
  elseif ($parsed.Probe -match 'b true') { $state = 'Locked' }
  elseif (Test-MissingCollectionOutput -Out $parsed.Probe) { $state = 'Missing' }
  else { $state = 'Error' }
  $ut = ((($r.Out -split "`n") | Where-Object { $_ -notmatch '^UBUNTUGUI_' }) -join "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($ut)) { $ut = '(vazio)' }
  return @{ UnlockCode = $parsed.UnlockCode; State = $state; Probe = $parsed.Probe; UnlockText = $ut }
}

# Grava usuario+senha do RDP no cofre. 'env' e obrigatorio apos 'timeout'
# (timeout executa o 1o argumento como programa: prefixo VAR=x puro falharia).
function Set-WslRdpCredential([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid, [int]$TimeoutSec) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return Invoke-Wsl $LinuxUser "timeout $TimeoutSec env $envPrefix grdctl rdp set-credentials '$LinuxUser' '$PasswordQuote' 2>&1 | tail -n 5"
}

# Verifica de verdade no daemon (o cofre existir nao basta: item vazio tambem conta).
function Test-WslRdpCredential([string]$LinuxUser, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  $r = Invoke-Wsl $LinuxUser "$envPrefix grdctl status 2>/dev/null | grep -E 'Username:' | grep -qv '(empty)' && echo YES || echo NO"
  return ($r.Out.Trim() -eq "YES")
}

# Parser puro da sonda (fail-closed: so 'b false' prova destravado).
function Test-UnlockedPropertyOutput([string]$Out) {
  return ($Out -match 'b false')
}

# Colecao login ausente: o daemon RESPONDEU mas nao expoe a colecao (o arquivo
# login.keyring nao existe no disco ou o daemon e anterior a ele). Textos
# observados ao vivo: "Unknown object '/org/.../aliases/default'" (busctl) e
# "Object does not exist at path .../collection/login" (resposta do proprio
# daemon). Fail-closed: qualquer outro texto nao e Missing.
function Test-MissingCollectionOutput([string]$Out) {
  if ([string]::IsNullOrWhiteSpace($Out)) { return $false }
  if ($Out -match 'Unknown object .*/aliases/default') { return $true }
  if ($Out -match 'Object does not exist at path' -and $Out -match 'collection/login') { return $true }
  return $false
}

# Estado da sonda do cofre: Locked vs Unlocked vs Missing vs Error. Fail-closed
# como antes (so 'b false' prova destravado), mas sem confundir 'trancado' com
# 'sonda quebrou' nem com 'cofre sumiu': 'b true' = trancado de verdade;
# Missing = daemon no ar sem colecao login (arquivo ausente/daemon velho -
# pede restaurar backup, nao mexer no D-Bus); qualquer outra saida (bus fora)
# = Error, que pede outro conserto (D-Bus/sessao, nao apagar o keyring).
# 2>&1 de proposito: o texto do erro e o diagnostico.
function Get-WslKeyringProbeState([string]$LinuxUser, [string]$Uid) {
  $r = Invoke-Wsl $LinuxUser (Get-WslKeyringProbeCommand -Uid $Uid)
  $out = if ($r.Out) { $r.Out.Trim() } else { '' }
  if (Test-UnlockedPropertyOutput -Out $out) { return @{ State = 'Unlocked'; Out = $out } }
  if ($out -match 'b true') { return @{ State = 'Locked'; Out = $out } }
  if (Test-MissingCollectionOutput -Out $out) { return @{ State = 'Missing'; Out = $out } }
  return @{ State = 'Error'; Out = $out }
}

# Sonda sem prompt: colecao 'default' destravada? Le a propriedade Locked via
# busctl (retorna na hora, nunca abre prompt). Qualquer duvida = $false:
# melhor falhar rapido com instrucao do que travar 60s no set-credentials.
function Test-WslKeyringUnlocked([string]$LinuxUser, [string]$Uid) {
  return ((Get-WslKeyringProbeState -LinuxUser $LinuxUser -Uid $Uid).State -eq 'Unlocked')
}

# Teste de controle: unlock com senha GARANTIDAMENTE errada (sem efeito
# colateral: unlock falho nao muda nada). Se sair != 0, exit codes sao
# significativos neste sistema (e unlock-0 com a senha do usuario = senha
# aceita => senha incorreta p/ o cofre existente). Se sair 0, o unlock por
# stdin nao valida nada aqui (e a senha do usuario e inocentada). So chamado
# no caminho de falha Locked.
function Test-WslUnlockExitMeaningful([string]$LinuxUser, [string]$Uid) {
  $probe = UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote 'ubuntugui-sonda-falsa-000' -Uid $Uid
  return ($probe.UnlockCode -ne 0)
}

# Detalhe so p/ falha Locked: a colecao LOGIN esta trancada ou o DEFAULT aponta
# p/ outra colecao? Quais arquivos existem, quantos daemons rodam. So leitura,
# so chamado no caminho de falha (custo zero no sucesso). Se o caminho da
# colecao estiver errado, o busctl devolve erro como texto - que tambem e
# evidencia, nunca quebra.
function Get-WslKeyringLockDetail([string]$LinuxUser, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  $login = Invoke-Wsl $LinuxUser "$envPrefix busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked 2>&1"
  $files = Invoke-Wsl $LinuxUser "ls ~/.local/share/keyrings/ 2>/dev/null || echo SEM-DIR"
  $daemons = Invoke-Wsl $LinuxUser "daemons=`$(pgrep -fc '[g]nome-keyring-daemon' 2>/dev/null); echo daemons=`$daemons"
  $loginOut = if ($login.Out) { $login.Out.Trim() } else { '(vazio)' }
  $filesOut = if ($files.Out) { $files.Out.Trim() } else { '(vazio)' }
  $daemonOut = if ($daemons.Out) { $daemons.Out.Trim() } else { '(vazio)' }
  return "login Locked=[$loginOut] arquivos=[$filesOut] $daemonOut"
}
# Escapa a senha para embutir em 'bash -c "..."' (escapa bash + PowerShell).
function Get-PasswordQuote([string]$Password) {
  return ($Password -replace "'", "'\''") -replace '`', '``' -replace '\$', '`$' -replace '"', '`"'
}
# Converte SecureString em texto puro p/ embutir no bash (uso imediato, sem log).
# SSOT da conversao (antes copiada 3x no Install): PtrToStringUni + ZeroFreeBSTR
# juntos — sem o ZeroFreeBSTR a senha ficava no BSTR alem do necessario.
function ConvertFrom-SecureStringPlain([System.Security.SecureString]$Secure) {
  if (-not $Secure) { return '' }
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
# Normaliza a saida de 'wsl -l -q' (NULs, espacos, linhas vazias).
function ConvertFrom-WslDistroList([string[]]$Raw) {
  return ($Raw -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
# Primeiro IP de 'hostname -I' (pode vir com varios + espacos).
function Get-FirstIpAddress([string]$HostnameI) {
  return ($HostnameI -split '\s+' | Where-Object { $_ } | Select-Object -First 1)
}
# Primeiro IP do WSL. SSOT do comando (antes copiado 3x no Install):
# 'hostname -I' pode vir com varios IPs + espacos; o parse vive em Get-FirstIpAddress.
function Get-WslIpAddress([string]$Distro) {
  $d = $Distro
  if ([string]::IsNullOrWhiteSpace($d)) { try { $d = $DISTRO } catch { $d = $null } }
  if ([string]::IsNullOrWhiteSpace($d)) { $d = 'Ubuntu' }
  return Get-FirstIpAddress (wsl -d $d -- hostname -I 2>$null)
}
# Sondas de saude do desktop (SSOT): o mesmo texto de comando no Install
# (etapas 5 e 7) e no Status. Fronteira de I/O: chamadores decidem Ok/Fail/throw.
# Get-* montam o comando (puros, testaveis sem WSL); Test-* executam via Invoke-Wsl.
function Get-WslShellActiveCommand([string]$Service) {
  return "systemctl --user is-active $Service"
}
function Get-WslRdpListeningCommand([string]$Service, [int]$Port) {
  return "systemctl --user is-active $Service && ss -tlnp 2>/dev/null | grep -q ':$Port' && echo OK || echo DOWN"
}
function Test-WslShellActive([string]$LinuxUser, [string]$Service) {
  $r = Invoke-Wsl $LinuxUser (Get-WslShellActiveCommand -Service $Service)
  return ($r.Out.Trim() -eq 'active')
}
function Test-WslRdpListening([string]$LinuxUser, [string]$Service, [int]$Port) {
  $r = Invoke-Wsl $LinuxUser (Get-WslRdpListeningCommand -Service $Service -Port $Port)
  return ($r.Out -match 'OK')
}
# ViewModel puro (MVVM): validacao sem I/O, sem global, sem WSL.
# Todas retornam dados, nunca escrevem na tela nem lancam para fluxo normal
# (o orquestrador Install-WslUbuntuGui decide mensagem/throw). Cobertas no Pester.
function Test-LinuxUserName {
  [CmdletBinding()]
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    return @{ Ok = $false; Reason = 'empty' }
  }
  if ($Name -eq 'root') {
    return @{ Ok = $false; Reason = 'reserved' }
  }
  if ($Name -cnotmatch '^[a-z_][a-z0-9_-]*$') {
    return @{ Ok = $false; Reason = 'pattern' }
  }
  return @{ Ok = $true; Reason = '' }
}

# Normaliza a escolha de rede do prompt/TUI ('1' = localhost mirrored, '2' = dinamico).
# Preserva a regra historica: vazio ou qualquer coisa != '2' vira mirrored.
function Resolve-NetworkChoice {
  [CmdletBinding()]
  param([string]$NetChoice)
  $norm = if ([string]::IsNullOrWhiteSpace($NetChoice)) { '1' } else { $NetChoice.Trim() }
  if ([string]::IsNullOrWhiteSpace($norm)) { $norm = '1' }
  return @{ Normalized = $norm; WantMirrored = ($norm -ne "2") }
}

# Default do usuario Linux: salvo entre runs > windows user sanitizado > 'ubuntu'. Puro.
function Get-DefaultLinuxUser {
  [CmdletBinding()]
  param([string]$SavedUser, [string]$WindowsUser)
  $saved = if ($SavedUser) { $SavedUser.Trim() } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($saved)) { return $saved }
  $defUser = if ($WindowsUser) { ($WindowsUser.ToLower() -replace '[^a-z0-9]', '') } else { '' }
  if ([string]::IsNullOrWhiteSpace($defUser)) { $defUser = "ubuntu" }
  return $defUser
}

# Escolha usar-capturado vs criar-novo (menu TUI, indice 0 = usar). Pura: vazia
# volta ao padrao; digitado vai como esta (validacao vem depois, sem mudanca).
function Resolve-UserMenuChoice {
  [CmdletBinding()]
  param([int]$MenuIndex, [string]$TypedName, [string]$DefaultUser)
  if ($MenuIndex -ne 1) { return $DefaultUser }
  if ([string]::IsNullOrWhiteSpace($TypedName)) { return $DefaultUser }
  return $TypedName
}
# View TUI nativa (MVVM): so render + leitura de tecla, sem decisao de instalacao.
# Zero dependencia (Windows PowerShell 5.1 inbox). Com fallback Read-Host quando
# nao ha console interativo (pipe, -NoTui, hosts sem UI). Logica de indice pura
# em Move-MenuIndex para cobrir no Pester sem precisar de teclado.
function Move-MenuIndex {
  [CmdletBinding()]
  param(
    [int]$Current,
    [int]$Direction,
    [int]$Count
  )
  if ($Count -le 0) { return 0 }
  $next = $Current + $Direction
  if ($next -lt 0) { return 0 }
  if ($next -ge $Count) { return ($Count - 1) }
  return $next
}

function Test-TuiAvailable {
  [CmdletBinding()]
  param([switch]$NoTui)
  if ($NoTui) { return $false }
  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if ([Console]::IsInputRedirected) { return $false }
  } catch { return $false }
  if ($Host.Name -notmatch 'ConsoleHost') { return $false }
  return $true
}

# Menu de escolha unica com setas + Enter. Retorna o indice 0-based selecionado.
# Fallback: prompt numerico via Read-Host (mesmo contrato de retorno).
function Show-SingleChoiceMenu {
  [CmdletBinding()]
  param(
    [string]$Title,
    [string[]]$Options,
    [int]$DefaultIndex = 0,
    [switch]$NoTui
  )
  if (-not $Options -or $Options.Count -eq 0) { return 0 }
  $selected = $DefaultIndex
  if ($selected -lt 0) { $selected = 0 }
  if ($selected -ge $Options.Count) { $selected = $Options.Count - 1 }
  if (-not (Test-TuiAvailable -NoTui:$NoTui)) {
    for ($i = 0; $i -lt $Options.Count; $i++) {
      Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i])
    }
    $raw = Read-Host ("{0} [{1}]" -f $Title, ($selected + 1))
    if ([string]::IsNullOrWhiteSpace($raw)) { return $selected }
    $n = 0
    if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
      return ($n - 1)
    }
    return $selected
  }
  try {
    [Console]::CursorVisible = $false
  } catch {}
  try {
    $done = $false
    while (-not $done) {
      Write-Host ""
      Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
      for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -eq $selected) {
          Write-Host ("  > [{0}] {1}" -f ($i + 1), $Options[$i]) -ForegroundColor Green
        } else {
          Write-Host ("    [{0}] {1}" -f ($i + 1), $Options[$i])
        }
      }
      Write-Host "  (setas + Enter)" -ForegroundColor DarkGray
      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow' { $selected = Move-MenuIndex -Current $selected -Direction -1 -Count $Options.Count }
        'DownArrow' { $selected = Move-MenuIndex -Current $selected -Direction 1 -Count $Options.Count }
        'Enter' { $done = $true }
        'Escape' { $done = $true }
        default {
          $digit = "$($key.KeyChar)"
          $n = 0
          if ([int]::TryParse($digit, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            $selected = $n - 1
            $done = $true
          }
        }
      }
      if (-not $done) {
        # Reposiciona sem reler o cursor no Unix: la, CursorTop expoe DSR via
        # stdin e rouba bytes das setas/Enter digitados junto (race). Win32 usa
        # API de console real (sem DSR, sem race); Unix limpa a tela (sem flicker
        # relevante num menu de 2-3 linhas) com fallback so-anexa.
        $moved = $false
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
          try {
            $top = [Console]::CursorTop - ($Options.Count + 3)
            if ($top -lt 0) { $top = 0 }
            [Console]::SetCursorPosition(0, $top)
            $moved = $true
          } catch {}
        }
        if (-not $moved) {
          try { Clear-Host } catch {}
        }
      }
    }
  } finally {
    try {
      [Console]::CursorVisible = $true
    } catch {}
    Write-Host ""
  }
  return $selected
}

# Leitura de senha com eco de asteriscos. Retorna SecureString como Read-Host -AsSecureString.
function Read-TuiSecurePassword {
  [CmdletBinding()]
  param([string]$Prompt = "Senha", [switch]$NoTui)
  if (-not (Test-TuiAvailable -NoTui:$NoTui)) {
    return (Read-Host $Prompt -AsSecureString)
  }
  $secure = New-Object Security.SecureString
  Write-Host ("{0}: " -f $Prompt) -NoNewline
  $done = $false
  while (-not $done) {
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'Enter' { $done = $true }
      'Backspace' {
        if ($secure.Length -gt 0) {
          $secure.RemoveAt($secure.Length - 1)
          try { [Console]::Write("`b `b") } catch {}
        }
      }
      'Escape' { $secure.Clear(); $done = $true }
      default {
        if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
          $secure.AppendChar($key.KeyChar)
          try { [Console]::Write("*") } catch {}
        }
      }
    }
  }
  Write-Host ""
  $secure.MakeReadOnly()
  return $secure
}
# Monta as linhas do .rdp com login automatico (senha em blob DPAPI, so este usuario le).
function New-RdpFileContent(
  [string]$RdpHost,
  [int]$RdpPort,
  [string]$LinuxUser,
  [string]$PasswordHex,
  [string]$Resolution
) {
  $rdp = @('screen mode id:i:2', 'session bpp:i:32')
  if ($Resolution -match '^(\d+)x(\d+)$') {
    $rdp += "desktopwidth:i:$($Matches[1])"
    $rdp += "desktopheight:i:$($Matches[2])"
  }
  $rdp += "full address:s:${RdpHost}:$RdpPort"
  $rdp += "username:s:$LinuxUser"
  $rdp += "password 51:b:$PasswordHex"
  $rdp += 'prompt for credentials:i:0'
  $rdp += 'enablecredsspsupport:i:1'
  $rdp += 'authentication level:i:0'  # 0 = nao avisar: cert e autoassinado (loopback/WSL, sem MITM pratico)
  $rdp += 'promptcredentialonce:i:1'
  $rdp += 'negotiate security layer:i:1'
  return $rdp
}
# Monta o launcher .cmd (placeholders _VAL trocados aqui; assinatura preservada no fixo).
function New-LauncherContent(
  [string]$AppName,
  [string]$Distro,
  [string]$LinuxUser,
  [int]$RdpPort,
  [string]$Thumbprint,
  [string]$DiscoveryBlock,
  [string]$RewriteBlock
) {
  $cmd = @'
@echo off
rem APP_NAME - liga o WSL, garante desktop+RDP e abre o mstsc
setlocal
set DISTRO=DISTRO_VAL
set WSL=C:\Windows\System32\wsl.exe
set MSTSC=C:\Windows\System32\mstsc.exe
set RDPPATH=%LOCALAPPDATA%\Programs\APP_NAME\APP_NAME.rdp
set WSL_IP=127.0.0.1
IPDISCOVERY_VAL
if "%WSL_IP%"=="" (
  echo Nao foi possivel iniciar o Ubuntu no WSL.
  pause
  exit /b 1
)
%WSL% -d %DISTRO% -u LINUXUSER_VAL --exec env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start SHELLSVC_VAL RDPSVC_VAL.service >nul 2>&1
RDPREWRITE_VAL
start "APP_NAME" "%MSTSC%" "%RDPPATH%"
'@
  return ($cmd -replace "APP_NAME", $AppName -replace "DISTRO_VAL", $Distro `
    -replace "LINUXUSER_VAL", $LinuxUser -replace "RDPREWRITE_VAL", $RewriteBlock `
    -replace "RDP_PORT_VAL", $RdpPort -replace "THUMBPRINT_VAL", $Thumbprint `
    -replace "SHELLSVC_VAL", $script:UbuntuGuiDefaults.ShellService `
    -replace "RDPSVC_VAL", $script:UbuntuGuiDefaults.RdpService `
    -replace "IPDISCOVERY_VAL", $DiscoveryBlock)
}
# Retomada sozinha apos reboot: salva respostas (senha em DPAPI, so este usuario le),
# copia o script em execucao p/ a pasta do app e agenda reabertura via RunOnce.
# -SourceScript: caminho do script a reexecutar (no .cmd, o TEMP extraido; no modulo,
# a retomada so faz sentido via script/.cmd - o chamador passa $PSCommandPath).
function Save-ResumeState(
  [string]$SourceScript,
  [string]$ProgDir,
  [string]$ResumeFile,
  [string]$ResumePs1,
  [string]$RunOncePath,
  [string]$RunOnceName,
  [string]$LinuxUser,
  [string]$LinuxPass,
  [string]$NetChoice
) {
  if (-not (Test-Path $ProgDir)) { New-Item -ItemType Directory -Path $ProgDir -Force | Out-Null }
  Copy-Item -Path $SourceScript -Destination $ResumePs1 -Force
  $enc = [Convert]::ToBase64String(
    [Security.Cryptography.ProtectedData]::Protect(
      [Text.Encoding]::UTF8.GetBytes($LinuxPass), $null, 'CurrentUser'))
  @{ Phase = "AfterReboot"; LinuxUser = $LinuxUser; LinuxPassEnc = $enc; NetChoice = $NetChoice } |
    ConvertTo-Json -Compress | Set-Content $ResumeFile
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ResumePs1`" -Resume"
  New-ItemProperty -Path $RunOncePath -Name $RunOnceName -Value $cmd -PropertyType String -Force | Out-Null
  Ok "Retomada agendada (reabre sozinho apos o reboot)"
}
function Clear-ResumeState([string]$RunOncePath, [string]$RunOnceName, [string]$ResumeFile, [string]$ResumePs1) {
  Remove-ItemProperty -Path $RunOncePath -Name $RunOnceName -ErrorAction SilentlyContinue | Out-Null
  Remove-Item $ResumeFile, $ResumePs1 -Force -ErrorAction SilentlyContinue | Out-Null
}
# Certificado de publicador p/ assinar o .rdp (some o aviso "fornecedor desconhecido").
# Idempotente: reaproveita se ja existir no CurrentUser\My.
function New-PublisherCertificate([string]$Subject = $script:UbuntuGuiDefaults.PublisherSubject) {
  $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Subject } | Select-Object -First 1
  if ($cert) { return $cert }
  $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
    -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears($script:UbuntuGuiDefaults.CertYears)
  $store = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPublishers", "CurrentUser")
  $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
  Ok "Publicador confiavel criado"
  return $cert
}
function Install-WslUbuntuGui {
<#
.SYNOPSIS
  Instala o Ubuntu no WSL2 com desktop GNOME completo via RDP.
  Idempotente: pode rodar, reiniciar e rodar de novo - retoma de onde parou.
  Se precisar de reboot, agenda a retomada sozinha (RunOnce) - nao precisa rodar de novo.

.EXECUCAO (modulo)
  Install-WslUbuntuGui                       # interativo (pergunta tudo)
  Install-WslUbuntuGui -LinuxUser daniel -NetChoice 1 -Resume

.O QUE FAZ (tudo validado numa instalacao real Ubuntu 26.04 + GNOME 50)
  1. Habilita o WSL (wsl --install) e instala a distro (reinicia se preciso)
  2. Cria o usuario Linux, ativa systemd, instala o pacote GUI
  3. Desabilita o GDM, configura o ambiente WSLg no .bashrc
  4. Le a resolucao do monitor Windows e cria o monitor virtual igual
  5. Sobe o GNOME headless + RDP com TLS e credencial no cofre
  6. Baixa o icone oficial do Ubuntu, cria o .cmd e os atalhos
#>
[CmdletBinding()]
param(
  [string]$LinuxUser,
  [SecureString]$LinuxPassword,
  [string]$NetChoice,
  [switch]$Resume,
  [string]$Distro,
  [string]$GuiPackage,
  [string]$FallbackResolution,
  [int]$RdpPort,
  [string]$AppName,
  [switch]$NoTui
)
# (padroes em source/Private/UbuntuGui-Constants.ps1 - sem defaults aqui; ViewModel)

$script:Failures = @()
$FeedbackState = New-UbuntuGuiFeedbackState
$SCRIPT_VERSION = if ($SCRIPT_VERSION) { $SCRIPT_VERSION } else {
  try { (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\UbuntuGui.psd1')).ModuleVersion }
  catch { 'dev' }
}

# --- constantes (Model via Get-UbuntuGuiDefaults: clone; override via params) ---
$D = Get-UbuntuGuiDefaults
foreach ($n in @('Distro', 'GuiPackage', 'FallbackResolution', 'RdpPort', 'AppName')) {
  if (-not $PSBoundParameters.ContainsKey($n)) { Set-Variable $n $D[$n] }
}
$DISTRO          = $Distro
$GUI_PACKAGE     = $GuiPackage
$FALLBACK_RES    = $FallbackResolution
$RDP_PORT        = $RdpPort
$APP_NAME        = $AppName
$ICON_FILE       = "ubuntu.ico"
$ICON_URL        = $D.IconUrl
$UBUNTU_CODENAME = "resolute"               # 26.04 LTS (informativo)
$MinBuild        = $D.MinBuildMirrored
$CredTimeoutSec  = $D.CredTimeoutSec
$CredRetries     = $D.CredRetries
$KeyringReprobeSec = $D.KeyringReprobeSec
$AptRetries      = $D.AptRetries
$RdpSettleSec    = $D.RdpSettleSec
$WslWaitSec      = $D.WslShutdownWaitSec
$ShellWaitSec    = $D.ShellRestartWaitSec
$FreshWaitSec    = $D.FreshInstallWaitSec
$RebootDelaySec  = $D.RebootDelaySec
$TlsDays         = $D.TlsCertDays
$PublisherSubject = $D.PublisherSubject
$ShellService    = $D.ShellService
$ShellBinary     = $D.ShellBinary
$ShellRestartSec = $D.ShellRestartSec
$RdpService      = $D.RdpService
$GdmService      = $D.GdmService
$GdmAlias        = $D.GdmAlias
$KeyringPath     = $D.KeyringPath
$TlsCertPath     = $D.TlsCertPath
$TlsKeyPath      = $D.TlsKeyPath
$PamSudoPath     = $D.PamSudoPath
$IconSizes       = $D.IconSizes

$IconsDir  = Join-Path $env:USERPROFILE "Icons"
$ProgDir   = Join-Path $env:LOCALAPPDATA "Programs\$APP_NAME"
$CmdPath   = Join-Path $ProgDir "$APP_NAME.cmd"
$IcoPath   = Join-Path $IconsDir $ICON_FILE
$DeskLnk   = Join-Path ([Environment]::GetFolderPath("Desktop")) "$APP_NAME.lnk"
$StartLnk  = Join-Path ([Environment]::GetFolderPath("Programs")) "$APP_NAME.lnk"
$LogFile   = Join-Path $env:TEMP "$APP_NAME-install.log"
$ResumeFile = Join-Path $ProgDir "resume-state.json"
$ResumePs1  = Join-Path $ProgDir "Install-UbuntuGUI.resume.ps1"
$SavedUserFile = Join-Path $ProgDir "linux-user.txt"
$RunOncePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$RunOnceName = "UbuntuGUIResume"
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

# ============================== PRE-CHECKS ==============================
Write-Host "Ubuntu-GUI Installer v$SCRIPT_VERSION" -ForegroundColor Cyan
Step "Pre-checagens (Windows, rede, WSL)"
$os = [Environment]::OSVersion.Version
if ($os.Major -lt 10 -or ($os.Major -eq 10 -and $os.Build -lt 19041)) {
  Fail "Windows 10 2004+ ou 11 necessario (build $os)"
} else { Ok "Windows build $($os.Build)" }

if (-not (Test-Connection -ComputerName "archive.ubuntu.com" -Count 1 -Quiet)) {
  Warn "Sem resposta de archive.ubuntu.com - a instalacao APT pode falhar"
} else { Ok "Rede alcanca o repositorio Ubuntu" }

# Resolucao real do monitor primario ( cai para $FALLBACK_RES se falhar )
$RES = $FALLBACK_RES
try {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $cand = "$($b.Width)x$($b.Height)"
  if ($cand -match '^\d+x\d+$') { $RES = $cand; Ok "Resolucao do monitor: $RES" }
  else { Warn "Resolucao ilegivel, usando $RES" }
} catch { Warn "Nao deu pra ler a resolucao, usando $RES" }

# Retomada sozinha apos reboot (-Resume): reaproveita as respostas salvas, sem perguntar.
if ($Resume -and (Test-Path $ResumeFile)) {
  try {
    $st = Get-Content $ResumeFile -Raw | ConvertFrom-Json
    $LinuxUser = $st.LinuxUser
    $LinuxPass = [Text.Encoding]::UTF8.GetString(
      [Security.Cryptography.ProtectedData]::Unprotect(
        [Convert]::FromBase64String($st.LinuxPassEnc), $null, 'CurrentUser'))
    $NetChoice = $st.NetChoice
    if ([string]::IsNullOrWhiteSpace($NetChoice)) { $NetChoice = "1" }
    $PWQ = Get-PasswordQuote $LinuxPass
    $WantMirrored = ($NetChoice.Trim() -ne "2")
    Ok "Retomando sozinho apos o reboot (usuario $LinuxUser)"
  } catch {
    Warn "Estado de retomada ilegivel - segue perguntando de novo"
    $Resume = $false
  }
}
if (-not $Resume) {
  # Usuario/senha Linux (reaproveita padrao Ubuntu: minusculas, sem espaco).
  # O nome fica salvo entre runs: na 1a instalacao ele sera o usuario criado pelo script
  # (nao precisa digitar no instalador do Ubuntu); nos reruns ele ja vem pronto.
  if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $savedRaw = if (Test-Path $SavedUserFile) { (Get-Content $SavedUserFile -Raw) } else { '' }
    $defUser = Get-DefaultLinuxUser -SavedUser $savedRaw -WindowsUser $env:USERNAME
    if (Test-TuiAvailable -NoTui:$NoTui) {
      $userIdx = Show-SingleChoiceMenu -Title "Usuario Linux" `
        -Options @("Usar '$defUser'", 'Criar um novo') `
        -DefaultIndex 0 -NoTui:$NoTui
      $typedUser = if ($userIdx -eq 1) { Read-Host "Novo usuario Linux" } else { '' }
      $LinuxUser = Resolve-UserMenuChoice -MenuIndex $userIdx -TypedName $typedUser -DefaultUser $defUser
    } else {
      $LinuxUser = Read-Host "Usuario Linux [$defUser]"
      if ([string]::IsNullOrWhiteSpace($LinuxUser)) { $LinuxUser = $defUser }
    }
  }
  $userCheck = Test-LinuxUserName -Name $LinuxUser
  if (-not $userCheck.Ok -and $userCheck.Reason -eq 'reserved') {
    Fail "O usuario 'root' e reservado - escolha outro nome"; throw "Usuario reservado"
  }
  if (-not $userCheck.Ok) {
    Fail "Usuario '$LinuxUser' invalido (use minusculas, numeros, _ ou -)"; throw "Usuario Linux invalido"
  }
  if ($LinuxPassword) {
    $LinuxPass = ConvertFrom-SecureStringPlain $LinuxPassword
  } else {
    $sec1 = Read-TuiSecurePassword -Prompt "Senha do usuario $LinuxUser" -NoTui:$NoTui
    $sec2 = Read-TuiSecurePassword -Prompt "Confirme a senha" -NoTui:$NoTui
    $LinuxPass = ConvertFrom-SecureStringPlain $sec1
    $LinuxPass2 = ConvertFrom-SecureStringPlain $sec2
    if ($LinuxPass -cne $LinuxPass2 -or [string]::IsNullOrEmpty($LinuxPass)) {
      Fail "Senhas diferentes ou vazias - rode de novo"; throw "Senhas diferentes ou vazias"
    }
  }
  # $PWQ = senha pronta para embutir em 'bash -c "..."' (escapa bash + PowerShell)
  $PWQ = Get-PasswordQuote $LinuxPass
  Ok "Usuario Linux: $LinuxUser"

  # Modo de rede: [1] localhost fixo 127.0.0.1 via mirrored (recomendado, padrao: endpoint
  # estavel, sem redescoberta, assinatura do .rdp sempre valida) ou [2] IP dinamico
  # descoberto automaticamente a cada clique (p/ Windows sem mirrored).
  # View (TUI com fallback Read-Host); regra pura em Resolve-NetworkChoice.
  if ([string]::IsNullOrWhiteSpace($NetChoice)) {
    if (Test-TuiAvailable -NoTui:$NoTui) {
      $menuIdx = Show-SingleChoiceMenu -Title "Modo de rede" `
        -Options @('localhost fixo 127.0.0.1 (recomendado)', 'IP dinamico a cada clique') `
        -DefaultIndex 0 -NoTui:$NoTui
      $NetChoice = if ($menuIdx -eq 1) { "2" } else { "1" }
    } else {
      $NetChoice = Read-Host "Modo de rede [1] localhost fixo 127.0.0.1 (recomendado) ou [2] IP dinamico a cada clique [1]"
    }
  }
  $NetResolved = Resolve-NetworkChoice -NetChoice $NetChoice
  $NetChoice = $NetResolved.Normalized
  $WantMirrored = $NetResolved.WantMirrored
  if ($WantMirrored) { Ok "Modo: localhost fixo 127.0.0.1 (masked)" }
  else { Write-Host "  Modo: IP dinamico - o atalho identifica o IP automaticamente a cada clique" -ForegroundColor Yellow }

  if (Test-Path $ResumeFile) {
    Clear-ResumeState $RunOncePath $RunOnceName $ResumeFile $ResumePs1
    Warn "Retomada pendente cancelada (novo run manual)"
  }
}

# ============================== 1. WSL + DISTRO ==============================
Step "1/7 WSL, rede e distro $DISTRO"
$distros = ConvertFrom-WslDistroList (wsl -l -q 2>$null)
if ($distros -notcontains $DISTRO) {
  Write-Host "  Instalando WSL + $DISTRO..." -ForegroundColor Yellow
  wsl --install -d $DISTRO
  Write-Host "  Nao abra o app Ubuntu: o script cria o usuario '$LinuxUser' sozinho (sem digitar no instalador do Ubuntu)" -ForegroundColor Yellow
  Start-Sleep -Seconds $FreshWaitSec
  wsl -d $DISTRO -- true 2>$null
  if ($LASTEXITCODE -eq 0) { Ok "WSL pronto sem reboot - seguindo sozinho" }
  else {
    Save-ResumeState $PSCommandPath $ProgDir $ResumeFile $ResumePs1 $RunOncePath $RunOnceName $LinuxUser $LinuxPass $NetChoice
    $rb = Read-Host "Reiniciar o Windows agora para continuar sozinho? [S/n]"
    if ([string]::IsNullOrWhiteSpace($rb) -or $rb.Trim().ToLower().StartsWith("s")) {
      Write-Host "  Reiniciando em ${RebootDelaySec}s (cancele com: shutdown /a)..." -ForegroundColor Yellow
      shutdown /r /t $RebootDelaySec /c "Ubuntu-GUI: reiniciando p/ continuar a instalacao sozinho"
    } else {
      Write-Host "  Sem pressa: ao ligar de novo, a instalacao reabre sozinha (sem clicar de novo)" -ForegroundColor Yellow
    }
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    return
  }
}
Ok "Distro $DISTRO presente"
wsl -d $DISTRO -- true 2>$null
if ($LASTEXITCODE -ne 0) {
  Fail "Distro instalada mas nao inicia - abra o Ubuntu uma vez e rode de novo"
  throw "Distro nao inicia"
}

# Mirrored networking (Win11 22H2+, build 22621+): RDP vira 127.0.0.1 fixo.
# Sem suporte ou modo dinamico escolhido: IP dinamico descoberto a cada clique.
$UseMirrored = $WantMirrored -and ($os.Build -ge $MinBuild)
if ($WantMirrored -and ($os.Build -lt $MinBuild)) {
  Warn "Mirrored exige Win11 22H2+ (build $MinBuild+); usando IP dinamico"
}
$RdpHost = '127.0.0.1'
$wslRestartNeeded = $false
if ($UseMirrored) {
  $wslCfg = Join-Path $env:USERPROFILE '.wslconfig'
  $txt = if (Test-Path $wslCfg) { Get-Content $wslCfg -Raw } else { '' }
  if ($txt -notmatch '(?m)^networkingMode\s*=') {
    if ($txt -notmatch '(?m)^\[wsl2\]') { $txt = "[wsl2]`r`n" + $txt }
    $txt = $txt -replace '(?m)^(\[wsl2\].*)$', "`$1`r`nnetworkingMode=mirrored"
    [IO.File]::WriteAllText($wslCfg, $txt.Trim() + "`r`n")
    $wslRestartNeeded = $true
  }
  Ok "Mirrored networking (RDP fixo em 127.0.0.1)"
} else {
  $RdpHost = Get-WslIpAddress -Distro $DISTRO
  Ok "IP dinamico - cada clique detecta sozinho ($RdpHost)"
}

# ============================== 2. USUARIO + SYSTEMD ==============================
Step "2/7 Usuario Linux e systemd"
$r = Invoke-WslRoot "id -u $LinuxUser 2>/dev/null || echo MISSING"
if ($r.Out -match "MISSING") {
  Write-Host "  Criando usuario $LinuxUser (novo)..." -ForegroundColor Yellow
  $r = Invoke-WslRoot "useradd -m -s /bin/bash '$LinuxUser' && echo '$LinuxUser`:$PWQ' | chpasswd && usermod -aG sudo '$LinuxUser'"
  if ($r.Code -ne 0) { Fail "Nao criei o usuario: $($r.Out)" }
  else { Ok "Usuario $LinuxUser criado" }
} else {
  # TRAVA: conta existente nunca e apagada nem recriada (home e arquivos intactos).
  # So a senha do Linux e atualizada p/ digitada (iguala RDP + login automatico).
  Ok "Usuario $LinuxUser ja existe - NADA sera apagado (home e arquivos intactos)"
  Write-Host "  Atualizando a senha do Linux para a digitada..." -ForegroundColor Yellow
  $rp = Invoke-WslRoot "echo '$LinuxUser`:$PWQ' | chpasswd"
  if ($rp.Code -eq 0) { Ok "Senha do Linux atualizada" }
  else { Fail "Nao atualizei a senha: $($rp.Out)"; throw "Senha nao atualizada" }
}
if (-not (Test-Path $ProgDir)) { New-Item -ItemType Directory -Path $ProgDir -Force | Out-Null }
[IO.File]::WriteAllText($SavedUserFile, $LinuxUser)
if ((Invoke-WslRoot "id -u $LinuxUser 2>/dev/null").Code -eq 0) { Ok "Usuario $LinuxUser pronto" }

# wsl.conf com systemd + usuario padrao (exige 'wsl --shutdown' para valer)
$r = Invoke-WslRoot "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && grep -q 'default=$LinuxUser' /etc/wsl.conf 2>/dev/null && echo OK || echo FIX"
if ($r.Out -match "FIX") {
  Invoke-WslRoot "printf '[boot]\nsystemd=true\n[user]\ndefault=$LinuxUser\n' > /etc/wsl.conf" | Out-Null
  Write-Host "  Reiniciando o WSL para ativar o systemd..." -ForegroundColor Yellow
  wsl --shutdown
  Start-Sleep -Seconds $WslWaitSec
}
$r = Invoke-Wsl $LinuxUser "systemctl is-system-running 2>&1 | head -n 1"
if ($r.Out -match "running|degraded") { Ok "systemd ativo ($($r.Out.Trim()))" }
else { Fail "systemd nao subiu - rode 'wsl --shutdown' e execute de novo"; throw "systemd nao subiu" }

# ============================== 3. PACOTE GUI ==============================
Step "3/7 Pacote $GUI_PACKAGE (+ openssl, PIL)"
$apt = "env DEBIAN_FRONTEND=noninteractive"  # via 'env': sudo nao entende 'export'
$r = Invoke-Wsl $LinuxUser "dpkg -l $GUI_PACKAGE 2>/dev/null | grep -q '^ii' && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  Write-Host "  apt update + instalacao (~2 GB, demora)..." -ForegroundColor Yellow
  $ok = $false
  for ($i = 1; $i -le $AptRetries -and -not $ok; $i++) {
    $r = Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get update 2>&1 | tail -n 1"
    $r = Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -y $GUI_PACKAGE gnome-remote-desktop openssl python3-pil curl 2>&1 | tail -n 2"
    $ok = ((Invoke-Wsl $LinuxUser "dpkg -l $GUI_PACKAGE 2>/dev/null | grep -q '^ii'").Code -eq 0)
    if (-not $ok) { Warn "Tentativa $i falhou, tentando de novo..." }
  }
  if (-not $ok) { Fail "APT nao concluiu apos $AptRetries tentativas - veja o log"; throw "APT falhou" }
}
Ok "$GUI_PACKAGE instalado"
$r = Invoke-Wsl $LinuxUser "gnome-shell --version 2>&1"
Ok $r.Out.Trim()

# GDM nunca no WSL (conflita com o Weston do WSLg)
Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S systemctl stop $GdmService 2>/dev/null; printf '%s\n' '$PWQ' | sudo -S systemctl disable $GdmService $GdmAlias 2>/dev/null | tail -n 1" | Out-Null
Ok "GDM parado e desabilitado"

# Bloco WSLg no .bashrc (idempotente: so adiciona uma vez)
$marker = "WSLg: expoe o socket Wayland"
$r = Invoke-Wsl $LinuxUser "grep -q '$marker' ~/.bashrc && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  $block = @'
# WSLg: expoe o socket Wayland no runtime dir padrao + tipo de sessao p/ apps GNOME
if [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
  [ -e "$XDG_RUNTIME_DIR/wayland-0" ] || ln -sf /mnt/wslg/runtime-dir/wayland-0 "$XDG_RUNTIME_DIR/wayland-0"
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" DISPLAY="${DISPLAY:-:0}" XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-ubuntu:GNOME}"
'@
  $block | wsl -d $DISTRO -u $LinuxUser --exec bash -c "cat >> ~/.bashrc"
  Ok "Bloco WSLg no .bashrc"
} else { Ok "Bloco WSLg ja estava no .bashrc" }

# ============================== 4. SHELL HEADLESS ==============================
Step "4/7 Desktop GNOME headless ($RES)"
$unit = @"
[Unit]
Description=GNOME Shell headless (desktop Ubuntu completo via RDP)
Before=gnome-remote-desktop.service
After=dbus.socket
Wants=dbus.socket
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=XDG_RUNTIME_DIR=%t
Environment=LIBGL_ALWAYS_SOFTWARE=1
ExecStart=/usr/bin/$ShellBinary --mode=ubuntu --wayland --headless --no-x11 --virtual-monitor $RES
Restart=on-failure
RestartSec=$ShellRestartSec
[Install]
WantedBy=default.target
"@
$unit | wsl -d $DISTRO -u $LinuxUser --exec bash -c "mkdir -p ~/.config/systemd/user && cat > ~/.config/systemd/user/$ShellService"
Invoke-Wsl $LinuxUser "systemctl --user daemon-reload; systemctl --user enable $ShellService 2>&1 | tail -n 1" | Out-Null
# Reinicia so se nao houver Shell rodando exatamente nesta resolucao (rerun seguro)
$r = Invoke-Wsl $LinuxUser "pgrep -af '$ShellBinary.*--virtual-monitor $RES' | grep -qv 'bin/sh' && echo CURRENT || echo STALE"
if ($r.Out -match "STALE") {
  Write-Host "  (Re)iniciando o Shell em $RES..." -ForegroundColor Yellow
  Invoke-Wsl $LinuxUser "systemctl --user restart $ShellService" | Out-Null
  Start-Sleep -Seconds $ShellWaitSec
}
if (Test-WslShellActive -LinuxUser $LinuxUser -Service $ShellService) { Ok "GNOME Shell ativo em $RES" }
else { Fail "Shell nao subiu - journal: systemctl --user status gnome-shell-headless"; throw "Shell nao subiu" }
Invoke-Wsl $LinuxUser "mkdir -p ~/Desktop" | Out-Null

# ============================== 5. RDP + COFRE ==============================
Step "5/7 RDP com TLS e credencial"
# Certificado autoassinado (idempotente)
$r = Invoke-Wsl $LinuxUser "test -f $TlsCertPath && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  Invoke-Wsl $LinuxUser "mkdir -p ~/.local/share/gnome-remote-desktop && openssl req -x509 -newkey rsa:2048 -keyout $TlsKeyPath -out $TlsCertPath -days $TlsDays -nodes -subj '/CN=ubuntu-wsl'" | Out-Null
  Ok "Certificado TLS criado"
}
# Daemon no ar ANTES do PAM (o gkr-pam nao consegue subir sozinho aqui:
# "couldn't setup credentials" no auth.log). Com ele rodando, o PAM so cria/destrava.
$Uid = (Invoke-Wsl $LinuxUser "id -u").Out.Trim()
$busRepair = Repair-WslKeyringBus -LinuxUser $LinuxUser -Uid $Uid -Distro $DISTRO
if ($busRepair.Repaired) { Warn "Bus do cofre reparado ($($busRepair.Detail))" }
if (Start-WslKeyringDaemon -LinuxUser $LinuxUser -Uid $Uid) { Ok "Daemon do cofre no ar" } else { Warn "Daemon do cofre nao respondeu - PAM tenta subir sozinho" }
# Cofre login via PAM do sudo (cria com a senha do usuario; revertido em seguida).
# O tee recebe SENHA + CONTEUDO no mesmo stdin: o sudo consome a 1a linha, o resto anexa.
$kc = New-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -KeyringPath $KeyringPath -PamSudoPath $PamSudoPath
if ($kc.Fresh) { Ok "Cofre login criado com a senha informada" }
elseif ($kc.Created) { Ok "Cofre login pronto" }
else { Fail "Cofre nao criado (o PAM via sudo nao criou sozinho: confira ~/.local/share/keyrings/login.keyring e backups *.bak* - sem o arquivo nenhum unlock funciona)"; throw "Cofre nao criado" }
if ((Invoke-Wsl $LinuxUser "grep -c pam_gnome_keyring $PamSudoPath 2>/dev/null").Out.Trim() -ne "0") {
  Fail "/etc/pam.d/sudo nao voltou ao original - verifique"; throw "PAM adulterado"
}
Ok "/etc/pam.d/sudo intacto"

# Rerun apos reboot: o cofre volta bloqueado e o set-credentials travaria no prompt.
# Gestor de cofre (Invoke-VaultCredential.ps1): unlock falhou = fail fast com
# instrucao, nunca 2x60s de retry queimado a toa (sintoma: tentativas mudas).
# ($Uid ja calculado antes do prestart, acima.)
Write-Host "  Desbloqueando o cofre..." -ForegroundColor Yellow
# Unlock + sonda na MESMA chamada (daemon pode ser efemero: ativado por D-Bus,
# some em segundos; duas chamadas podem atingir instancias diferentes).
# Se o PAM ja destravou (sudo -S true acima), pula o unlock: menos partes
# moveis, e diagnostica se o caminho PAM funciona nesta maquina.
$pamUnlocked = Test-WslKeyringUnlocked -LinuxUser $LinuxUser -Uid $Uid
if ($pamUnlocked) { Ok "Cofre ja destravado via PAM (pulando unlock)" }
$uk = if ($pamUnlocked) { @{ UnlockCode = 0; State = 'Unlocked'; Probe = 'via PAM'; UnlockText = '(via PAM)' } } else { UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid }
if ($uk.UnlockCode -ne 0) {
  Fail "Cofre nao desbloqueou com a senha informada ($($uk.UnlockText)) - cofre de outro run? No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo com UMA senha definitiva (nunca rm: sem o arquivo o PAM nao recria sozinho)"
  throw "Cofre bloqueado"
}
# Sonda sem prompt antes de gravar: trancado = set-credentials travaria ate o
# timeout. Uma repeticao apos a espera absorve ativacao lenta do D-Bus; se
# falhar de novo, classifica Locked (cofre de outro run) vs Error (sonda
# quebrou: D-Bus/sessao, outro conserto - nao apague o keyring a toa).
if ($uk.State -ne 'Unlocked') {
  Start-Sleep -Seconds $KeyringReprobeSec
  $uk2 = UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid
  if ($uk2.State -eq 'Unlocked') { Ok "Cofre destravou na re-sonda" }
  elseif ($uk2.State -eq 'Missing') {
    Fail "Colecao login ausente (daemon responde mas sem colecao: arquivo ~/.local/share/keyrings/login.keyring sumiu ou daemon anterior a ele - retorno: $($uk2.Probe)) - restaure um backup *.bak* para login.keyring (com cp, sem apagar o backup) e rode de novo"
    throw "Cofre ausente"
  }
  elseif ($uk2.State -eq 'Error') {
    Fail "Sonda do cofre falhou (nao e 'trancado': D-Bus/sessao?) - retorno: $($uk2.Probe) - unlock disse: $($uk2.UnlockText) - tente 'wsl --shutdown' e rode de novo"
    throw "Cofre bloqueado"
  } else {
    $lockDetail = Get-WslKeyringLockDetail -LinuxUser $LinuxUser -Uid $Uid
    if (Test-WslUnlockExitMeaningful -LinuxUser $LinuxUser -Uid $Uid) {
      Fail "Senha incorreta para o cofre existente (teste de controle com senha falsa foi rejeitado; unlock disse: $($uk2.UnlockText); $lockDetail) - No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo com UMA senha definitiva (nunca rm: sem o arquivo o PAM nao recria sozinho)"
      throw "Cofre bloqueado"
    } else {
      Warn "Senha nao confere para o cofre existente (sudo passou mas cofre segue trancado; unlock por stdin nao valida nada aqui: senha falsa tambem sai 0) - recriando o cofre com a senha informada (backup automatico, original preservado)"
      $rk = Reset-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid -KeyringPath $KeyringPath -PamSudoPath $PamSudoPath
      if (-not $rk.Recreated) {
        Fail "Recriacao via PAM falhou e o original foi restaurado de $($rk.Backup) ($lockDetail) - destrave uma vez via Senhas e chaves (seahorse), mantenha ABERTO e rode de novo"
        throw "Cofre bloqueado"
      }
      Ok "Cofre recriado com a senha informada (original em $($rk.Backup))"
      $uk2 = UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid
      if ($uk2.State -eq 'Unlocked') { Ok "Cofre destravou apos recriar" }
      else {
        Fail "Cofre recriado mas segue trancado (retorno: $($uk2.Probe) - unlock disse: $($uk2.UnlockText)) - tente 'wsl --shutdown' e rode de novo"
        throw "Cofre bloqueado"
      }
    }
  }
}

# Credencial + TLS + servico (com retry, sem prompt: cofre ja existe destravado).
# O set-credentials pode levar ate ~60s por tentativa: avisa + mostra tentativa p/ nao parecer travado.
Write-Host "  Gravando credencial RDP no cofre (pode levar ate ~${CredTimeoutSec}s por tentativa, nao feche)..." -ForegroundColor Yellow
$stored = $false
for ($i = 1; $i -le $CredRetries -and -not $stored; $i++) {
  Write-Host "  Tentativa $i/$CredRetries..." -NoNewline
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $gc = Set-WslRdpCredential -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid -TimeoutSec $CredTimeoutSec
  # Verifica a credencial de verdade no daemon (o cofre existir nao basta: item vazio tambem conta no busctl)
  $stored = Test-WslRdpCredential -LinuxUser $LinuxUser -Uid $Uid
  $sw.Stop()
  if ($stored) { Write-Host " ok ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green }
  else { Write-Host " ainda nao ($([int]$sw.Elapsed.TotalSeconds)s): $($gc.Out.Trim())" -ForegroundColor Yellow }
}
if (-not $stored) {
  Fail "Credencial RDP nao gravou no cofre (ultima saida: $($gc.Out.Trim()) - cofre trancado com outra senha? No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo (nunca rm: sem o arquivo o PAM nao recria sozinho))"
  throw "Credencial nao gravada"
}
Ok "Credencial RDP gravada"
# Porta fora da 3389 (erro 0x708 no loopback): idempotente, migra quem instalou na 3389.
Write-Host "  Aplicando TLS/porta $RDP_PORT e reiniciando o servico..." -ForegroundColor Yellow
Invoke-Wsl $LinuxUser "grdctl rdp set-tls-cert $TlsCertPath 2>/dev/null; grdctl rdp set-tls-key $TlsKeyPath 2>/dev/null; grdctl rdp set-port $RDP_PORT 2>/dev/null; grdctl rdp disable-view-only 2>/dev/null; grdctl rdp enable 2>/dev/null; systemctl --user enable $RdpService 2>/dev/null; systemctl --user restart $RdpService 2>&1 | tail -n 1" | Out-Null
Start-Sleep -Seconds $RdpSettleSec
if (Test-WslRdpListening -LinuxUser $LinuxUser -Service $RdpService -Port $RDP_PORT) { Ok "RDP ouvindo na porta $RDP_PORT" }
else { Fail "RDP nao subiu"; throw "RDP nao subiu" }

# ============================== 6. ICONE + ATALHOS ==============================
Step "6/7 Icone e atalhos ($APP_NAME)"
foreach ($d in @($IconsDir, $ProgDir)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
# Icone oficial (Circle of Friends 2022) -> .ico multi-tamanho via PIL no WSL
if (-not (Test-Path $IcoPath)) {
  # C:\... -> /mnt/c/... (sintaxe compativel com Windows PowerShell 5.1)
  $wIco = '/mnt/' + $IcoPath.Substring(0, 1).ToLower() + ($IcoPath.Substring(2) -replace '\\', '/')
  $iconSizesArg = ($IconSizes | ForEach-Object { "($_ ,$_)" }) -join ','
  $r = Invoke-Wsl $LinuxUser "curl -sL --max-time 60 -o /tmp/cof.png '$ICON_URL' && python3 -c `"from PIL import Image; im=Image.open('/tmp/cof.png').convert('RGBA'); S=max(im.size); sq=Image.new('RGBA',(S,S),(0,0,0,0)); sq.paste(im,((S-im.width)//2,(S-im.height)//2),im); sq.save('$wIco',sizes=[$iconSizesArg])`"" 2>&1
  if (Test-Path $IcoPath) { Ok "Icone Ubuntu baixado e convertido" }
  else { Warn "Icone oficial falhou, usando o do mstsc ($($r.Out))" }
} else { Ok "Icone ja existia" }

# Certificado de publicador p/ assinar o .rdp (some o aviso "fornecedor desconhecido").
$pubCert = New-PublisherCertificate -Subject $PublisherSubject

# Endpoint real: localhost so se responde AGORA (mirrored ja valendo + RDP de pe).
# Instalacao fresca sempre cai no dinamico e vira localhost no rerun pos-reboot.
# Modo dinamico escolhido: pula o probe e vai direto ao IP por clique.
$LocalhostLive = $false
if ($UseMirrored) {
  try { $LocalhostLive = Test-NetConnection -ComputerName 127.0.0.1 -Port $RDP_PORT -WarningAction SilentlyContinue | Select-Object -ExpandProperty TcpTestSucceeded }
  catch { $LocalhostLive = $false }
}
if ($LocalhostLive) { $RdpHost = '127.0.0.1'; Ok "RDP responde em localhost (endpoint fixo)" }
elseif ($UseMirrored) { Ok "RDP via IP dinamico por enquanto (localhost ainda nao vale; rerun fixa)" }
else { Ok "RDP via IP dinamico (cada clique detecta sozinho)" }
$discBlock = if ($LocalhostLive) { 'rem IP fixo via mirrored networking (127.0.0.1)' }
  else { 'rem IP descoberto automaticamente a cada clique (hostname -I)' + "`r`n" + 'for /f "tokens=1" %%i in (''%WSL% -d %DISTRO% -- hostname -I 2^>nul'') do set WSL_IP=%%i' }
# Fixo: nao reescreve o .rdp (assinatura continua valida). Dinamico: reescreve + reassina.
$rewriteBlock = if ($LocalhostLive) { 'rem IP/porta fixos via mirrored (127.0.0.1:RDP_PORT_VAL) - .rdp assinado, nao alterar' }
  else { 'powershell -NoProfile -Command "(Get-Content ''%RDPPATH%'') -replace ''^full address:s:.*'',''full address:s:%WSL_IP%:RDP_PORT_VAL'' | Set-Content ''%RDPPATH%''; & %SystemRoot%\System32\rdpsign.exe /sha256 THUMBPRINT_VAL ''%RDPPATH%'' >nul 2>&1"' }
$cmd = New-LauncherContent -AppName $APP_NAME -Distro $DISTRO `
  -LinuxUser $LinuxUser -RdpPort $RDP_PORT -Thumbprint $pubCert.Thumbprint `
  -DiscoveryBlock $discBlock -RewriteBlock $rewriteBlock
[IO.File]::WriteAllText($CmdPath, $cmd)
Ok "Script em $CmdPath"

# .rdp com login automatico: senha em blob DPAPI (so este usuario Windows le)
$RdpPath = Join-Path $ProgDir "$APP_NAME.rdp"
Add-Type -AssemblyName System.Security
$blob = [Security.Cryptography.ProtectedData]::Protect(
  [Text.Encoding]::Unicode.GetBytes($LinuxPass), $null, 'CurrentUser')
$hex = ($blob | ForEach-Object { $_.ToString('x2') }) -join ''
if (-not $LocalhostLive) { $RdpHost = Get-WslIpAddress -Distro $DISTRO }
$rdp = New-RdpFileContent -RdpHost $RdpHost -RdpPort $RDP_PORT -LinuxUser $LinuxUser -PasswordHex $hex -Resolution $RES
[IO.File]::WriteAllLines($RdpPath, $rdp)
if (Test-Path $RdpPath) { Ok "RDP com login automatico em $RdpPath" }
else { Fail "Arquivo .rdp nao criado"; throw "RDP nao criado" }

# Assina o .rdp p/ sumir o aviso "fornecedor desconhecido" (rerun reassina apos regerar).
& "$env:SystemRoot\System32\rdpsign.exe" /sha256 $pubCert.Thumbprint "$RdpPath" | Out-Null
if ([IO.File]::ReadAllText($RdpPath) -match 'signature:s:') { Ok "RDP assinado (sem aviso de fornecedor)" }
else { Warn "Assinatura do .rdp falhou - o aviso de fornecedor pode continuar" }

# .lnk no Desktop + Iniciar, com o icone (fallback: icone do mstsc)
$icoSpec = if (Test-Path $IcoPath) { "$IcoPath,0" } else { "C:\Windows\System32\mstsc.exe,0" }
$ws = New-Object -ComObject WScript.Shell
foreach ($lnk in @($DeskLnk, $StartLnk)) {
  $s = $ws.CreateShortcut($lnk)
  $s.TargetPath = $CmdPath
  $s.WorkingDirectory = $ProgDir
  $s.IconLocation = $icoSpec
  $s.Description = "Abre o desktop GNOME do Ubuntu (WSL) via RDP"
  $s.WindowStyle = 7
  $s.Save()
}
if ((Test-Path $DeskLnk) -and (Test-Path $StartLnk)) { Ok "Atalhos no Desktop e no Iniciar" }
else { Fail "Atalhos nao criados"; throw "Atalhos nao criados" }

# ============================== 7. VERIFICACAO ==============================
Step "7/7 Verificacao ponta a ponta"
$checks = @(
  @{ N = "Shell headless ativo"; C = (Get-WslShellActiveCommand -Service $ShellService); Want = "^active$" },
  @{ N = "Dock do Ubuntu ativo"; C = "gnome-extensions list --enabled 2>/dev/null | grep -q ubuntu-dock && echo YES || echo NO"; Want = "YES" },
  @{ N = "RDP ouvindo :$RDP_PORT"; C = (Get-WslRdpListeningCommand -Service $RdpService -Port $RDP_PORT); Want = "OK" }
)
foreach ($t in $checks) {
  $r = Invoke-Wsl $LinuxUser $t.C
  if ($r.Out -match $t.Want) { Ok $t.N } else { Fail "$($t.N) (ret: $($r.Out.Trim()))" }
}
if (Test-Path $RdpPath) { Ok "Login automatico pronto (abre direto, sem senha)" }
else { Fail "Arquivo .rdp sumiu"; throw "RDP sumiu" }

Write-Host ""
$FeedbackState = @{ Failures = @($script:Failures) }
$LiveFailures = @(Get-UbuntuGuiFailures -State $FeedbackState)
if ($LiveFailures.Count -eq 0) {
  Remove-Item $LogFile -Force -ErrorAction SilentlyContinue  # higiene: transcript guarda a senha
  Clear-ResumeState $RunOncePath $RunOnceName $ResumeFile $ResumePs1  # higiene: estado de retomada guarda a senha (DPAPI)
  $ip = Get-WslIpAddress -Distro $DISTRO
  if ($LocalhostLive) { $ip = '127.0.0.1' }
  Write-Host "TUDO PRONTO" -ForegroundColor Green
  Write-Host "  Desktop : duplo clique em $APP_NAME (ou mstsc em ${ip}:$RDP_PORT)"
  Write-Host "  Login RDP : automatico (usuario e senha salvos no .rdp)"
  Write-Host "  Resolucao do desktop: $RES"
  if ($wslRestartNeeded) { Write-Host "  REINICIE o Windows (ou rode 'wsl --shutdown') p/ valer o mirrored" -ForegroundColor Yellow }
} else {
  Write-Host "TERMINOU COM FALHAS:" -ForegroundColor Red
  $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host "Rode de novo (retoma sozinho) ou veja $LogFile (tem a senha dentro - apague depois)"
  throw "Instalacao terminou com falhas"
}
}

function Get-WslUbuntuGuiStatus {
<#
.SYNOPSIS
  Le o estado do desktop Ubuntu/WSL (somente leitura, seguro rodar sempre).
.EXEMPLO
  Get-WslUbuntuGuiStatus -Distro Ubuntu -LinuxUser daniel | Format-List
#>
[CmdletBinding()]
param(
  [string]$Distro,
  [Parameter(Mandatory)] [string]$LinuxUser,
  [int]$RdpPort = 0
)
# (padroes em source/Private/UbuntuGui-Constants.ps1 - sem defaults aqui; ViewModel)
$D = Get-UbuntuGuiDefaults
foreach ($n in @('Distro', 'RdpPort')) {
  if (-not $PSBoundParameters.ContainsKey($n)) { Set-Variable $n $D[$n] }
}
$DISTRO = $Distro
$RDP_PORT = $RdpPort
$shellActive = Test-WslShellActive -LinuxUser $LinuxUser -Service $D.ShellService
$rdpUp = Test-WslRdpListening -LinuxUser $LinuxUser -Service $D.RdpService -Port $RDP_PORT
$Uid = (Invoke-Wsl $LinuxUser "id -u").Out.Trim()
$credSet = Test-WslRdpCredential -LinuxUser $LinuxUser -Uid $Uid
return [pscustomobject]@{
  Distro           = $Distro
  LinuxUser        = $LinuxUser
  RdpPort          = $RdpPort
  ShellActive      = $shellActive
  RdpListening     = $rdpUp
  CredentialsSet   = $credSet
}
}
try {
  Install-WslUbuntuGui -Resume:$Resume
  exit 0
} catch {
  # Sem eco duplicado: falha controlada ja imprimiu [FALHA] com detalhe.
  if ($env:UBUNTUGUI_FAIL_REPORTED) { Write-Host "FALHA (detalhes acima)" -ForegroundColor Red }
  else { Write-Host "FALHA: $($_.Exception.Message)" -ForegroundColor Red }
  exit 1
} finally {
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
}
:::PS1-BODY-END
