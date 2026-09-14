# Gestor de cofre (credencial RDP no Secret Service via gnome-keyring/grdctl).
# Todo acesso ao cofre passa por aqui: elimina a duplicacao entre Install
# (etapa 5) e Get-WslUbuntuGuiStatus e nunca engole resultado (sem Out-Null
# cego). I/O com o daemon fica isolado nestas fronteiras; retry e mensagens
# ficam na View. Cobertura Pester no construtor puro.
function New-WslSessionEnv([string]$Uid) {
  return "XDG_RUNTIME_DIR=/run/user/$Uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$Uid/bus"
}

# Desbloqueia o cofre 'login' com a senha informada. Retorna @{ Code; Out }.
# Code != 0 = senha nao confere ou daemon fora: o chamador falha rapido com
# instrucao (nunca retry cego que queima 2x60s). PIPESTATUS[1] e o exit do
# unlock (sem ele, o tail mascarava tudo com 0).
function Unlock-WslKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return Invoke-Wsl $LinuxUser "printf '%s' '$PasswordQuote' | $envPrefix gnome-keyring-daemon --unlock 2>&1 | tail -n 3; exit `${PIPESTATUS[1]}"
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
