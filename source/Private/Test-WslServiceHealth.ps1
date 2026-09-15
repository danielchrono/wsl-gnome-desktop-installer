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
