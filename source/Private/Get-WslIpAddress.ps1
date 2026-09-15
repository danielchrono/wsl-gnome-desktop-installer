# Primeiro IP do WSL. SSOT do comando (antes copiado 3x no Install):
# 'hostname -I' pode vir com varios IPs + espacos; o parse vive em Get-FirstIpAddress.
function Get-WslIpAddress([string]$Distro) {
  $d = $Distro
  if ([string]::IsNullOrWhiteSpace($d)) { try { $d = $DISTRO } catch { $d = $null } }
  if ([string]::IsNullOrWhiteSpace($d)) { $d = 'Ubuntu' }
  return Get-FirstIpAddress (wsl -d $d -- hostname -I 2>$null)
}
