[CmdletBinding()]
param([switch]$Resume, [switch]$Unattended)
$SCRIPT_VERSION = "0.1.0"
try { Start-Transcript -Path (Join-Path $env:TEMP 'Ubuntu-GUI-install.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
# Auto-elevacao: varios pontos exigem admin (WSL, mstsc, CFA). Relanca elevado
# com UM clique no UAC - bypass silencioso nao existe (seria vulnerabilidade).
# -Unattended nunca relanca (ninguem clicaria no UAC: rode o .cmd ja elevado).
if (-not $Unattended) {
  $isAdminHead = $false
  try { $isAdminHead = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $isAdminHead = $false }
  if (-not $isAdminHead) {
    try {
      Write-Host "  Elevando a admin (confirme no UAC uma vez)..." -ForegroundColor Yellow
      $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
      if ((-not [Environment]::Is64BitProcess) -and (Test-Path "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe")) { $psExe = "$env:SystemRoot\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
      $psiArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
      if ($Resume) { $psiArgs += ' -Resume' }
      Start-Process -FilePath $psExe -ArgumentList $psiArgs -Verb RunAs -Wait -ErrorAction Stop
      exit 0
    } catch { Write-Host "  Sem elevacao: segue sem admin (algumas etapas avisam e pulam)..." -ForegroundColor Yellow }
  }
}
