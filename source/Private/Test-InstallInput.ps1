# ViewModel puro (MVVM): validacao sem I/O, sem global, sem WSL.
# Todas retornam dados, nunca escrevem na tela nem lancam para fluxo normal
# (o orquestrador Install-WslUbuntuGui decide mensagem/throw). Cobertas no Pester.
function Test-LinuxUserName {
  [CmdletBinding()]
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    return @{ Ok = $false; Reason = 'empty' }
  }
  if ($Name -eq 'root') {
    return @{ Ok = $false; Reason = 'reserved' }
  }
  if ($Name -cnotmatch '^[a-z_][a-z0-9_-]*$') {
    return @{ Ok = $false; Reason = 'pattern' }
  }
  return @{ Ok = $true; Reason = '' }
}

# Normaliza a escolha de rede do prompt/TUI ('1' = localhost mirrored, '2' = dinamico).
# Preserva a regra historica: vazio ou qualquer coisa != '2' vira mirrored.
function Resolve-NetworkChoice {
  [CmdletBinding()]
  param([string]$NetChoice)
  $norm = if ([string]::IsNullOrWhiteSpace($NetChoice)) { '1' } else { $NetChoice.Trim() }
  if ([string]::IsNullOrWhiteSpace($norm)) { $norm = '1' }
  return @{ Normalized = $norm; WantMirrored = ($norm -ne "2") }
}

# Default do usuario Linux: salvo entre runs > windows user sanitizado > 'ubuntu'. Puro.
function Get-DefaultLinuxUser {
  [CmdletBinding()]
  param([string]$SavedUser, [string]$WindowsUser)
  $saved = if ($SavedUser) { $SavedUser.Trim() } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($saved)) { return $saved }
  $defUser = if ($WindowsUser) { ($WindowsUser.ToLower() -replace '[^a-z0-9]', '') } else { '' }
  if ([string]::IsNullOrWhiteSpace($defUser)) { $defUser = "ubuntu" }
  return $defUser
}

# Escolha usar-capturado vs criar-novo (menu TUI, indice 0 = usar). Pura: vazia
# volta ao padrao; digitado vai como esta (validacao vem depois, sem mudanca).
function Resolve-UserMenuChoice {
  [CmdletBinding()]
  param([int]$MenuIndex, [string]$TypedName, [string]$DefaultUser)
  if ($MenuIndex -ne 1) { return $DefaultUser }
  if ([string]::IsNullOrWhiteSpace($TypedName)) { return $DefaultUser }
  return $TypedName
}
