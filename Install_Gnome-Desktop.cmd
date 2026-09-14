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
<#
.SYNOPSIS
  Install-UbuntuGUI - Instala o Ubuntu no WSL2 com desktop GNOME completo via RDP.
  Idempotente: pode rodar, reiniciar e rodar de novo - retoma de onde parou.
  Se precisar de reboot, agenda a retomada sozinha (RunOnce) - nao precisa rodar de novo.

.EXECUCAO
  Botao direito > Executar com o PowerShell, ou:
  powershell -ExecutionPolicy Bypass -File .\Install-UbuntuGUI.ps1

.O QUE FAZ (tudo validado numa instalacao real Ubuntu 26.04 + GNOME 50)
  1. Habilita o WSL (wsl --install) e instala a distro (reinicia se preciso)
  2. Cria o usuario Linux, ativa systemd, instala o pacote GUI
  3. Desabilita o GDM, configura o ambiente WSLg no .bashrc
  4. Le a resolucao do monitor Windows e cria o monitor virtual igual
  5. Sobe o GNOME headless + RDP com TLS e credencial no cofre
  6. Baixa o icone oficial do Ubuntu, cria o .cmd e os atalhos
#>
[CmdletBinding()]
param([switch]$Resume)

# ============================== CONSTANTES ==============================
$DISTRO          = "Ubuntu"                  # distro WSL (wsl -l -q)
$GUI_PACKAGE     = "ubuntu-desktop-minimal"  # pacote GNOME nativo (sem flashback)
$FALLBACK_RES    = "1600x900"                # resolucao se nao der pra ler a do Windows
$RDP_PORT        = 3390                  # 3390, nao 3389: mstsc no Win11/Server2025 bloqueia loopback 127.0.0.1:3389 com erro 0x708 + conflita com o RDP do Windows no mirrored
$APP_NAME        = "Ubuntu-GUI"
$SCRIPT_VERSION = "0.1.0"
$ICON_FILE       = "ubuntu.ico"
$ICON_URL        = "https://commons.wikimedia.org/wiki/Special:FilePath/Ubuntu-logo-no-wordmark-solid-o-2022.svg?width=512"
$UBUNTU_CODENAME = "resolute"               # 26.04 LTS (informativo)

$IconsDir  = Join-Path $env:USERPROFILE "Icons"
$ProgDir   = Join-Path $env:LOCALAPPDATA "Programs\$APP_NAME"
$CmdPath   = Join-Path $ProgDir "$APP_NAME.cmd"
$IcoPath   = Join-Path $IconsDir $ICON_FILE
$DeskLnk   = Join-Path ([Environment]::GetFolderPath("Desktop")) "$APP_NAME.lnk"
$StartLnk  = Join-Path ([Environment]::GetFolderPath("Programs")) "$APP_NAME.lnk"
$LogFile   = Join-Path $env:TEMP "$APP_NAME-install.log"
$ResumeFile = Join-Path $ProgDir "resume-state.json"
$ResumePs1  = Join-Path $ProgDir "Install-UbuntuGUI.resume.ps1"
$RunOncePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$RunOnceName = "UbuntuGUIResume"
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

