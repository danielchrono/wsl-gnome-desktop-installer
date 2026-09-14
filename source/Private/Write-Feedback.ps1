# View (MVVM): so render no console, sem decisao. O estado de falhas vive no
# ViewModel (Install-WslUbuntuGui, variavel local); $script:Failures segue como
# compat legada espelhada para codigo externo que ainda le o global.
$script:Failures = @()
function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }
function Fail([string]$msg) { Write-Host "  [FALHA] $msg" -ForegroundColor Red; $script:Failures += $msg }

# Estado explicito (FP): hashtable imutavel por copia. Novo codigo prefere estas.
function New-UbuntuGuiFeedbackState {
  [CmdletBinding()]
  param()
  return @{ Failures = @() }
}
function Add-UbuntuGuiFailure {
  [CmdletBinding()]
  param([hashtable]$State, [string]$Message)
  $base = @()
  if ($State -and $State.Failures) { $base = @($State.Failures) }
  return @{ Failures = @($base + $Message) }
}
function Get-UbuntuGuiFailures {
  [CmdletBinding()]
  param([hashtable]$State)
  if ($State -and $State.ContainsKey('Failures')) { return @($State.Failures) }
  return @($script:Failures)
}
