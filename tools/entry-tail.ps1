try {
  Install-WslUbuntuGui -Resume:$Resume -Unattended:$Unattended
  exit 0
} catch {
  # Sem eco duplicado: falha controlada ja imprimiu [FALHA] com detalhe.
  if ($env:UBUNTUGUI_FAIL_REPORTED) { Write-Host "FALHA (detalhes acima)" -ForegroundColor Red }
  else { Write-Host "FALHA: $($_.Exception.Message)" -ForegroundColor Red }
  exit 1
} finally {
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
}
