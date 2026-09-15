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