# Retomada sozinha apos reboot: salva respostas (senha em DPAPI, so este usuario le),
# copia este script p/ a pasta do app e agenda reabertura via RunOnce.
function Save-ResumeState {
  if (-not (Test-Path $ProgDir)) { New-Item -ItemType Directory -Path $ProgDir -Force | Out-Null }
  Copy-Item -Path $PSCommandPath -Destination $ResumePs1 -Force
  $enc = [Convert]::ToBase64String(
    [Security.Cryptography.ProtectedData]::Protect(
      [Text.Encoding]::UTF8.GetBytes($LinuxPass), $null, 'CurrentUser'))
  @{ Phase = "AfterReboot"; LinuxUser = $LinuxUser; LinuxPassEnc = $enc; NetChoice = $NetChoice } |
    ConvertTo-Json -Compress | Set-Content $ResumeFile
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ResumePs1`" -Resume"
  New-ItemProperty -Path $RunOncePath -Name $RunOnceName -Value $cmd -PropertyType String -Force | Out-Null
  Ok "Retomada agendada (reabre sozinho apos o reboot)"
}
function Clear-ResumeState {
  Remove-ItemProperty -Path $RunOncePath -Name $RunOnceName -ErrorAction SilentlyContinue | Out-Null
  Remove-Item $ResumeFile, $ResumePs1 -Force -ErrorAction SilentlyContinue | Out-Null
}

# ============================== FEEDBACK ==============================
$script:Failures = @()
function Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "  [FALHA] $msg" -ForegroundColor Red; $script:Failures += $msg }

# Roda 'wsl -d $DISTRO ...' repassando o exit code real do Linux
function Invoke-Wsl([string]$AsUser, [string]$Command) {
  $out = wsl -d $DISTRO -u $AsUser --exec bash -c $Command 2>&1
  return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}
function Invoke-WslRoot([string]$Command) { return Invoke-Wsl "root" $Command }

try { Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null } catch {}

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
    $PWQ = ($LinuxPass -replace "'", "'\''") -replace '`', '``' -replace '\$', '`$' -replace '"', '`"'
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
  $SavedUserFile = Join-Path $env:LOCALAPPDATA "Programs\$APP_NAME\linux-user.txt"
  $defUser = if (Test-Path $SavedUserFile) { (Get-Content $SavedUserFile -Raw).Trim() } else { ($env:USERNAME.ToLower() -replace '[^a-z0-9]', '') }
  if ([string]::IsNullOrWhiteSpace($defUser)) { $defUser = "ubuntu" }
  $LinuxUser = Read-Host "Usuario Linux [$defUser]"
  if ([string]::IsNullOrWhiteSpace($LinuxUser)) { $LinuxUser = $defUser }
  if ($LinuxUser -notmatch '^[a-z_][a-z0-9_-]*$') {
    Fail "Usuario '$LinuxUser' invalido (use minusculas, numeros, _ ou -)"; exit 1
  }
  if ($LinuxUser -eq 'root') {
    Fail "O usuario 'root' e reservado - escolha outro nome"; exit 1
  }
  $sec1 = Read-Host "Senha do usuario $LinuxUser" -AsSecureString
  $sec2 = Read-Host "Confirme a senha" -AsSecureString
  $LinuxPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec1))
  $LinuxPass2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2))
  if ($LinuxPass -cne $LinuxPass2 -or [string]::IsNullOrEmpty($LinuxPass)) {
    Fail "Senhas diferentes ou vazias - rode de novo"; exit 1
  }
  # $PWQ = senha pronta para embutir em 'bash -c "..."' (escapa bash + PowerShell)
  $PWQ = ($LinuxPass -replace "'", "'\''") -replace '`', '``' -replace '\$', '`$' -replace '"', '`"'
  Ok "Usuario Linux: $LinuxUser"

  # Modo de rede: [1] localhost fixo 127.0.0.1 via mirrored (recomendado, padrao: endpoint
  # estavel, sem redescoberta, assinatura do .rdp sempre valida) ou [2] IP dinamico
  # descoberto automaticamente a cada clique (p/ Windows sem mirrored).
  $NetChoice = Read-Host "Modo de rede [1] localhost fixo 127.0.0.1 (recomendado) ou [2] IP dinamico a cada clique [1]"
  if ([string]::IsNullOrWhiteSpace($NetChoice)) { $NetChoice = "1" }
  $WantMirrored = ($NetChoice.Trim() -ne "2")
  if ($WantMirrored) { Ok "Modo: localhost fixo 127.0.0.1 (masked)" }
  else { Write-Host "  Modo: IP dinamico - o atalho identifica o IP automaticamente a cada clique" -ForegroundColor Yellow }

  if (Test-Path $ResumeFile) {
    Clear-ResumeState
    Warn "Retomada pendente cancelada (novo run manual)"
  }
}

# ============================== 1. WSL + DISTRO ==============================
Step "1/7 WSL, rede e distro $DISTRO"
$distros = (wsl -l -q 2>$null) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $DISTRO) {
  Write-Host "  Instalando WSL + $DISTRO..." -ForegroundColor Yellow
  wsl --install -d $DISTRO
  Write-Host "  Nao abra o app Ubuntu: o script cria o usuario '$LinuxUser' sozinho (sem digitar no instalador do Ubuntu)" -ForegroundColor Yellow
  Start-Sleep -Seconds 15
  wsl -d $DISTRO -- true 2>$null
  if ($LASTEXITCODE -eq 0) { Ok "WSL pronto sem reboot - seguindo sozinho" }
  else {
    Save-ResumeState
    $rb = Read-Host "Reiniciar o Windows agora para continuar sozinho? [S/n]"
    if ([string]::IsNullOrWhiteSpace($rb) -or $rb.Trim().ToLower().StartsWith("s")) {
      Write-Host "  Reiniciando em 30s (cancele com: shutdown /a)..." -ForegroundColor Yellow
      shutdown /r /t 30 /c "Ubuntu-GUI: reiniciando p/ continuar a instalacao sozinho"
    } else {
      Write-Host "  Sem pressa: ao ligar de novo, a instalacao reabre sozinha (sem clicar de novo)" -ForegroundColor Yellow
    }
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    exit 0
  }
}
Ok "Distro $DISTRO presente"
wsl -d $DISTRO -- true 2>$null
if ($LASTEXITCODE -ne 0) {
  Fail "Distro instalada mas nao inicia - abra o Ubuntu uma vez e rode de novo"
  exit 1
}

