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
