# Loader do modulo: importa Private (helpers) + Public (exportadas).
# No .cmd instalador estas mesmas funcoes vao concatenadas (tools/build_single.py).
# Ordem fixa: Constants primeiro (Model), resto alfabetico, Public por ultimo.
$PrivateFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$Public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)
$Private = @($PrivateFiles | Where-Object { $_.Name -eq 'UbuntuGui-Constants.ps1' }) + `
  @($PrivateFiles | Where-Object { $_.Name -ne 'UbuntuGui-Constants.ps1' } | Sort-Object Name)
foreach ($f in @($Private + $Public)) {
  try { . $f.FullName } catch { Write-Error "Falha ao importar $($f.FullName): $_"; throw }
}
Export-ModuleMember -Function $Public.BaseName
