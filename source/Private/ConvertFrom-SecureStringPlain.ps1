# Converte SecureString em texto puro p/ embutir no bash (uso imediato, sem log).
# SSOT da conversao (antes copiada 3x no Install): PtrToStringUni + ZeroFreeBSTR
# juntos — sem o ZeroFreeBSTR a senha ficava no BSTR alem do necessario.
function ConvertFrom-SecureStringPlain([System.Security.SecureString]$Secure) {
  if (-not $Secure) { return '' }
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
