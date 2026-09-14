# Primeiro IP de 'hostname -I' (pode vir com varios + espacos).
function Get-FirstIpAddress([string]$HostnameI) {
  return ($HostnameI -split '\s+' | Where-Object { $_ } | Select-Object -First 1)
}
