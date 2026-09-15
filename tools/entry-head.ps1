[CmdletBinding()]
param([switch]$Resume, [switch]$Unattended)
$SCRIPT_VERSION = "0.1.0"
try { Start-Transcript -Path (Join-Path $env:TEMP 'Ubuntu-GUI-install.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
# Auto-elevacao: varios pontos exigem admin (WSL, mstsc, CFA). Via .cmd, o lote
# ja relancou elevado (caixa preta) - este bloco so age no uso direto do ps1
# (ex.: retomada RunOnce), com UM clique no UAC - bypass silencioso nao existe.
# -Unattended nunca relanca (ninguem clicaria no UAC: rode o .cmd ja elevado).
if ((-not $Unattended) -and (-not $env:UBUNTUGUI_FROM_CMD)) {
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

$SCRIPT_BUILD = "__BUILD_ID__"
Write-Host "Ubuntu-GUI Installer v$SCRIPT_VERSION (build $SCRIPT_BUILD)" -ForegroundColor Cyan
$script:UbuntuGuiBannerShown = $true
