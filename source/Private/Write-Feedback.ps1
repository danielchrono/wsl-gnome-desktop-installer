# Feedback padrao do instalador. $script:Failures acumula falhas nao-fatais;
# Install-WslUbuntuGui zera no inicio e avalia no final (etapa 7).
$script:Failures = @()
function Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "  [FALHA] $msg" -ForegroundColor Red; $script:Failures += $msg }
