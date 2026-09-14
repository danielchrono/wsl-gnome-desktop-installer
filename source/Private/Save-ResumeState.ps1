# Retomada sozinha apos reboot: salva respostas (senha em DPAPI, so este usuario le),
# copia o script em execucao p/ a pasta do app e agenda reabertura via RunOnce.
# -SourceScript: caminho do script a reexecutar (no .cmd, o TEMP extraido; no modulo,
# a retomada so faz sentido via script/.cmd - o chamador passa $PSCommandPath).
function Save-ResumeState(
  [string]$SourceScript,
  [string]$ProgDir,
  [string]$ResumeFile,
  [string]$ResumePs1,
  [string]$RunOncePath,
  [string]$RunOnceName,
  [string]$LinuxUser,
  [string]$LinuxPass,
  [string]$NetChoice
) {
  if (-not (Test-Path $ProgDir)) { New-Item -ItemType Directory -Path $ProgDir -Force | Out-Null }
  Copy-Item -Path $SourceScript -Destination $ResumePs1 -Force
  $enc = [Convert]::ToBase64String(
    [Security.Cryptography.ProtectedData]::Protect(
      [Text.Encoding]::UTF8.GetBytes($LinuxPass), $null, 'CurrentUser'))
  @{ Phase = "AfterReboot"; LinuxUser = $LinuxUser; LinuxPassEnc = $enc; NetChoice = $NetChoice } |
    ConvertTo-Json -Compress | Set-Content $ResumeFile
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ResumePs1`" -Resume"
  New-ItemProperty -Path $RunOncePath -Name $RunOnceName -Value $cmd -PropertyType String -Force | Out-Null
  Ok "Retomada agendada (reabre sozinho apos o reboot)"
}
function Clear-ResumeState([string]$RunOncePath, [string]$RunOnceName, [string]$ResumeFile, [string]$ResumePs1) {
  Remove-ItemProperty -Path $RunOncePath -Name $RunOnceName -ErrorAction SilentlyContinue | Out-Null
  Remove-Item $ResumeFile, $ResumePs1 -Force -ErrorAction SilentlyContinue | Out-Null
}
