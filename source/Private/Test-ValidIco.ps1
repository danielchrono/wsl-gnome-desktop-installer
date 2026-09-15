# Valida o .ico inteiro (header + tabela de entradas + dados): header sozinho
# (download truncado) passava e deixava o .lnk sem imagem - o passo 6 refaz
# nesses casos e o atalho so aponta para o .ico quando ele passa aqui.
function Test-ValidIco([string]$Path) {
  try {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 6 -or $b[0] -ne 0 -or $b[1] -ne 0) { return $false }
    if ([BitConverter]::ToUInt16($b, 2) -ne 1) { return $false }
    $count = [BitConverter]::ToUInt16($b, 4)
    if ($count -lt 1 -or $count -gt 255) { return $false }
    if ($b.Length -lt 6 + $count * 16) { return $false }
    for ($i = 0; $i -lt $count; $i++) {
      $o = 6 + $i * 16
      $size = [BitConverter]::ToUInt32($b, $o + 8)
      $off = [BitConverter]::ToUInt32($b, $o + 12)
      if ($size -lt 1) { return $false }
      if (($off + $size) -gt $b.Length) { return $false }
    }
    return $true
  } catch { return $false }
}