# Mirrored networking (Win11 22H2+, build 22621+): RDP vira 127.0.0.1 fixo.
# Sem suporte ou modo dinamico escolhido: IP dinamico descoberto a cada clique.
$UseMirrored = $WantMirrored -and ($os.Build -ge 22621)
if ($WantMirrored -and ($os.Build -lt 22621)) {
  Warn "Mirrored exige Win11 22H2+ (build 22621+); usando IP dinamico"
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
  $RdpHost = (wsl -d $DISTRO -- hostname -I 2>$null) -split '\s+' | Where-Object { $_ } | Select-Object -First 1
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
  else { Fail "Nao atualizei a senha: $($rp.Out)"; exit 1 }
}
if (-not (Test-Path $ProgDir)) { New-Item -ItemType Directory -Path $ProgDir -Force | Out-Null }
[IO.File]::WriteAllText((Join-Path $ProgDir "linux-user.txt"), $LinuxUser)
if ((Invoke-WslRoot "id -u $LinuxUser 2>/dev/null").Code -eq 0) { Ok "Usuario $LinuxUser pronto" }

# wsl.conf com systemd + usuario padrao (exige 'wsl --shutdown' para valer)
$r = Invoke-WslRoot "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && grep -q 'default=$LinuxUser' /etc/wsl.conf 2>/dev/null && echo OK || echo FIX"
if ($r.Out -match "FIX") {
  Invoke-WslRoot "printf '[boot]\nsystemd=true\n[user]\ndefault=$LinuxUser\n' > /etc/wsl.conf" | Out-Null
  Write-Host "  Reiniciando o WSL para ativar o systemd..." -ForegroundColor Yellow
  wsl --shutdown
  Start-Sleep -Seconds 8
}
$r = Invoke-Wsl $LinuxUser "systemctl is-system-running 2>&1 | head -n 1"
if ($r.Out -match "running|degraded") { Ok "systemd ativo ($($r.Out.Trim()))" }
else { Fail "systemd nao subiu - rode 'wsl --shutdown' e execute de novo"; exit 1 }

# ============================== 3. PACOTE GUI ==============================
Step "3/7 Pacote $GUI_PACKAGE (+ openssl, PIL)"
$apt = "env DEBIAN_FRONTEND=noninteractive"  # via 'env': sudo nao entende 'export'
$r = Invoke-Wsl $LinuxUser "dpkg -l $GUI_PACKAGE 2>/dev/null | grep -q '^ii' && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  Write-Host "  apt update + instalacao (~2 GB, demora)..." -ForegroundColor Yellow
  $ok = $false
  for ($i = 1; $i -le 3 -and -not $ok; $i++) {
    $r = Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get update 2>&1 | tail -n 1"
    $r = Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S $apt apt-get install -y $GUI_PACKAGE gnome-remote-desktop openssl python3-pil curl 2>&1 | tail -n 2"
    $ok = ((Invoke-Wsl $LinuxUser "dpkg -l $GUI_PACKAGE 2>/dev/null | grep -q '^ii'").Code -eq 0)
    if (-not $ok) { Warn "Tentativa $i falhou, tentando de novo..." }
  }
  if (-not $ok) { Fail "APT nao concluiu apos 3 tentativas - veja o log"; exit 1 }
}
Ok "$GUI_PACKAGE instalado"
$r = Invoke-Wsl $LinuxUser "gnome-shell --version 2>&1"
Ok $r.Out.Trim()

