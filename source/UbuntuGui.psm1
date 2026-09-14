# Loader do modulo: importa Private (helpers) + Public (exportadas).
# No .cmd instalador estas mesmas funcoes vao concatenadas (tools/build_single.py).
$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$Public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($f in @($Private + $Public)) {
  try { . $f.FullName } catch { Write-Error "Falha ao importar $($f.FullName): $_"; throw }
}
Export-ModuleMember -Function $Public.BaseName
