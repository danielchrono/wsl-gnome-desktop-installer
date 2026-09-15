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
  else { 'powershell -NoProfile -Command "(Get-Content ''%RDPPATH%'') -replace ''^full address:s:.*'',''full address:s:%WSL_IP%:RDP_PORT_VAL'' | Set-Content ''%RDPPATH%''; & %SYS32%\rdpsign.exe /sha256 THUMBPRINT_VAL ''%RDPPATH%'' >nul 2>&1"' }
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
# rdpsign ausente (SKU sem o binario, ou powershell 32-bit vendo SysWOW64) nao
# pode matar a instalacao: assinatura e cosmetica, o .rdp funciona sem ela.
$rdpSign = "$env:SystemRoot\System32\rdpsign.exe"
if ((-not [Environment]::Is64BitProcess) -and (Test-Path "$env:SystemRoot\Sysnative\rdpsign.exe")) { $rdpSign = "$env:SystemRoot\Sysnative\rdpsign.exe" }
if (Test-Path $rdpSign) {
  & $rdpSign /sha256 $pubCert.Thumbprint "$RdpPath" | Out-Null
} else {
  Warn "rdpsign.exe ausente - pulando assinatura (o .rdp funciona, so mostra aviso de fornecedor)"
}
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