# GDM nunca no WSL (conflita com o Weston do WSLg)
Invoke-Wsl $LinuxUser "printf '%s\n' '$PWQ' | sudo -S systemctl stop gdm3 2>/dev/null; printf '%s\n' '$PWQ' | sudo -S systemctl disable gdm3 gdm 2>/dev/null | tail -n 1" | Out-Null
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
ExecStart=/usr/bin/gnome-shell --mode=ubuntu --wayland --headless --no-x11 --virtual-monitor $RES
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
"@
$unit | wsl -d $DISTRO -u $LinuxUser --exec bash -c "mkdir -p ~/.config/systemd/user && cat > ~/.config/systemd/user/gnome-shell-headless.service"
Invoke-Wsl $LinuxUser "systemctl --user daemon-reload; systemctl --user enable gnome-shell-headless.service 2>&1 | tail -n 1" | Out-Null
# Reinicia so se nao houver Shell rodando exatamente nesta resolucao (rerun seguro)
$r = Invoke-Wsl $LinuxUser "pgrep -af 'gnome-shell.*--virtual-monitor $RES' | grep -qv 'bin/sh' && echo CURRENT || echo STALE"
if ($r.Out -match "STALE") {
  Write-Host "  (Re)iniciando o Shell em $RES..." -ForegroundColor Yellow
  Invoke-Wsl $LinuxUser "systemctl --user restart gnome-shell-headless.service" | Out-Null
  Start-Sleep -Seconds 12
}
$r = Invoke-Wsl $LinuxUser "systemctl --user is-active gnome-shell-headless.service"
if ($r.Out -match "active") { Ok "GNOME Shell ativo em $RES" }
else { Fail "Shell nao subiu - journal: systemctl --user status gnome-shell-headless"; exit 1 }
Invoke-Wsl $LinuxUser "mkdir -p ~/Desktop" | Out-Null

# ============================== 5. RDP + COFRE ==============================
Step "5/7 RDP com TLS e credencial"
# Certificado autoassinado (idempotente)
$r = Invoke-Wsl $LinuxUser "test -f ~/.local/share/gnome-remote-desktop/rdp-cert.pem && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  Invoke-Wsl $LinuxUser "mkdir -p ~/.local/share/gnome-remote-desktop && openssl req -x509 -newkey rsa:2048 -keyout ~/.local/share/gnome-remote-desktop/rdp-key.pem -out ~/.local/share/gnome-remote-desktop/rdp-cert.pem -days 825 -nodes -subj '/CN=ubuntu-wsl'" | Out-Null
  Ok "Certificado TLS criado"
}
# Cofre login via PAM do sudo (cria com a senha do usuario; revertido em seguida).
# O tee recebe SENHA + CONTEUDO no mesmo stdin: o sudo consome a 1a linha, o resto anexa.
$r = Invoke-Wsl $LinuxUser "test -f ~/.local/share/keyrings/login.keyring && echo OK || echo MISSING"
if ($r.Out -match "MISSING") {
  $pamAdd = "printf '%s\nauth optional pam_gnome_keyring.so\nsession optional pam_gnome_keyring.so auto_start\n' '$PWQ' | sudo -S tee -a /etc/pam.d/sudo > /dev/null"
  Invoke-Wsl $LinuxUser "$pamAdd && printf '%s\n' '$PWQ' | sudo -S true && printf '%s\n' '$PWQ' | sudo -S sed -i '/pam_gnome_keyring.so/d' /etc/pam.d/sudo" | Out-Null
}
$r = Invoke-Wsl $LinuxUser "test -f ~/.local/share/keyrings/login.keyring && echo OK || echo MISSING"
if ($r.Out -match "OK") { Ok "Cofre login pronto" } else { Fail "Cofre nao criado"; exit 1 }
if ((Invoke-Wsl $LinuxUser "grep -c pam_gnome_keyring /etc/pam.d/sudo 2>/dev/null").Out.Trim() -ne "0") {
  Fail "/etc/pam.d/sudo nao voltou ao original - verifique"; exit 1
}
Ok "/etc/pam.d/sudo intacto"

# Rerun apos reboot: o cofre volta bloqueado e o set-credentials travaria no prompt.
# Desbloqueia com a senha informada (cofre de senha vazia ignora: ja abre sozinho).
$Uid = (Invoke-Wsl $LinuxUser "id -u").Out.Trim()
Write-Host "  Desbloqueando o cofre..." -ForegroundColor Yellow
Invoke-Wsl $LinuxUser "printf '%s' '$PWQ' | XDG_RUNTIME_DIR=/run/user/$Uid gnome-keyring-daemon --unlock 2>&1 | tail -n 1" | Out-Null

