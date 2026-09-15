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
  [string]$WRdpPath = ''
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
RDPREWRITE_VAL
if exist "%MSTSC%" (start "APP_NAME" "%MSTSC%" "%RDPPATH%") else (%WSL% -d %DISTRO% -u LINUXUSER_VAL -- FREERDP_VAL "W_RDP_VAL")
'@
  return ($cmd -replace "APP_NAME", $AppName -replace "DISTRO_VAL", $Distro `
    -replace "LINUXUSER_VAL", $LinuxUser -replace "RDPREWRITE_VAL", $RewriteBlock `
    -replace "RDP_PORT_VAL", $RdpPort -replace "THUMBPRINT_VAL", $Thumbprint `
    -replace "SHELLSVC_VAL", $script:UbuntuGuiDefaults.ShellService `
    -replace "RDPSVC_VAL", $script:UbuntuGuiDefaults.RdpService `
    -replace "IPDISCOVERY_VAL", $DiscoveryBlock `
    -replace "FREERDP_VAL", $FreeRdpBin -replace "W_RDP_VAL", $WRdpPath)
}
