# View TUI nativa (MVVM): so render + leitura de tecla, sem decisao de instalacao.
# Zero dependencia (Windows PowerShell 5.1 inbox). Com fallback Read-Host quando
# nao ha console interativo (pipe, -NoTui, hosts sem UI). Logica de indice pura
# em Move-MenuIndex para cobrir no Pester sem precisar de teclado.
function Move-MenuIndex {
  [CmdletBinding()]
  param(
    [int]$Current,
    [int]$Direction,
    [int]$Count
  )
  if ($Count -le 0) { return 0 }
  $next = $Current + $Direction
  if ($next -lt 0) { return 0 }
  if ($next -ge $Count) { return ($Count - 1) }
  return $next
}

function Test-TuiAvailable {
  [CmdletBinding()]
  param([switch]$NoTui)
  if ($NoTui) { return $false }
  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if ([Console]::IsInputRedirected) { return $false }
  } catch { return $false }
  if ($Host.Name -notmatch 'ConsoleHost') { return $false }
  return $true
}

# Menu de escolha unica com setas + Enter. Retorna o indice 0-based selecionado.
# Fallback: prompt numerico via Read-Host (mesmo contrato de retorno).
function Show-SingleChoiceMenu {
  [CmdletBinding()]
  param(
    [string]$Title,
    [string[]]$Options,
    [int]$DefaultIndex = 0,
    [switch]$NoTui
  )
  if (-not $Options -or $Options.Count -eq 0) { return 0 }
  $selected = $DefaultIndex
  if ($selected -lt 0) { $selected = 0 }
  if ($selected -ge $Options.Count) { $selected = $Options.Count - 1 }
  if (-not (Test-TuiAvailable -NoTui:$NoTui)) {
    for ($i = 0; $i -lt $Options.Count; $i++) {
      Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i])
    }
    $raw = Read-Host ("{0} [{1}]" -f $Title, ($selected + 1))
    if ([string]::IsNullOrWhiteSpace($raw)) { return $selected }
    $n = 0
    if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
      return ($n - 1)
    }
    return $selected
  }
  try {
    [Console]::CursorVisible = $false
  } catch {}
  try {
    $done = $false
    while (-not $done) {
      Write-Host ""
      Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
      for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -eq $selected) {
          Write-Host ("  > [{0}] {1}" -f ($i + 1), $Options[$i]) -ForegroundColor Green
        } else {
          Write-Host ("    [{0}] {1}" -f ($i + 1), $Options[$i])
        }
      }
      Write-Host "  (setas + Enter)" -ForegroundColor DarkGray
      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow' { $selected = Move-MenuIndex -Current $selected -Direction -1 -Count $Options.Count }
        'DownArrow' { $selected = Move-MenuIndex -Current $selected -Direction 1 -Count $Options.Count }
        'Enter' { $done = $true }
        'Escape' { $done = $true }
        default {
          $digit = "$($key.KeyChar)"
          $n = 0
          if ([int]::TryParse($digit, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            $selected = $n - 1
            $done = $true
          }
        }
      }
      if (-not $done) {
        # Reposiciona sem reler o cursor no Unix: la, CursorTop expoe DSR via
        # stdin e rouba bytes das setas/Enter digitados junto (race). Win32 usa
        # API de console real (sem DSR, sem race); Unix limpa a tela (sem flicker
        # relevante num menu de 2-3 linhas) com fallback so-anexa.
        $moved = $false
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
          try {
            $top = [Console]::CursorTop - ($Options.Count + 3)
            if ($top -lt 0) { $top = 0 }
            [Console]::SetCursorPosition(0, $top)
            $moved = $true
          } catch {}
        }
        if (-not $moved) {
          try { Clear-Host } catch {}
        }
      }
    }
  } finally {
    try {
      [Console]::CursorVisible = $true
    } catch {}
    Write-Host ""
  }
  return $selected
}

# Leitura de senha com eco de asteriscos. Retorna SecureString como Read-Host -AsSecureString.
function Read-TuiSecurePassword {
  [CmdletBinding()]
  param([string]$Prompt = "Senha", [switch]$NoTui)
  if (-not (Test-TuiAvailable -NoTui:$NoTui)) {
    return (Read-Host $Prompt -AsSecureString)
  }
  $secure = New-Object Security.SecureString
  Write-Host ("{0}: " -f $Prompt) -NoNewline
  $done = $false
  while (-not $done) {
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'Enter' { $done = $true }
      'Backspace' {
        if ($secure.Length -gt 0) {
          $secure.RemoveAt($secure.Length - 1)
          try { [Console]::Write("`b `b") } catch {}
        }
      }
      'Escape' { $secure.Clear(); $done = $true }
      default {
        if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
          $secure.AppendChar($key.KeyChar)
          try { [Console]::Write("*") } catch {}
        }
      }
    }
  }
  Write-Host ""
  $secure.MakeReadOnly()
  return $secure
}