# Credencial + TLS + servico (com retry, sem prompt: cofre ja existe destravado).
# O set-credentials pode levar ate ~60s por tentativa: avisa + mostra tentativa p/ nao parecer travado.
Write-Host "  Gravando credencial RDP no cofre (pode levar ate ~60s por tentativa, nao feche)..." -ForegroundColor Yellow
$stored = $false
for ($i = 1; $i -le 2 -and -not $stored; $i++) {
  Write-Host "  Tentativa $i/2..." -NoNewline
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $gc = Invoke-Wsl $LinuxUser "timeout 60 grdctl rdp set-credentials '$LinuxUser' '$PWQ' 2>&1 | tail -n 5"
  # Verifica a credencial de verdade no daemon (o cofre existir nao basta: item vazio tambem conta no busctl)
  $stored = ((Invoke-Wsl $LinuxUser "grdctl status 2>/dev/null | grep -E 'Username:' | grep -qv '(empty)' && echo YES || echo NO").Out.Trim() -eq "YES")
  $sw.Stop()
  if ($stored) { Write-Host " ok ($([int]$sw.Elapsed.TotalSeconds)s)" -ForegroundColor Green }
  else { Write-Host " ainda nao ($([int]$sw.Elapsed.TotalSeconds)s): $($gc.Out.Trim())" -ForegroundColor Yellow }
}
if (-not $stored) { Fail "Credencial RDP nao gravou no cofre"; exit 1 }
Ok "Credencial RDP gravada"
# Porta fora da 3389 (erro 0x708 no loopback): idempotente, migra quem instalou na 3389.
Write-Host "  Aplicando TLS/porta $RDP_PORT e reiniciando o servico..." -ForegroundColor Yellow
Invoke-Wsl $LinuxUser "grdctl rdp set-tls-cert ~/.local/share/gnome-remote-desktop/rdp-cert.pem 2>/dev/null; grdctl rdp set-tls-key ~/.local/share/gnome-remote-desktop/rdp-key.pem 2>/dev/null; grdctl rdp set-port $RDP_PORT 2>/dev/null; grdctl rdp disable-view-only 2>/dev/null; grdctl rdp enable 2>/dev/null; systemctl --user enable gnome-remote-desktop 2>/dev/null; systemctl --user restart gnome-remote-desktop 2>&1 | tail -n 1" | Out-Null
Start-Sleep -Seconds 4
$r = Invoke-Wsl $LinuxUser "systemctl --user is-active gnome-remote-desktop && ss -tlnp 2>/dev/null | grep -q ':$RDP_PORT' && echo OK || echo DOWN"
if ($r.Out -match "OK") { Ok "RDP ouvindo na porta $RDP_PORT" }
else { Fail "RDP nao subiu"; exit 1 }

