function Get-WslUbuntuGuiStatus {
<#
.SYNOPSIS
  Le o estado do desktop Ubuntu/WSL (somente leitura, seguro rodar sempre).
.EXEMPLO
  Get-WslUbuntuGuiStatus -Distro Ubuntu -LinuxUser daniel | Format-List
#>
[CmdletBinding()]
param(
  [string]$Distro = "Ubuntu",
  [Parameter(Mandatory)] [string]$LinuxUser,
  [int]$RdpPort = 3390
)
$DISTRO = $Distro
$RDP_PORT = $RdpPort
$D = $script:UbuntuGuiDefaults
$shell = (Invoke-Wsl $LinuxUser "systemctl --user is-active $($D.ShellService)").Out.Trim()
$rdp = Invoke-Wsl $LinuxUser "systemctl --user is-active $($D.RdpService) && ss -tlnp 2>/dev/null | grep -q ':$RDP_PORT' && echo OK || echo DOWN"
$cred = (Invoke-Wsl $LinuxUser "grdctl status 2>/dev/null | grep -E 'Username:' | grep -qv '(empty)' && echo YES || echo NO").Out.Trim()
return [pscustomobject]@{
  Distro           = $Distro
  LinuxUser        = $LinuxUser
  RdpPort          = $RdpPort
  ShellActive      = ($shell -eq 'active')
  RdpListening     = ($rdp.Out -match 'OK')
  CredentialsSet   = ($cred -eq 'YES')
}
}
