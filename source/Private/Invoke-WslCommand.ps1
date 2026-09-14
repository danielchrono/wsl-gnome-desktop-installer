# Roda 'wsl -d $DISTRO ...' repassando o exit code real do Linux.
# NOTA: $DISTRO vem do escopo chamador (Install-WslUbuntuGui / Get-WslUbuntuGuiStatus
# definem como local; o escopo dinamico do PowerShell alcanca ambos os modos:
# modulo importado e .cmd concatenado). Proposital para nao churnar ~30 chamadas.
function Invoke-Wsl([string]$AsUser, [string]$Command) {
  $out = wsl -d $DISTRO -u $AsUser --exec bash -c $Command 2>&1
  return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}
function Invoke-WslRoot([string]$Command) { return Invoke-Wsl "root" $Command }