# ============================== 6. ICONE + ATALHOS ==============================
Step "6/7 Icone e atalhos ($APP_NAME)"
foreach ($d in @($IconsDir, $ProgDir)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
# Icone oficial (Circle of Friends 2022) -> .ico multi-tamanho via PIL no WSL
if (-not (Test-Path $IcoPath)) {
  # C:\... -> /mnt/c/... (sintaxe compativel com Windows PowerShell 5.1)
  $wIco = '/mnt/' + $IcoPath.Substring(0, 1).ToLower() + ($IcoPath.Substring(2) -replace '\\', '/')
  $r = Invoke-Wsl $LinuxUser "curl -sL --max-time 60 -o /tmp/cof.png '$ICON_URL' && python3 -c `"from PIL import Image; im=Image.open('/tmp/cof.png').convert('RGBA'); S=max(im.size); sq=Image.new('RGBA',(S,S),(0,0,0,0)); sq.paste(im,((S-im.width)//2,(S-im.height)//2),im); sq.save('$wIco',sizes=[(16,16),(32,32),(48,48),(128,128),(256,256)])`"" 2>&1
  if (Test-Path $IcoPath) { Ok "Icone Ubuntu baixado e convertido" }
  else { Warn "Icone oficial falhou, usando o do mstsc ($($r.Out))" }
} else { Ok "Icone ja existia" }

# Certificado de publicador p/ assinar o .rdp (some o aviso "fornecedor desconhecido").
$PublisherCN = "CN=Ubuntu-GUI RDP"
$pubCert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
  Where-Object { $_.Subject -eq $PublisherCN } | Select-Object -First 1
if (-not $pubCert) {
  $pubCert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $PublisherCN `
    -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(10)
  $pubStore = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPublishers", "CurrentUser")
  $pubStore.Open("ReadWrite"); $pubStore.Add($pubCert); $pubStore.Close()
  Ok "Publicador confiavel criado"
}

# Script launcher na pasta de programas (modo fixo: nao toca no .rdp p/ manter a assinatura)
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
%WSL% -d %DISTRO% -u LINUXUSER_VAL --exec env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start gnome-shell-headless.service gnome-remote-desktop.service >nul 2>&1
RDPREWRITE_VAL
start "APP_NAME" "%MSTSC%" "%RDPPATH%"
'@
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
$cmd = $cmd -replace "APP_NAME", $APP_NAME -replace "DISTRO_VAL", $DISTRO `
  -replace "LINUXUSER_VAL", $LinuxUser -replace "RDPREWRITE_VAL", $rewriteBlock `
  -replace "RDP_PORT_VAL", $RDP_PORT -replace "THUMBPRINT_VAL", $pubCert.Thumbprint `
  -replace "IPDISCOVERY_VAL", $discBlock
[IO.File]::WriteAllText($CmdPath, $cmd)
Ok "Script em $CmdPath"

# .rdp com login automatico: senha em blob DPAPI (so este usuario Windows le)
$RdpPath = Join-Path $ProgDir "$APP_NAME.rdp"
Add-Type -AssemblyName System.Security
$blob = [Security.Cryptography.ProtectedData]::Protect(
  [Text.Encoding]::Unicode.GetBytes($LinuxPass), $null, 'CurrentUser')
$hex = ($blob | ForEach-Object { $_.ToString('x2') }) -join ''
$rdp = @('screen mode id:i:2', 'session bpp:i:32')
if ($RES -match '^(\d+)x(\d+)$') {
  $rdp += "desktopwidth:i:$($Matches[1])"
  $rdp += "desktopheight:i:$($Matches[2])"
}
if (-not $LocalhostLive) { $RdpHost = (wsl -d $DISTRO -- hostname -I 2>$null) -split '\s+' | Where-Object { $_ } | Select-Object -First 1 }
$rdp += "full address:s:${RdpHost}:$RDP_PORT"
$rdp += "username:s:$LinuxUser"
$rdp += "password 51:b:$hex"
$rdp += 'prompt for credentials:i:0'
$rdp += 'enablecredsspsupport:i:1'
$rdp += 'authentication level:i:0'  # 0 = nao avisar: cert e autoassinado (loopback/WSL, sem MITM pratico)
$rdp += 'promptcredentialonce:i:1'
$rdp += 'negotiate security layer:i:1'
[IO.File]::WriteAllLines($RdpPath, $rdp)
if (Test-Path $RdpPath) { Ok "RDP com login automatico em $RdpPath" }
else { Fail "Arquivo .rdp nao criado"; exit 1 }

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
else { Fail "Atalhos nao criados"; exit 1 }

# ============================== 7. VERIFICACAO ==============================
Step "7/7 Verificacao ponta a ponta"
$checks = @(
  @{ N = "Shell headless ativo"; C = "systemctl --user is-active gnome-shell-headless.service"; Want = "active" },
  @{ N = "Dock do Ubuntu ativo"; C = "gnome-extensions list --enabled 2>/dev/null | grep -q ubuntu-dock && echo YES || echo NO"; Want = "YES" },
  @{ N = "RDP ouvindo :$RDP_PORT"; C = "ss -tlnp 2>/dev/null | grep -q ':$RDP_PORT' && echo YES || echo NO"; Want = "YES" }
)
foreach ($t in $checks) {
  $r = Invoke-Wsl $LinuxUser $t.C
  if ($r.Out -match $t.Want) { Ok $t.N } else { Fail "$($t.N) (ret: $($r.Out.Trim()))" }
}
if (Test-Path $RdpPath) { Ok "Login automatico pronto (abre direto, sem senha)" }
else { Fail "Arquivo .rdp sumiu"; exit 1 }

Write-Host ""
if ($script:Failures.Count -eq 0) {
  Remove-Item $LogFile -Force -ErrorAction SilentlyContinue  # higiene: transcript guarda a senha
  Clear-ResumeState  # higiene: estado de retomada guarda a senha (DPAPI)
  $ip = (wsl -d $DISTRO -- hostname -I 2>$null) -split '\s+' | Where-Object { $_ } | Select-Object -First 1
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
  exit 1
}
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
:::PS1-BODY-END
