# Escapa a senha para embutir em 'bash -c "..."' (escapa bash + PowerShell).
function Get-PasswordQuote([string]$Password) {
  return ($Password -replace "'", "'\''") -replace '`', '``' -replace '\$', '`$' -replace '"', '`"'
}
