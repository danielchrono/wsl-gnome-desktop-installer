# Valida o header do .ico (magic 00 00 01 00 + count >= 1): arquivo
# corrompido (PNG renomeado, download falho, 0 bytes) passa no Test-Path
# e deixa o .lnk sem imagem - o passo 6 refaz nesses casos.
function Test-ValidIco([string]$Path) {
  try {
    $b = [IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 6 -and $b[0] -eq 0 -and $b[1] -eq 0 -and ([BitConverter]::ToUInt16($b, 2) -eq 1) -and ([BitConverter]::ToUInt16($b, 4) -ge 1))
  } catch { return $false }
}
