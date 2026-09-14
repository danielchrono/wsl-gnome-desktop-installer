try {
  Install-WslUbuntuGui -Resume:$Resume
  exit 0
} catch {
  Write-Host "FALHA: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
} finally {
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
}
