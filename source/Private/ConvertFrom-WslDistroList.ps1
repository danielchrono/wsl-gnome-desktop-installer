# Normaliza a saida de 'wsl -l -q' (NULs, espacos, linhas vazias).
function ConvertFrom-WslDistroList([string[]]$Raw) {
  return ($Raw -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
