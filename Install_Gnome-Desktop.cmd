@echo off
rem Instalador Ubuntu GUI em ARQUIVO UNICO: extrai o PowerShell embutido
rem abaixo (texto claro, auditavel) para a pasta TEMP e executa.
setlocal
rem Auto-elevacao na caixa preta: sem admin, relanca ESTE .cmd elevado
rem (1 clique no UAC; o ps1 embutido nao re-eleva - ve UBUNTUGUI_FROM_CMD).
set UBUNTUGUI_FROM_CMD=1
net session >nul 2>&1
if not errorlevel 1 goto :RUNPS1
echo Elevando a admin (confirme no UAC uma vez)...
if "%~1"=="" (powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop } catch { exit 1 }") else (powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -ErrorAction Stop } catch { exit 1 }")
if errorlevel 1 (
  echo Sem elevacao: segue sem admin (algumas etapas avisam e pulam)...
  goto :RUNPS1
)
exit /b 0
:RUNPS1
powershell -NoProfile -Command "$a=':::PS1-BODY'+'-START'; $b=':::PS1-BODY'+'-END'; $t=[IO.File]::ReadAllText('%~f0') -split $a; $u=$t[1] -split $b; [IO.File]::WriteAllText('%TEMP%\Install-UbuntuGUI.ps1',$u[0].Trim() + [char]10)"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\Install-UbuntuGUI.ps1" %*
echo.
pause
exit /b 0
:::PS1-BODY-START
[CmdletBinding()]
param([switch]$Resume, [switch]$Unattended)
$SCRIPT_VERSION = "0.1.0"
try { Start-Transcript -Path (Join-Path $env:TEMP 'Ubuntu-GUI-install.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
# Auto-elevacao: varios pontos exigem admin (WSL, mstsc, CFA). Via .cmd, o lote
# ja relancou elevado (caixa preta) - este bloco so age no uso direto do ps1
# (ex.: retomada RunOnce), com UM clique no UAC - bypass silencioso nao existe.
# -Unattended nunca relanca (ninguem clicaria no UAC: rode o .cmd ja elevado).
if ((-not $Unattended) -and (-not $env:UBUNTUGUI_FROM_CMD)) {
  $isAdminHead = $false
  try { $isAdminHead = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $isAdminHead = $false }
  if (-not $isAdminHead) {
    try {
      Write-Host "  Elevando a admin (confirme no UAC uma vez)..." -ForegroundColor Yellow
      $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
      if ((-not [Environment]::Is64BitProcess) -and (Test-Path "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe")) { $psExe = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
      $psiArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
      if ($Resume) { $psiArgs += ' -Resume' }
      Start-Process -FilePath $psExe -ArgumentList $psiArgs -Verb RunAs -Wait -ErrorAction Stop
      exit 0
    } catch { Write-Host "  Sem elevacao: segue sem admin (algumas etapas avisam e pulam)..." -ForegroundColor Yellow }
  }
}

$SCRIPT_BUILD = "d7e081f36e29"
Write-Host "Ubuntu-GUI Installer v$SCRIPT_VERSION (build $SCRIPT_BUILD)" -ForegroundColor Cyan
$script:UbuntuGuiBannerShown = $true
# Fonte unica de tunables tecnicos: mude AQUI, nunca espalhado no fluxo.
# Install-WslUbuntuGui mapeia para locais curtas ($RDP_PORT, $MinBuild, ...);
# Private/* leem via $script:UbuntuGuiDefaults (vale no modulo e no .cmd).
$script:UbuntuGuiDefaults = @{
  Distro               = 'Ubuntu'
  GuiPackage           = 'ubuntu-desktop-minimal'
  FallbackResolution   = '1600x900'
  RdpPort              = 3390    # longe da 3389 (erro 0x708 no loopback); ainda permite sobrescrita via parametro
  RdpFallbackPort        = 3391    # primeira alternativa quando a padrao esta ocupada
  RdpScanExtra         = 8       # portas extras varridas apos o fallback (fallback..fallback+extra)
  AppName              = 'Ubuntu-GUI'
  IconUrl              = 'https://commons.wikimedia.org/wiki/Special:FilePath/Ubuntu-logo-no-wordmark-solid-o-2022.svg?width=512'
  MstscSetupUrl64      = 'https://go.microsoft.com/fwlink/?linkid=2247659'   # mstsc 64-bit (doc MS: desinstalavel desde 23H2)
  MstscSetupUrl32      = 'https://go.microsoft.com/fwlink/?linkid=2247660'   # mstsc 32-bit
  MstscSetupUrlArm64   = 'https://go.microsoft.com/fwlink/?linkid=2247577'   # mstsc ARM64
  MinBuildMirrored     = 22621   # Win11 22H2+: mirrored networking
  CredTimeoutSec       = 60      # timeout por tentativa de set-credentials
  CredRetries          = 2       # tentativas de gravacao no cofre
  KeyringReprobeSec    = 5       # espera antes da re-sonda (corrida de ativacao do D-Bus)
  AptRetries           = 3       # tentativas de apt install
  PasswordMaxAttempts  = 3       # digitacao/confirmacao da senha (canon Rust)
  AptRetrySec          = 20      # espera entre tentativas de apt
  NetWaitTries         = 6       # sondas de DNS no WSL pos-reboot
  NetWaitSec           = 10      # espera entre sondas de DNS
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

# Sobe um daemon NOVO ja com a senha de login (o fluxo do login grafico:
# 'daemon --daemonize --login' le a senha do stdin e cria+destravada a colecao
# login, sem prompt, sem sudo, sem pam.d - provado ao vivo: arquivo persiste,
# alias resolve, item grava). O pkill roda em chamada WSL SEPARADA do --login:
# o padrao '[g]...' nunca divide a linha com o literal (senao o pkill se mata
# - SIGTERM observado). Retorna @{ Started; State; Out }.
function Start-WslLoginKeyringDaemon([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  Invoke-Wsl $LinuxUser "pkill -f '[g]nome-keyring-daemon' 2>/dev/null; sleep 1; echo REINICIADO" | Out-Null
  $probeCmd = Get-WslKeyringProbeCommand -Uid $Uid
  $r = Invoke-Wsl $LinuxUser "printf '%s' '$PasswordQuote' | $envPrefix gnome-keyring-daemon --daemonize --login >/dev/null 2>&1; sleep 2; $probeCmd"
  $out = if ($r.Out) { $r.Out.Trim() } else { '' }
  if (Test-UnlockedPropertyOutput -Out $out) { return @{ Started = $true; State = 'Unlocked'; Out = $out } }
  if ($out -match 'b true') { return @{ Started = $true; State = 'Locked'; Out = $out } }
  return @{ Started = $false; State = 'Error'; Out = $out }
}

# Cria o login.keyring com a senha informada quando ausente (via daemon
# --login, que ja deixa destravado). Puro de View (sem Ok/Fail: retorna
# @{ Created; Fresh }). Idempotente: arquivo existente = Created sem tocar nada.
function New-WslLoginKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid, [string]$KeyringPath) {
  $r = Invoke-Wsl $LinuxUser "test -f $KeyringPath && echo OK || echo MISSING"
  if ($r.Out -match "OK") { return @{ Created = $true; Fresh = $false } }
  Start-WslLoginKeyringDaemon -LinuxUser $LinuxUser -PasswordQuote $PasswordQuote -Uid $Uid | Out-Null
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
function Reset-WslLoginKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid, [string]$KeyringPath) {
  $ts = (Invoke-Wsl $LinuxUser "date +%Y%m%d-%H%M%S").Out.Trim()
  $backup = "$KeyringPath.bak-$ts"
  Invoke-Wsl $LinuxUser "mv $KeyringPath $backup 2>/dev/null; echo MOVED" | Out-Null
  $kc = New-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PasswordQuote -Uid $Uid -KeyringPath $KeyringPath
  if (-not $kc.Created) {
    Invoke-Wsl $LinuxUser "mv $backup $KeyringPath 2>/dev/null; echo RESTORED" | Out-Null
    return @{ Recreated = $false; Backup = $backup }
  }
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

# Resposta ao prompt de reboot ('[S/n]', padrao sim): vazio ou comeca com 's'.
# Pura (espelha o canon: mesma regra do instalador Rust).
function Test-RebootAnswer {
  [CmdletBinding()]
  param([string]$Answer)
  if ([string]::IsNullOrWhiteSpace($Answer)) { return $true }
  return $Answer.Trim().ToLower().StartsWith("s")
}

# Fail-fast do -Unattended (puro): sem terminal, sem pergunta - usuario e senha
# tem que vir de parametro (-LinuxUser e -LinuxPassword); rede cai no padrao.
function Test-UnattendedInput {
  [CmdletBinding()]
  param([string]$LinuxUser, [bool]$HasPassword)
  if ([string]::IsNullOrWhiteSpace($LinuxUser) -or (-not $HasPassword)) {
    return @{ Ok = $false; Reason = 'missing-credentials' }
  }
  return @{ Ok = $true; Reason = '' }
}

# Confirmacao de senha: iguais (case-sensitive) E nao-vazias (vazia confirma
# com vazia seria "match" - por isso o IsNullOrEmpty explicito). Pura.
function Test-PasswordConfirmation {
  [CmdletBinding()]
  param([string]$First, [string]$Second)
  if ([string]::IsNullOrEmpty($First)) { return $false }
  return ($First -ceq $Second)
}
# Valida o .ico inteiro (header + tabela de entradas + dados): header sozinho
# (download truncado) passava e deixava o .lnk sem imagem - o passo 6 refaz
# nesses casos e o atalho so aponta para o .ico quando ele passa aqui.
function Test-ValidIco([string]$Path) {
  try {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 6 -or $b[0] -ne 0 -or $b[1] -ne 0) { return $false }
    if ([BitConverter]::ToUInt16($b, 2) -ne 1) { return $false }
    $count = [BitConverter]::ToUInt16($b, 4)
    if ($count -lt 1 -or $count -gt 255) { return $false }
    if ($b.Length -lt 6 + $count * 16) { return $false }
    for ($i = 0; $i -lt $count; $i++) {
      $o = 6 + $i * 16
      $size = [BitConverter]::ToUInt32($b, $o + 8)
      $off = [BitConverter]::ToUInt32($b, $o + 12)
      if ($size -lt 1) { return $false }
      if (($off + $size) -gt $b.Length) { return $false }
    }
    return $true
  } catch { return $false }
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
# Monta as linhas do .rdp com login automatico (SEM senha embutida: o rdpsign
# deforma a linha longa `password 51:b:` e invalida a assinatura; a senha vai
# no sidecar `-Cred.txt` para o Cofre do Windows).
function New-RdpFileContent(
  [string]$RdpHost,
  [int]$RdpPort,
  [string]$LinuxUser,
  [string]$Resolution
) {
  # dynamic resolution: o servidor redesenha na resolucao atual da janela ao
  # redimensionar — sem barras pretas horizontais ou verticais.
  $rdp = @('screen mode id:i:1', 'session bpp:i:32', 'dynamic resolution:i:1')  # 1 = janela (2 = tela cheia); maximizar continua possivel
  $rdp += 'usbdevicestoredirect:s:*'  # USB do host na sessao (o servidor/GNOME pode recusar algumas classes)
  if ($Resolution -match '^(\d+)x(\d+)$') {
    $rdp += "desktopwidth:i:$($Matches[1])"
    $rdp += "desktopheight:i:$($Matches[2])"
  }
  $rdp += "full address:s:${RdpHost}:$RdpPort"
  $rdp += "username:s:$LinuxUser"
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
  [string]$RewriteBlock,
  [string]$FreeRdpBin = '',
  [string]$WRdpPath = '',
  [int]$RdpWidth,
  [int]$RdpHeight
) {
  $cmd = @'
@echo off
rem APP_NAME - liga o WSL, garante desktop+RDP e abre o mstsc
setlocal
set DISTRO=DISTRO_VAL
set SYS32=%SystemRoot%\System32
if exist "%SystemRoot%\Sysnative\cmd.exe" set SYS32=%SystemRoot%\Sysnative
set WSL=%SYS32%\wsl.exe
set MSTSC=%SYS32%\mstsc.exe
set RDPPATH=%LOCALAPPDATA%\Programs\APP_NAME\APP_NAME.rdp
set RUNRDP=%TEMP%\APP_NAME-run.rdp
set CREDHELPER=%LOCALAPPDATA%\Programs\APP_NAME\APP_NAME-Cred.ps1
if not exist "%WSL%" (echo ERRO: wsl.exe nao encontrado em %WSL% & pause & exit /b 1)
rem Sem mstsc, abre pelo cliente reserva no WSL (vazio = sem reserva, erro abaixo)
if not exist "%MSTSC%" if "FREERDP_VAL"=="" (echo ERRO: mstsc.exe nao encontrado em %MSTSC% & pause & exit /b 1)
set WSL_IP=127.0.0.1
IPDISCOVERY_VAL
if "%WSL_IP%"=="" (
  echo Nao foi possivel iniciar o Ubuntu no WSL.
  pause
  exit /b 1
)
%WSL% -d %DISTRO% -u LINUXUSER_VAL --exec env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start SHELLSVC_VAL RDPSVC_VAL.service >nul 2>&1
rem Copia por clique: o mstsc reescreve o .rdp que abre e invalidava a assinatura
copy /y "%RDPPATH%" "%RUNRDP%" >nul
RDPREWRITE_VAL
rem Sem arquivo no caminho diario: credencial no Cofre do Windows (sem aviso de
rem fornecedor). Se falhar, volta ao .rdp (comportamento anterior, nunca pior).
if not exist "%MSTSC%" goto :FREERDP
powershell -NoProfile -ExecutionPolicy Bypass -File "%CREDHELPER%" "%RUNRDP%" "%WSL_IP%" RDP_PORT_VAL >nul 2>&1
if errorlevel 1 (start "APP_NAME" "%MSTSC%" "%RUNRDP%") else (start "APP_NAME" %MSTSC% /v:%WSL_IP%:RDP_PORT_VAL /w:RDP_W_VAL /h:RDP_H_VAL)
goto :ENDLAUNCH
:FREERDP
%WSL% -d %DISTRO% -u LINUXUSER_VAL -- FREERDP_VAL "W_RDP_VAL"
:ENDLAUNCH
'@
  return ($cmd -replace "APP_NAME", $AppName -replace "DISTRO_VAL", $Distro `
    -replace "LINUXUSER_VAL", $LinuxUser -replace "RDPREWRITE_VAL", $RewriteBlock `
    -replace "RDP_PORT_VAL", $RdpPort -replace "THUMBPRINT_VAL", $Thumbprint `
    -replace "SHELLSVC_VAL", $script:UbuntuGuiDefaults.ShellService `
    -replace "RDPSVC_VAL", $script:UbuntuGuiDefaults.RdpService `
    -replace "IPDISCOVERY_VAL", $DiscoveryBlock `
    -replace "FREERDP_VAL", $FreeRdpBin -replace "W_RDP_VAL", $WRdpPath `
    -replace "RDP_W_VAL", $RdpWidth -replace "RDP_H_VAL", $RdpHeight)
}
# Gera o helper que grava a credencial RDP no Cofre do Windows (Credential Manager)
# para o mstsc abrir sem o aviso de fornecedor (sem precisar do .rdp assinado).
# Estatico (sem placeholder): recebe RdpPath, Host e Port por argumento.
# Fonte da credencial: sidecar `-Cred.txt` (usuario + blob DPAPI, gravado na
# instalacao) — o `.rdp` assinado NAO serve: o rdpsign deforma a linha longa
# `password 51:b:` (uppercase + zeros + hex impar) e a extracao quebra.
# Fallback: le usuario/blob do proprio .rdp (sanitizado; senha nunca em texto).
# Falha nunca e fatal: o launcher volta ao .rdp quando sai codigo != 0.
function New-CredHelperContent {
  return @'
param([string]$RdpPath, [string]$RdpHost, [int]$RdpPort)
try {
  $u = ''; $h = ''
  $sidecar = $PSCommandPath -replace '\.ps1$', '.txt'
  if (Test-Path $sidecar) {
    $sc = [IO.File]::ReadAllLines($sidecar)
    if ($sc.Count -ge 2) { $u = $sc[0].Trim(); $h = $sc[1] -replace '[^0-9a-fA-F]', '' }
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h)) {
    $lines = [IO.File]::ReadAllLines($RdpPath)
    $u = @($lines | Where-Object { $_ -like 'username:s:*' })[0] -replace '^username:s:', ''
    $h = @($lines | Where-Object { $_ -like 'password 51:b:*' })[0] -replace '^password 51:b:', ''
    $u = "$u".Trim()
    $h = "$h" -replace '[^0-9a-fA-F]', ''
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h) -or ($h.Length % 2 -eq 1)) { exit 1 }
  $raw = New-Object byte[] ($h.Length / 2)
  for ($i = 0; $i -lt $h.Length; $i += 2) { $raw[$i / 2] = [Convert]::ToByte($h.Substring($i, 2), 16) }
  Add-Type -AssemblyName System.Security
  $pass = [Text.Encoding]::Unicode.GetString([Security.Cryptography.ProtectedData]::Unprotect($raw, $null, 'CurrentUser'))
  if ([string]::IsNullOrEmpty($pass)) { exit 1 }
  $cs = 'using System; using System.Runtime.InteropServices; public static class CredMan { [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct CREDENTIAL { public UInt32 Flags; public UInt32 Type; [MarshalAs(UnmanagedType.LPWStr)] public string TargetName; [MarshalAs(UnmanagedType.LPWStr)] public string Comment; public UInt64 LastWritten; public UInt32 CredentialBlobSize; public IntPtr CredentialBlob; public UInt32 Persist; public UInt32 AttributeCount; public IntPtr Attributes; [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias; [MarshalAs(UnmanagedType.LPWStr)] public string UserName; } [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CredWriteW")] public static extern bool Write(ref CREDENTIAL cred, UInt32 flags); public static bool Save(string target, string user, string secret) { byte[] b = System.Text.Encoding.Unicode.GetBytes(secret); IntPtr p = Marshal.AllocCoTaskMem(b.Length); Marshal.Copy(b, 0, p, b.Length); CREDENTIAL c = new CREDENTIAL(); c.Flags = 0; c.Type = 1; c.TargetName = target; c.CredentialBlobSize = (UInt32)b.Length; c.CredentialBlob = p; c.Persist = 3; c.UserName = user; bool ok = Write(ref c, 0); Marshal.FreeCoTaskMem(p); return ok; } }'
  Add-Type -TypeDefinition $cs -Language CSharp
  $ok = $true
  foreach ($t in @("TERMSRV/$RdpHost", "TERMSRV/${RdpHost}:$RdpPort")) { if (-not [CredMan]::Save($t, $u, $pass)) { $ok = $false } }
  if (-not $ok) { exit 1 }
} catch { exit 1 }
exit 0
'@
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
  $all = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Subject })
  # So reaproveita com chave privada (cert sem chave nao assina: rdpsign 0x8009200B):
  # limpa as sobras do caminho antigo.
  $all | Where-Object { -not $_.HasPrivateKey } | ForEach-Object { try { $_ | Remove-Item -ErrorAction Stop } catch {} }
  $cert = @($all | Where-Object { $_.HasPrivateKey }) | Select-Object -First 1
  if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
      -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears($script:UbuntuGuiDefaults.CertYears)
  }
  # Store real no singular (o plural abre um custom que o mstsc ignora).
  # Vale tambem no reuso: sem essa gravacao o mstsc acusava fornecedor
  # desconhecido mesmo com o .rdp assinado.
  $store = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "CurrentUser")
  $store.Open("ReadWrite")
  try {
    $known = @($store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }).Count -gt 0
    if (-not $known) { $store.Add($cert); Ok "Publicador confiavel criado" }
    else { Ok "Publicador ja confiavel" }
  } finally { $store.Close() }
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
  Install-WslUbuntuGui -Unattended -LinuxUser daniel -LinuxPassword $sec -NetChoice 1  # sem paradas (reboot sozinho)

.O QUE FAZ (tudo validado numa instalacao real Ubuntu 26.04 + GNOME 50)
  1. Habilita o WSL (wsl --install) e instala a distro (reinicia se preciso)
  2. Cria o usuario Linux, ativa systemd, instala o pacote GUI
  3. Desabilita o GDM, configura o ambiente WSLg no .bashrc
  4. Le a resolucao do monitor Windows e cria o monitor virtual igual
  5. Sobe o GNOME headless + RDP com TLS e credencial no cofre
  6. Baixa o icone oficial do Ubuntu, restaura o mstsc se ausente (ou garante o FreeRDP reserva no WSL), cria o .cmd e os atalhos
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
  [switch]$NoTui,
  [switch]$Unattended
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
$PasswordMaxAttempts = $D.PasswordMaxAttempts
$AptRetrySec     = $D.AptRetrySec
$NetWaitTries    = $D.NetWaitTries
$NetWaitSec      = $D.NetWaitSec
$RdpSettleSec    = $D.RdpSettleSec
$WslWaitSec      = $D.WslShutdownWaitSec
$ShellWaitSec    = $D.ShellRestartWaitSec
$FreshWaitSec    = $D.FreshInstallWaitSec
$RebootDelaySec  = $D.RebootDelaySec
$TlsDays         = $D.TlsCertDays
$PublisherSubject = $D.PublisherSubject
$ShellService    = $D.ShellService
# Varredura [pedida, fallback, fallback+1, ...]: o teste anterior estava
# invertido (-not caia no fallback com a porta LIVRE, queimando uma por
# rerun) e o probe de loopback nao distingue "nosso RDP" de invasor
# (mirrored expoe o convidado no 127.0.0.1 do host). O reuso do proprio RDP
# vem no passo 5 (precisa do WSL). Nunca 3389 como padrao (0x708).
$RdpWanted = $RDP_PORT
$RdpCandidates = @($RdpWanted) + ($D.RdpFallbackPort..($D.RdpFallbackPort + $D.RdpScanExtra) | Where-Object { $_ -ne $RdpWanted })
$RDP_PORT = $RdpCandidates[-1]
foreach ($p in $RdpCandidates) {
  try { $busy = Test-NetConnection -ComputerName '127.0.0.1' -Port $p -InformationLevel Quiet }
  catch { $busy = $false }
  if (-not $busy) { $RDP_PORT = $p; break }
}
if ($RDP_PORT -ne $RdpWanted) {
  $nativeNote = if ($RdpWanted -eq 3389) { " (Windows RDP nativo?)" } else { "" }
  Warn "Porta $RdpWanted ocupada$nativeNote; usando $RDP_PORT como alternativa (ou passe -RdpPort para forcar outra)"
}
$ShellBinary     = $D.ShellBinary
$ShellRestartSec = $D.ShellRestartSec
$RdpService      = $D.RdpService
$GdmService      = $D.GdmService
$GdmAlias        = $D.GdmAlias
$KeyringPath     = $D.KeyringPath
$TlsCertPath     = $D.TlsCertPath
$TlsKeyPath      = $D.TlsKeyPath
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
# Banner unico: no .cmd o entry-head ja imprimiu (com build id); aqui so no modulo.
if (-not $script:UbuntuGuiBannerShown) { Write-Host "Ubuntu-GUI Installer v$SCRIPT_VERSION" -ForegroundColor Cyan }
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
  # Fail-fast do -Unattended: sem terminal, sem pergunta - tudo tem que vir de
  # parametro (rede cai no padrao abaixo); nome passa pela mesma validacao do
  # interativo (espelha o canon do instalador Rust).
  if ($Unattended) {
    $upFront = if ($LinuxPassword) { ConvertFrom-SecureStringPlain $LinuxPassword } else { '' }
    $credCheck = Test-UnattendedInput -LinuxUser $LinuxUser -HasPassword (-not [string]::IsNullOrEmpty($upFront))
    if (-not $credCheck.Ok) {
      Fail "-Unattended exige -LinuxUser e -LinuxPassword (opcional: -NetChoice 1|2)"; throw "Credenciais unattended ausentes"
    }
  }
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
    # Retry: errar a confirmacao nao mata o run (fail-fast so apos N).
    $LinuxPass = ''
    for ($pa = 1; $pa -le $PasswordMaxAttempts; $pa++) {
      $sec1 = Read-TuiSecurePassword -Prompt "Senha do usuario $LinuxUser" -NoTui:$NoTui
      $sec2 = Read-TuiSecurePassword -Prompt "Confirme a senha" -NoTui:$NoTui
      $cand = ConvertFrom-SecureStringPlain $sec1
      if (Test-PasswordConfirmation -First $cand -Second (ConvertFrom-SecureStringPlain $sec2)) { $LinuxPass = $cand; break }
      if ($pa -lt $PasswordMaxAttempts) { Warn "Senhas diferentes ou vazias - tente de novo ($pa/$PasswordMaxAttempts)" }
    }
    if ([string]::IsNullOrEmpty($LinuxPass)) {
      Fail "Senhas diferentes ou vazias apos $PasswordMaxAttempts tentativas - rode de novo"; throw "Senhas diferentes ou vazias"
    }
  }
  # $PWQ = senha pronta para embutir em 'bash -c "..."' (escapa bash + PowerShell)
  $PWQ = Get-PasswordQuote $LinuxPass
  Ok "Usuario Linux: $LinuxUser"

  # Modo de rede: [1] localhost fixo 127.0.0.1 via mirrored (recomendado, padrao: endpoint
  # estavel, sem redescoberta, assinatura do .rdp sempre valida) ou [2] IP dinamico
  # descoberto automaticamente a cada clique (p/ Windows sem mirrored).
  # Deteccao automatica: mirrored ativo mas sem internet cai sozinho p/ dinamico.
  # View (TUI com fallback Read-Host); regra pura em Resolve-NetworkChoice.
  # -Unattended pula o prompt: vazio cai no padrao mirrored via Resolve-NetworkChoice.
  if ([string]::IsNullOrWhiteSpace($NetChoice) -and (-not $Unattended)) {
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
  wsl --install -d $DISTRO --no-launch
  Write-Host "  Sem prompt duplo: o Ubuntu instala sem abrir (o usuario '$LinuxUser' e criado sozinho na etapa 2)" -ForegroundColor Yellow
  Start-Sleep -Seconds $FreshWaitSec
  wsl -d $DISTRO -- true 2>$null
  if ($LASTEXITCODE -eq 0) { Ok "WSL pronto sem reboot - seguindo sozinho" }
  else {
    Save-ResumeState $PSCommandPath $ProgDir $ResumeFile $ResumePs1 $RunOncePath $RunOnceName $LinuxUser $LinuxPass $NetChoice
    if ($Unattended) {
      Write-Host "  Modo nao assistido: reiniciando sozinho para continuar..." -ForegroundColor Yellow
      $rebootNow = $true
    } else {
      $rb = Read-Host "Reiniciar o Windows agora para continuar sozinho? [S/n]"
      $rebootNow = Test-RebootAnswer -Answer $rb
    }
    if ($rebootNow) {
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
    Ok "Mirrored networking (RDP fixo em 127.0.0.1 apos reiniciar)"
  } else {
    # Linha ja existia = mirrored ativo: valida antes de confiar. Sem rota
    # externa no WSL (preview/VPN/firewall), volta ao NAT sozinho com dinamico.
    $netUp = Invoke-Wsl $LinuxUser "ping -c 1 -W 4 1.1.1.1 2>&1 | grep -q '1 received\|1 packets received' && echo UP || echo DOWN"
    if ("$($netUp.Out)" -match 'DOWN') {
      Warn 'Mirrored ativo mas sem internet no WSL - voltando ao NAT com IP dinamico'
      $txt = ($txt -split "`r?`n" | Where-Object { $_ -notmatch '^\s*networkingMode\s*=' }) -join "`r`n"
      [IO.File]::WriteAllText($wslCfg, $txt.Trim() + "`r`n")
      $UseMirrored = $false
      wsl --shutdown
      Ok 'NAT de volta (interrompeu o mirrored quebrado)'
    } else { Ok "Mirrored networking (RDP fixo em 127.0.0.1)" }
  }
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
  Write-Host "  apt update + instalacao (~2 GB, demora; barra ao vivo abaixo)..." -ForegroundColor Yellow
  # Pos-reboot o WSL pode subir sem rede/DNS por alguns segundos: esperar aqui
  # (antes a 1a tentativa ja queimava com 'Temporary failure resolving...').
  $netOk = $false
  for ($w = 1; $w -le $NetWaitTries -and -not $netOk; $w++) {
    wsl -d $DISTRO -- getent hosts archive.ubuntu.com >$null 2>&1
    if ($LASTEXITCODE -eq 0) { $netOk = $true }
    else {
      Write-Host "  Aguardando rede do WSL ($w/$NetWaitTries)..." -ForegroundColor Yellow
      Start-Sleep -Seconds $NetWaitSec
    }
  }
  if (-not $netOk) { Warn "WSL sem DNS para archive.ubuntu.com - tentando o APT mesmo assim" }
  $ok = $false
  for ($i = 1; $i -le $AptRetries -and -not $ok; $i++) {
    if ($i -gt 1) {
      Write-Host "  Aguardando ${AptRetrySec}s antes da tentativa $i..." -ForegroundColor Yellow
      Start-Sleep -Seconds $AptRetrySec
    }
    # dpkg interrompido (reboot/janela fechada no meio do apt) mata QUALQUER
    # tentativa: recupera TODA vez (em sistema limpo e no-op de segundos).
    # Stdio HERDADO (sem tail, sem captura): a barra do apt desenha AO VIVO e
    # o transcript vira o log de verdade - antes parecia travado e matavam o
    # script no meio, que era o que quebrava o dpkg.
    wsl -d $DISTRO -u $LinuxUser --exec bash -c "printf '%s\n' '$PWQ' | sudo -S $apt dpkg --configure -a 2>&1"
    wsl -d $DISTRO -u $LinuxUser --exec bash -c "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -f -y 2>&1"
    wsl -d $DISTRO -u $LinuxUser --exec bash -c "printf '%s\n' '$PWQ' | sudo -S $apt apt-get update 2>&1"
    wsl -d $DISTRO -u $LinuxUser --exec bash -c "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -y $GUI_PACKAGE gnome-remote-desktop openssl python3-pil curl 2>&1"
    $ok = ((Invoke-Wsl $LinuxUser "dpkg -l $GUI_PACKAGE 2>/dev/null | grep -q '^ii'").Code -eq 0)
    if (-not $ok) { Warn "Tentativa $i falhou - veja o log, tentando de novo..." }
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
# Daemon no ar ANTES de todo o resto (o bus precisa de um dono; sem ele a
# sonda falha e a criacao via --login nao tem onde servir a colecao).
$Uid = (Invoke-Wsl $LinuxUser "id -u").Out.Trim()
$busRepair = Repair-WslKeyringBus -LinuxUser $LinuxUser -Uid $Uid -Distro $DISTRO
if ($busRepair.Repaired) { Warn "Bus do cofre reparado ($($busRepair.Detail))" }
if (Start-WslKeyringDaemon -LinuxUser $LinuxUser -Uid $Uid) { Ok "Daemon do cofre no ar" } else { Warn "Daemon do cofre nao respondeu - tentando criar via --login mesmo assim" }
# Cofre login (cria com a senha do usuario quando ausente, via daemon --login:
# sem sudo, sem pam.d, sem prompt - e ja sai destravado).
$kc = New-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid -KeyringPath $KeyringPath
if ($kc.Fresh) { Ok "Cofre login criado com a senha informada" }
elseif ($kc.Created) { Ok "Cofre login pronto" }
else { Fail "Cofre nao criado (confira ~/.local/share/keyrings/login.keyring e backups *.bak* - sem o arquivo nenhum unlock funciona)"; throw "Cofre nao criado" }

# Rerun apos reboot: o cofre volta bloqueado e o set-credentials travaria no prompt.
# Gestor de cofre (Invoke-VaultCredential.ps1): unlock falhou = fail fast com
# instrucao, nunca 2x60s de retry queimado a toa (sintoma: tentativas mudas).
# ($Uid ja calculado antes do prestart, acima.)
Write-Host "  Desbloqueando o cofre..." -ForegroundColor Yellow
# Unlock + sonda na MESMA chamada (daemon pode ser efemero: ativado por D-Bus,
# some em segundos; duas chamadas podem atingir instancias diferentes).
# Se ja destravado (ex.: criado agora via --login), pula o unlock: menos
# partes moveis.
$pamUnlocked = Test-WslKeyringUnlocked -LinuxUser $LinuxUser -Uid $Uid
if ($pamUnlocked) { Ok "Cofre ja destravado (pulando unlock)" }
$uk = if ($pamUnlocked) { @{ UnlockCode = 0; State = 'Unlocked'; Probe = 'via PAM'; UnlockText = '(via PAM)' } } else { UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid }
if ($uk.UnlockCode -ne 0) {
  Fail "Cofre nao desbloqueou com a senha informada ($($uk.UnlockText)) - cofre de outro run? No Ubuntu, COM BACKUP: mv ~/.local/share/keyrings/login.keyring ~/login.keyring.bak-UMA-SENHA && rode de novo com UMA senha definitiva (nunca rm: sem o arquivo nada funciona)"
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
      $rk = Reset-WslLoginKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid -KeyringPath $KeyringPath
      if (-not $rk.Recreated) {
        Fail "Recriacao falhou de forma inesperada e o original foi restaurado de $($rk.Backup) ($lockDetail) - destrave uma vez via Senhas e chaves (seahorse), mantenha ABERTO e rode de novo"
        throw "Cofre bloqueado"
      }
      Ok "Cofre recriado com a senha informada (original em $($rk.Backup))"
      $ukS = Get-WslKeyringProbeState -LinuxUser $LinuxUser -Uid $Uid
      if ($ukS.State -eq 'Unlocked') { Ok "Cofre destravado apos recriar (via PAM)" }
      else {
        $uk2 = UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote $PWQ -Uid $Uid
        if ($uk2.State -eq 'Unlocked') { Ok "Cofre destravou apos recriar" }
        else {
          Fail "Cofre recriado mas segue trancado (sonda: $($ukS.Out) - unlock disse: $($uk2.UnlockText)) - tente 'wsl --shutdown' e rode de novo"
          throw "Cofre bloqueado"
        }
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
# O ocupante pode ser o nosso proprio RDP (mirrored expoe o convidado no
# loopback do host): confirma no convidado e reaproveita a pedida em vez de
# queimar uma porta nova a cada rerun.
if (($RDP_PORT -ne $RdpWanted) -and (Test-WslRdpListening -LinuxUser $LinuxUser -Service $RdpService -Port $RdpWanted)) {
  $RDP_PORT = $RdpWanted
  Ok "Porta $RDP_PORT reaproveitada (nosso RDP ja escuta nela)"
}
# Porta fora da 3389 (erro 0x708 no loopback): idempotente, migra quem instalou na 3389.
Write-Host "  Aplicando TLS/porta $RDP_PORT e reiniciando o servico..." -ForegroundColor Yellow
Invoke-Wsl $LinuxUser "grdctl rdp set-tls-cert $TlsCertPath 2>/dev/null; grdctl rdp set-tls-key $TlsKeyPath 2>/dev/null; grdctl rdp set-port $RDP_PORT 2>/dev/null; grdctl rdp disable-view-only 2>/dev/null; grdctl rdp enable 2>/dev/null; systemctl --user enable $RdpService 2>/dev/null; systemctl --user restart $RdpService 2>&1 | tail -n 1" | Out-Null
Start-Sleep -Seconds $RdpSettleSec
if (Test-WslRdpListening -LinuxUser $LinuxUser -Service $RdpService -Port $RDP_PORT) { Ok "RDP ouvindo na porta $RDP_PORT" }
else { Fail "RDP nao subiu"; throw "RDP nao subiu" }
# Confia no cert TLS autoassinado (gerado por nos p/ este endpoint): some o
# aviso de rede/computador nao confiavel. So CurrentUser (sem admin).
try {
  $tlsPem = (Invoke-Wsl $LinuxUser "cat $TlsCertPath 2>/dev/null").Out
  $tlsB64 = ($tlsPem -replace '-----(BEGIN|END) CERTIFICATE-----', '') -replace '\s', ''
  $tlsBytes = [Convert]::FromBase64String($tlsB64)
  $tlsCert = New-Object Security.Cryptography.X509Certificates.X509Certificate2(,$tlsBytes)
  $tlsStore = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
  $tlsStore.Open('ReadWrite')
  try {
    $tlsKnown = @($tlsStore.Certificates | Where-Object { $_.Thumbprint -eq $tlsCert.Thumbprint }).Count -gt 0
    if (-not $tlsKnown) { $tlsStore.Add($tlsCert); Ok "Cert TLS confiavel (sem aviso de rede nao confiavel)" }
    else { Ok "Cert TLS ja confiavel" }
  } finally { $tlsStore.Close() }
} catch { Warn "Cert TLS nao importado (aviso de rede pode continuar): $($_.Exception.Message)" }

# ============================== 6. ICONE + ATALHOS ==============================
Step "6/7 Icone e atalhos ($APP_NAME)"
# Cliente RDP desinstalavel desde 23H2 (doc MS): se sumiu, reinstala pelo
# instalador oficial (silencioso). Nunca fatal: sem mstsc o resto instala
# igual, so o atalho nao abre (espelha a checagem do launcher).
$mstscSys = "$env:SystemRoot\System32"
if ((-not [Environment]::Is64BitProcess) -and (Test-Path "$env:SystemRoot\Sysnative\mstsc.exe")) { $mstscSys = "$env:SystemRoot\Sysnative" }
$mstscExe = Join-Path $mstscSys "mstsc.exe"
if (-not (Test-Path $mstscExe)) {
  $procArch = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
  if ([string]::IsNullOrEmpty($procArch)) { $procArch = "AMD64" }
  $mstscUrl = if ($procArch -eq "ARM64") { $D.MstscSetupUrlArm64 } elseif ($procArch -eq "x86") { $D.MstscSetupUrl32 } else { $D.MstscSetupUrl64 }
  $isAdmin = $false
  try { $isAdmin = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $isAdmin = $false }
  if (-not $isAdmin) {
    Warn "mstsc.exe ausente - rode como admin p/ reinstalar sozinho (ou instale: $mstscUrl)"
  } else {
    $mstscSetup = Join-Path $env:TEMP "mstsc-setup.exe"
    Write-Host "  Baixando o cliente RDP oficial (mstsc)..." -ForegroundColor Yellow
    try {
      (New-Object Net.WebClient).DownloadFile($mstscUrl, $mstscSetup)
      # So executa se for Microsoft assinado (tamanho sozinho nao prova nada:
      # o fwlink pode entregar stub pequeno legitimo ou pagina de erro).
      $mstscSigOk = $false
      try {
        $mstscSig = Get-AuthenticodeSignature $mstscSetup -ErrorAction Stop
        $mstscSigOk = ($mstscSig.Status -eq 'Valid') -and ($mstscSig.SignerCertificate.Subject -match 'Microsoft Corporation')
      } catch { $mstscSigOk = $false }
      $mstscSize = (Get-Item $mstscSetup).Length
      if (-not $mstscSigOk -and $mstscSize -lt 1MB) { Warn "Download do mstsc suspeito ($mstscSize bytes, sem assinatura Microsoft) - instale manual: $mstscUrl" }
      else {
        if (-not $mstscSigOk) { Warn "Setup do mstsc sem assinatura verificavel ($mstscSize bytes) - tentando mesmo assim" }
        $mstscProc = Start-Process -FilePath $mstscSetup -Wait -PassThru
        if (-not (Test-Path $mstscExe)) { Start-Sleep -Seconds 15 }
        if (Test-Path $mstscExe) { Ok "Cliente RDP (mstsc) restaurado"; Remove-Item $mstscSetup -Force -ErrorAction SilentlyContinue }
        else { Warn "Instalador do mstsc saiu com codigo $($mstscProc.ExitCode) mas o exe segue ausente ($mstscSetup guardado)" }
      }
    } catch { Warn "mstsc nao restaurado ($($_.Exception.Message)) - instale manual: $mstscUrl" }
  }
}
# Sem mstsc (ex.: Home sem o cliente e stub oficial recusou): reserva via
# FreeRDP dentro do WSL - abre pela WSLg, nada a instalar no Windows.
# O .rdp e reaproveitado (host/usuario/resolucao); a senha e pedida na
# janela do FreeRDP, nunca em texto no .cmd. Nunca fatal.
$FreeRdpBin = ''
$WRdpPath = ''
if (-not (Test-Path $mstscExe)) {
  $fr = Invoke-Wsl $LinuxUser "command -v xfreerdp 2>/dev/null || command -v sdl-freerdp 2>/dev/null || echo MISSING"
  if ("$($fr.Out)" -match 'MISSING') {
    Write-Host '  Instalando cliente RDP reserva (FreeRDP)...' -ForegroundColor Yellow
    Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -y freerdp3-x11 2>&1" | Out-Null
    $fr = Invoke-Wsl $LinuxUser "command -v xfreerdp 2>/dev/null || command -v sdl-freerdp 2>/dev/null || echo MISSING"
  }
  if ("$($fr.Out)" -match 'MISSING') {
    Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -y freerdp2-x11 2>&1" | Out-Null
    $fr = Invoke-Wsl $LinuxUser "command -v xfreerdp 2>/dev/null || command -v sdl-freerdp 2>/dev/null || echo MISSING"
  }
  if ("$($fr.Out)".Trim() -match 'MISSING') { Warn 'Sem cliente RDP reserva (freerdp3/freerdp2 ausentes no apt) - siga sem mstsc por enquanto' }
  else {
    $FreeRdpBin = (("$($fr.Out)".Trim()) -split '\s+')[-1]
    $WRdpPath = '/mnt/' + $ProgDir.Substring(0, 1).ToLower() + ($ProgDir.Substring(2) -replace '\\', '/') + "/$APP_NAME.rdp"
    Ok "Cliente RDP reserva: $FreeRdpBin"
  }
}
foreach ($d in @($IconsDir, $ProgDir)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
# Icone oficial (Circle of Friends 2022) -> .ico multi-tamanho via PIL no WSL.
# Valida o header, nao so a existencia (corrompido = refaz, senao o .lnk fica sem imagem).
if (-not (Test-ValidIco -Path $IcoPath)) {
  if (Test-Path $IcoPath) { Remove-Item $IcoPath -Force -ErrorAction SilentlyContinue }
  # C:\... -> /mnt/c/... (sintaxe compativel com Windows PowerShell 5.1)
  $wIco = '/mnt/' + $IcoPath.Substring(0, 1).ToLower() + ($IcoPath.Substring(2) -replace '\\', '/')
  $iconSizesArg = ($IconSizes | ForEach-Object { "($_, $_)" }) -join ', '
  # Script python via base64: aspas duplas aninhadas NAO atravessam o argv do
  # wsl.exe (o -c com aspas chegava fatiado e o python via so 'from').
  # Sem aspas duplas no comando: so singles, que passam intactas.
  $pyTemplate = @'
from PIL import Image
import sys
im = Image.open('/tmp/cof.png').convert('RGBA')
S = max(im.size)
sq = Image.new('RGBA', (S, S), (0, 0, 0, 0))
sq.paste(im, ((S - im.width) // 2, (S - im.height) // 2), im)
sq.save(sys.argv[1], sizes=[SIZES_ARG])
'@
  $pyB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($pyTemplate -replace 'SIZES_ARG', $iconSizesArg)))
  $r = Invoke-Wsl $LinuxUser "curl -sSL --retry 2 --retry-delay 5 --retry-all-errors --show-error --max-time 60 -o /tmp/cof.png '$ICON_URL' && echo '$pyB64' | base64 -d > /tmp/mkico.py && python3 /tmp/mkico.py '$wIco'"
  if (Test-ValidIco -Path $IcoPath) { Ok "Icone Ubuntu baixado e convertido" }
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
# Fixo: nao reescreve o .rdp (assinatura continua valida). Dinamico: reescreve + reassina SO se o IP mudou (sem churn: o "nao perguntar de novo" do mstsc sobrevive entre cliques).
$rewriteBlock = if ($LocalhostLive) { 'rem IP/porta fixos via mirrored (127.0.0.1:RDP_PORT_VAL) - copia assinada por clique, nao alterar' }
  else { 'for /f "tokens=3,4 delims=:" %%a in (''findstr /B "full address:s:" ''%RUNRDP%'' '') do set RDP_CUR=%%a:%%b' + "`r`n" + 'if not "%RDP_CUR%"=="%WSL_IP%:RDP_PORT_VAL" powershell -NoProfile -Command "$c = Get-Content ''%RUNRDP%''; if ($c -match ''^full address:s:'') { $c -replace ''^full address:s:.*'',''full address:s:%WSL_IP%:RDP_PORT_VAL'' | Set-Content ''%RUNRDP%''; if (Test-Path ''%SYS32%\rdpsign.exe'') { & %SYS32%\rdpsign.exe /sha256 THUMBPRINT_VAL ''%RUNRDP%'' >nul 2>&1 } }"' }
$rdpW = 1600; $rdpH = 900
if ($RES -match '^(\d+)x(\d+)$') { $rdpW = [int]$Matches[1]; $rdpH = [int]$Matches[2] }
$cmd = New-LauncherContent -AppName $APP_NAME -Distro $DISTRO `
  -LinuxUser $LinuxUser -RdpPort $RDP_PORT -Thumbprint $pubCert.Thumbprint `
  -DiscoveryBlock $discBlock -RewriteBlock $rewriteBlock `
  -FreeRdpBin $FreeRdpBin -WRdpPath $WRdpPath -RdpWidth $rdpW -RdpHeight $rdpH
[IO.File]::WriteAllText($CmdPath, $cmd)
Ok "Script em $CmdPath"
# Helper que grava a credencial no Cofre do Windows (login sem aviso de fornecedor).
$CredHelperPath = Join-Path $ProgDir "$APP_NAME-Cred.ps1"
[IO.File]::WriteAllText($CredHelperPath, (New-CredHelperContent))
# Sidecar -Cred.txt: usuario + blob DPAPI hex. O helper le daqui; a senha nao
# vai no .rdp porque o rdpsign deforma a linha longa e invalida a assinatura.
$CredTxtPath = Join-Path $ProgDir "$APP_NAME-Cred.txt"
Add-Type -AssemblyName System.Security
$blob = [Security.Cryptography.ProtectedData]::Protect(
  [Text.Encoding]::Unicode.GetBytes($LinuxPass), $null, 'CurrentUser')
$hex = ($blob | ForEach-Object { $_.ToString('x2') }) -join ''
[IO.File]::WriteAllLines($CredTxtPath, @($LinuxUser, $hex))
if ((Test-Path $CredHelperPath) -and (Test-Path $CredTxtPath)) { Ok "Login sem aviso via Cofre do Windows" }
else { Warn "Helper de credencial nao criado (segue pelo .rdp)" }

# .rdp com login automatico (SEM senha embutida: vai no sidecar p/ o Cofre)
$RdpPath = Join-Path $ProgDir "$APP_NAME.rdp"
if (-not $LocalhostLive) { $RdpHost = Get-WslIpAddress -Distro $DISTRO }
$rdp = New-RdpFileContent -RdpHost $RdpHost -RdpPort $RDP_PORT -LinuxUser $LinuxUser -Resolution $RES
[IO.File]::WriteAllLines($RdpPath, $rdp)
if (Test-Path $RdpPath) { Ok "RDP com login automatico em $RdpPath" }
else { Fail "Arquivo .rdp nao criado"; throw "RDP nao criado" }

# Assina o .rdp p/ sumir o aviso "fornecedor desconhecido" (rerun reassina apos regerar).
# rdpsign ausente (SKU sem o binario, ou powershell 32-bit vendo SysWOW64) nao
# pode matar a instalacao: assinatura e cosmetica, o .rdp funciona sem ela.
# Resolve nos dois contextos (elevado ou nao, 32 ou 64-bit): o processo que
# executa pode ver um System32 diferente (redirecionamento SysWOW64), entao
# sonda as duas visoes sempre em vez de escolher por bitness.
$rdpSign = @("$env:SystemRoot\System32\rdpsign.exe", "$env:SystemRoot\Sysnative\rdpsign.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if ($rdpSign -and (Test-Path $rdpSign)) {
  & $rdpSign /sha256 $pubCert.Thumbprint "$RdpPath" | Out-Null
} else {
  Warn "rdpsign.exe ausente - pulando assinatura (o .rdp funciona, so mostra aviso de fornecedor)"
}
# O rdpsign reescreve o .rdp em UTF-16LE: casa nos dois encodings (so UTF-8
# dizia "falhou" com o arquivo assinado).
$rdpSigned = $false
try {
  $rdpBytes = [IO.File]::ReadAllBytes($RdpPath)
  $rdpSigned = ([Text.Encoding]::UTF8.GetString($rdpBytes) -match 'signature:s:') -or ([Text.Encoding]::Unicode.GetString($rdpBytes) -match 'signature:s:')
} catch { $rdpSigned = $false }
if ($rdpSigned) { Ok "RDP assinado (sem aviso de fornecedor) [$($pubCert.Thumbprint.Substring(0,8))]" }
else { Warn "Assinatura do .rdp falhou - o aviso de fornecedor pode continuar" }

# Acesso Controlado a Pastas (Defender) pode bloquear a gravacao no Desktop:
# detecta via escrita de prova e, com autorizacao, libera o powershell
# (exige admin; sem permissao, orienta e segue - atalho nunca e fatal).
$cfaMode = 0
try { $cfaMode = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess } catch { $cfaMode = 0 }
if ($cfaMode -eq 1) {
  $cfaProbe = Join-Path (Split-Path $DeskLnk) ".ubuntugui-write-test"
  $cfaWritable = $false
  try { [IO.File]::WriteAllText($cfaProbe, "x"); Remove-Item $cfaProbe -Force; $cfaWritable = $true } catch { $cfaWritable = $false }
  if (-not $cfaWritable) {
    $cfaAllow = $false
    if ($Unattended) { Warn "CFA bloqueando o Desktop (nao assistido: sem liberacao automatica)" }
    else {
      $cfaAns = Read-Host "Defender (pastas protegidas) bloqueando os atalhos. Liberar o PowerShell p/ gravar? [S/n]"
      $cfaAllow = Test-RebootAnswer -Answer $cfaAns  # [S/n] padrao sim
    }
    if ($cfaAllow) {
      try {
        Add-MpPreference -ControlledFolderAccessAllowedApplications (Join-Path $PSHOME "powershell.exe") -ErrorAction Stop
        Ok "PowerShell liberado nas pastas protegidas"
      } catch { Warn "Sem permissao p/ liberar o CFA (rode como admin uma vez): $($_.Exception.Message)" }
    }
  }
}
# .lnk no Desktop + Iniciar, com o icone valido (corrompido que existe tambem
# nascia o atalho sem imagem: fallback para o icone do mstsc).
$icoSpec = if (Test-ValidIco -Path $IcoPath) { "$IcoPath,0" } else { "C:\Windows\System32\mstsc.exe,0" }
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
else { Warn "Atalhos incompletos (rode de novo p/ recriar) - o Ubuntu-GUI.cmd em $ProgDir funciona" }
# Nada mais toca no .rdp depois da assinatura: se o marcador sumiu aqui,
# algo reescreveu o arquivo no meio do passo 6 (e o mstsc vai acusar
# fornecedor desconhecido mesmo com o "assinado" acima).
try {
  $rdpFinal = [IO.File]::ReadAllBytes($RdpPath)
  $stillSigned = ([Text.Encoding]::UTF8.GetString($rdpFinal) -match 'signature:s:') -or ([Text.Encoding]::Unicode.GetString($rdpFinal) -match 'signature:s:')
} catch { $stillSigned = $false }
if (-not $stillSigned) { Warn "Assinatura sumiu apos gravar atalhos - o aviso de fornecedor pode continuar" }

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
  Write-Host "  Login RDP : automatico (usuario e senha no Cofre do Windows)"
  Write-Host "  Resolucao do desktop: $RES"
  if ($wslRestartNeeded -and $UseMirrored) { Write-Host "  REINICIE o Windows (ou rode 'wsl --shutdown') p/ valer o mirrored" -ForegroundColor Yellow }
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
  Install-WslUbuntuGui -Resume:$Resume -Unattended:$Unattended
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
