# Pester do modulo UbuntuGui (sintaxe v3: roda no Windows PowerShell 5.1).
#   powershell -NoProfile -Command 'Invoke-Pester -Script <este arquivo>'
# So cobre helpers puras (sem WSL/rede/registro). O fluxo E2E vive na suite python.
$ModulePath = Join-Path $PSScriptRoot '..\source\UbuntuGui.psd1'
Import-Module $ModulePath -Force

Describe 'Modulo UbuntuGui' {
  It 'exporta Install-WslUbuntuGui e Get-WslUbuntuGuiStatus' {
    $names = Get-Command -Module UbuntuGui | Select-Object -ExpandProperty Name
    ($names -contains 'Install-WslUbuntuGui') | Should Be $true
    ($names -contains 'Get-WslUbuntuGuiStatus') | Should Be $true
  }
}

Describe 'UbuntuGui-Constants' {
  . (Join-Path $PSScriptRoot '..\source\Private\UbuntuGui-Constants.ps1')
  It 'porta longe da 3389 (erro 0x708)' {
    $script:UbuntuGuiDefaults.RdpPort | Should Be 3390
  }
  It 'mirrored exige Win11 22H2+' {
    $script:UbuntuGuiDefaults.MinBuildMirrored | Should Be 22621
  }
  It 'retries e timeouts sanos' {
    $script:UbuntuGuiDefaults.CredTimeoutSec | Should Be 60
    $script:UbuntuGuiDefaults.CredRetries | Should Be 2
    $script:UbuntuGuiDefaults.AptRetries | Should Be 3
  }
}

# Privates rodam no session state do modulo: & (Get-Module UbuntuGui) { ... }
Describe 'Get-PasswordQuote' {
  It 'mantem texto simples' {
    (& (Get-Module UbuntuGui) { Get-PasswordQuote 'abc123' }) | Should Be 'abc123'
  }
  It "escapa apostrofo p/ bash" {
    (& (Get-Module UbuntuGui) { Get-PasswordQuote "a'b" }) | Should Be "a'\''b"
  }
  It 'escapa $ p/ PowerShell' {
    (& (Get-Module UbuntuGui) { Get-PasswordQuote 'a$b' }) | Should Be 'a`$b'
  }
  It 'escapa crase e aspas' {
    (& (Get-Module UbuntuGui) { Get-PasswordQuote 'a`"b' }) | Should Be 'a```"b'
  }
}

Describe 'ConvertFrom-WslDistroList' {
  It 'remove NULs, espacos e vazios' {
    (& (Get-Module UbuntuGui) { (ConvertFrom-WslDistroList @("Ubuntu`0", '  ', 'Debian')) -join ',' }) | Should Be 'Ubuntu,Debian'
  }
}

Describe 'Get-FirstIpAddress' {
  It 'pega o primeiro IP' {
    (& (Get-Module UbuntuGui) { Get-FirstIpAddress ' 192.168.1.5 10.0.0.2 ' }) | Should Be '192.168.1.5'
  }
  It 'vazio retorna nulo' {
    (& (Get-Module UbuntuGui) { Get-FirstIpAddress '   ' }) | Should BeNullOrEmpty
  }
}

Describe 'New-RdpFileContent' {
  $rdp = & (Get-Module UbuntuGui) { New-RdpFileContent -RdpHost '127.0.0.1' -RdpPort 3390 -LinuxUser 'daniel' -PasswordHex 'aabb' -Resolution '1600x900' }
  It 'traz endereco e usuario' {
    ($rdp -join "`n") | Should Match 'full address:s:127.0.0.1:3390'
    ($rdp -join "`n") | Should Match 'username:s:daniel'
  }
  It 'traz resolucao e login automatico' {
    ($rdp -contains 'desktopwidth:i:1600') | Should Be $true
    ($rdp -contains 'prompt for credentials:i:0') | Should Be $true
  }
  It 'sem aviso de cert autoassinado' {
    ($rdp -contains 'authentication level:i:0') | Should Be $true
  }
  It 'abre em janela e redireciona USB' {
    ($rdp -contains 'screen mode id:i:1') | Should Be $true
    ($rdp -contains 'usbdevicestoredirect:s:*') | Should Be $true
  }
  It 'sessao acompanha a janela (sem barras pretas)' {
    ($rdp -contains 'smart sizing:i:1') | Should Be $true
  }
}

Describe 'New-LauncherContent' {
  $c = & (Get-Module UbuntuGui) { New-LauncherContent -AppName 'Ubuntu-GUI' -Distro 'Ubuntu' -LinuxUser 'daniel' `
    -RdpPort 3390 -Thumbprint 'ABC123' -DiscoveryBlock 'rem X' -RewriteBlock 'rem Y THUMBPRINT_VAL' -RdpWidth 1600 -RdpHeight 900 }
  It 'troca todos os placeholders' {
    $c | Should Not Match 'DISTRO_VAL|RDP_PORT_VAL|THUMBPRINT_VAL|IPDISCOVERY_VAL|RDPREWRITE_VAL|LINUXUSER_VAL|SHELLSVC_VAL|RDPSVC_VAL|FREERDP_VAL|W_RDP_VAL|RDP_W_VAL|RDP_H_VAL'
  }
  It 'embute thumbprint e usuario' {
    $c | Should Match 'ABC123'
    $c | Should Match 'daniel'
  }
  It 'sem reserva mantem o erro de mstsc ausente' {
    $c | Should Match 'mstsc.exe nao encontrado'
  }
  $f = & (Get-Module UbuntuGui) { New-LauncherContent -AppName 'Ubuntu-GUI' -Distro 'Ubuntu' -LinuxUser 'daniel' `
    -RdpPort 3390 -Thumbprint 'ABC123' -DiscoveryBlock 'rem X' -RewriteBlock 'rem Y' -FreeRdpBin '/usr/bin/xfreerdp' -WRdpPath '/mnt/c/Ubuntu-GUI.rdp' -RdpWidth 1600 -RdpHeight 900 }
  It 'com reserva chama o cliente do WSL quando sem mstsc' {
    $f | Should Match '/usr/bin/xfreerdp'
    $f | Should Match '/mnt/c/Ubuntu-GUI.rdp'
  }
  It 'com reserva nao deixa placeholder' {
    $f | Should Not Match 'FREERDP_VAL|W_RDP_VAL'
  }
  It 'tenta login sem aviso via cofre antes do rdp' {
    $c | Should Match 'CREDHELPER'
    $c | Should Match '/v:'
    $c | Should Match '/w:1600'
  }
  It 'abre copia por clique (mstsc nao invalida o original)' {
    $c | Should Match 'RUNRDP'
    $c | Should Match 'copy /y'
    $c | Should Match '"%MSTSC%" "%RUNRDP%"'
  }
}

Describe 'Test-LinuxUserName' {
  It 'aceita nome valido' {
    (& (Get-Module UbuntuGui) { (Test-LinuxUserName -Name 'daniel').Ok }) | Should Be $true
  }
  It 'rejeita root como reservado' {
    (& (Get-Module UbuntuGui) { (Test-LinuxUserName -Name 'root').Reason }) | Should Be 'reserved'
  }
  It 'rejeita maiusculas e vazio' {
    (& (Get-Module UbuntuGui) { (Test-LinuxUserName -Name 'Daniel').Ok }) | Should Be $false
    (& (Get-Module UbuntuGui) { (Test-LinuxUserName -Name '').Ok }) | Should Be $false
  }
}

Describe 'Resolve-NetworkChoice' {
  It 'vazio vira mirrored padrao' {
    (& (Get-Module UbuntuGui) { (Resolve-NetworkChoice -NetChoice '').WantMirrored }) | Should Be $true
    (& (Get-Module UbuntuGui) { (Resolve-NetworkChoice -NetChoice $null).Normalized }) | Should Be '1'
  }
  It '2 vira dinamico' {
    (& (Get-Module UbuntuGui) { (Resolve-NetworkChoice -NetChoice '2').WantMirrored }) | Should Be $false
  }
}

Describe 'Resolve-UserMenuChoice' {
  It 'indice 0 usa o capturado mesmo com digitado' {
    (& (Get-Module UbuntuGui) { Resolve-UserMenuChoice -MenuIndex 0 -TypedName 'outro' -DefaultUser 'salvo' }) | Should Be 'salvo'
  }
  It 'novo com nome usa o digitado; vazio volta ao padrao' {
    (& (Get-Module UbuntuGui) { Resolve-UserMenuChoice -MenuIndex 1 -TypedName 'novo1' -DefaultUser 'salvo' }) | Should Be 'novo1'
    (& (Get-Module UbuntuGui) { Resolve-UserMenuChoice -MenuIndex 1 -TypedName '   ' -DefaultUser 'salvo' }) | Should Be 'salvo'
  }
}

Describe 'Test-UnlockedPropertyOutput' {
  It 'so b false prova destravado (fail-closed)' {
    (& (Get-Module UbuntuGui) { Test-UnlockedPropertyOutput -Out 'b false' }) | Should Be $true
    (& (Get-Module UbuntuGui) { Test-UnlockedPropertyOutput -Out 'b true' }) | Should Be $false
    (& (Get-Module UbuntuGui) { Test-UnlockedPropertyOutput -Out '' }) | Should Be $false
    (& (Get-Module UbuntuGui) { Test-UnlockedPropertyOutput -Out 'Failed to get property: No such interface' }) | Should Be $false
  }
}

Describe 'Test-MissingCollectionOutput' {
  It 'alias default ausente e Missing (texto busctl ao vivo)' {
    (& (Get-Module UbuntuGui) { Test-MissingCollectionOutput -Out "Failed to get property Locked on interface org.freedesktop.Secret.Collection: Unknown object '/org/freedesktop/secrets/aliases/default'." }) | Should Be $true
  }
  It 'colecao login ausente e Missing (resposta do daemon ao vivo)' {
    (& (Get-Module UbuntuGui) { Test-MissingCollectionOutput -Out 'Failed to get property Locked on interface org.freedesktop.Secret.Collection: Object does not exist at path “/org/freedesktop/secrets/collection/login”' }) | Should Be $true
  }
  It 'trancado/destravado/vazio/bus-fora nao sao Missing (fail-closed)' {
    (& (Get-Module UbuntuGui) {
      @((Test-MissingCollectionOutput -Out 'b true'), (Test-MissingCollectionOutput -Out 'b false'), (Test-MissingCollectionOutput -Out ''), (Test-MissingCollectionOutput -Out 'Failed to connect to bus: No such file')) -join ','
    }) | Should Be 'False,False,False,False'
  }
}

Describe 'Test-ValidIco' {
  It 'aceita ico completo e rejeita truncado/lixo (fail-closed)' {
    (& (Get-Module UbuntuGui) {
      $d = Join-Path $env:TEMP ('ubuntugui-ico-' + [Guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $d -Force | Out-Null
      try {
        $ok = Join-Path $d 'ok.ico'; $trunc = Join-Path $d 'trunc.ico'; $bad = Join-Path $d 'bad.ico'; $short = Join-Path $d 'short.ico'
        $head = [byte[]](0,0,1,0,1,0)
        $ent = [byte[]](32,32,0,0,1,0,32,0,4,0,0,0,22,0,0,0)
        $dat = [byte[]](0xAA,0xBB,0xCC,0xDD)
        [IO.File]::WriteAllBytes($ok, $head + $ent + $dat)
        [IO.File]::WriteAllBytes($trunc, $head)
        [IO.File]::WriteAllBytes($bad, [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A))
        [IO.File]::WriteAllBytes($short, [byte[]](0,0,1,0))
        @((Test-ValidIco -Path $ok), (Test-ValidIco -Path $trunc), (Test-ValidIco -Path $bad), (Test-ValidIco -Path $short), (Test-ValidIco -Path (Join-Path $d 'falta.ico'))) -join ','
      } finally { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    }) | Should Be 'True,False,False,False,False'
  }
}

Describe 'New-WslSessionEnv' {
  It 'monta XDG e bus da sessao' {
    (& (Get-Module UbuntuGui) { New-WslSessionEnv -Uid '1000' }) | Should Be 'XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus'
  }
}

Describe 'Get-WslKeyringProbeState' {
  It "classifica 'b false' como Unlocked" {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'b false' } }
        (Get-WslKeyringProbeState -LinuxUser 'u' -Uid '1000').State
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'Unlocked'
  }
  It "classifica 'b true' como Locked" {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'b true' } }
        (Get-WslKeyringProbeState -LinuxUser 'u' -Uid '1000').State
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'Locked'
  }
  It 'classifica erro de bus como Error (nao Locked)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 1; Out = 'Failed to connect to bus: No such file' } }
        $s = Get-WslKeyringProbeState -LinuxUser 'u' -Uid '1000'
        @($s.State, (Test-WslKeyringUnlocked -LinuxUser 'u' -Uid '1000')) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'Error,False'
  }
  It 'classifica saida vazia como Error' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = '' } }
        (Get-WslKeyringProbeState -LinuxUser 'u' -Uid '1000').State
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'Error'
  }
  It 'classifica daemon sem colecao login como Missing (nao Error)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 1; Out = "Unknown object '/org/freedesktop/secrets/aliases/default'." } }
        (Get-WslKeyringProbeState -LinuxUser 'u' -Uid '1000').State
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'Missing'
  }
  It 're-sonda limitada a 5s (tunable)' {
    (& (Get-Module UbuntuGui) { (Get-UbuntuGuiDefaults).KeyringReprobeSec }) | Should Be 5
  }
}

Describe 'Get-WslKeyringLockDetail' {
  It 'mostra login/arquivos/daemons' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          if ($Command -match 'collection/login') { return @{ Code = 0; Out = 'b true' } }
          if ($Command -match 'keyrings') { return @{ Code = 0; Out = 'login.keyring' } }
          if ($Command -match 'pgrep') { return @{ Code = 0; Out = 'daemons=0' } }
          return @{ Code = 0; Out = '' }
        }
        Get-WslKeyringLockDetail -LinuxUser 'u' -Uid '1000'
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'login Locked=[b true] arquivos=[login.keyring] daemons=0'
  }
  It 'nunca quebra com saidas vazias' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 1; Out = '' } }
        Get-WslKeyringLockDetail -LinuxUser 'u' -Uid '1000'
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'login Locked=[(vazio)] arquivos=[(vazio)] (vazio)'
  }
}

Describe 'Test-WslUnlockExitMeaningful' {
  It 'exit != 0 na falsa => significativo (True)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          return @{ Code = 0; Out = "UBUNTUGUI_UNLOCKCODE=3`nUBUNTUGUI_PROBE=b true" } }
        Test-WslUnlockExitMeaningful -LinuxUser 'u' -Uid '1000'
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be $true
  }
  It 'exit 0 na falsa => stdin nao valida (False)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          return @{ Code = 0; Out = "UBUNTUGUI_UNLOCKCODE=0`nUBUNTUGUI_PROBE=b true" } }
        Test-WslUnlockExitMeaningful -LinuxUser 'u' -Uid '1000'
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be $false
  }
}

Describe 'Start-WslKeyringDaemon' {
  It 'daemon no ar retorna True sem dormir' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:calls = @(); $script:sleeps = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          $script:calls += $Command
          if ($Command -match 'get-property') { return @{ Code = 0; Out = 'b true' } }
          return @{ Code = 0; Out = '' } }
        $r = Start-WslKeyringDaemon -LinuxUser 'u' -Uid '1000'
        @($r, $script:calls.Count) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,2'
  }
  It 'daemon fora retorna False apos 10 tentativas' {
    (& (Get-Module UbuntuGui) {
      $realWsl = ${function:Invoke-Wsl}; $realSleep = ${function:Start-Sleep}
      $script:sleeps = 0
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          return @{ Code = 1; Out = 'Failed to connect to bus' } }
        ${function:Start-Sleep} = { param([int]$Seconds) $script:sleeps++ }
        $r = Start-WslKeyringDaemon -LinuxUser 'u' -Uid '1000'
        @($r, $script:sleeps) -join ','
      } finally { ${function:Invoke-Wsl} = $realWsl; ${function:Start-Sleep} = $realSleep }
    }) | Should Be 'False,10'
  }
  It 'daemon sem colecao conta como no ar (Missing responde)' {
    (& (Get-Module UbuntuGui) {
      $realWsl = ${function:Invoke-Wsl}; $realSleep = ${function:Start-Sleep}
      $script:sleeps = 0
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          if ($Command -match 'get-property') { return @{ Code = 1; Out = "Unknown object '/org/freedesktop/secrets/aliases/default'." } }
          return @{ Code = 0; Out = '' } }
        ${function:Start-Sleep} = { param([int]$Seconds) $script:sleeps++ }
        $r = Start-WslKeyringDaemon -LinuxUser 'u' -Uid '1000'
        @($r, $script:sleeps) -join ','
      } finally { ${function:Invoke-Wsl} = $realWsl; ${function:Start-Sleep} = $realSleep }
    }) | Should Be 'True,0'
  }
}

Describe 'New-WslLoginKeyring' {
  It 'arquivo existente retorna Created sem tocar no PAM' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:cmds = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) $script:cmds += $Command; return @{ Code = 0; Out = 'OK' } }
        $r = New-WslLoginKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000' -KeyringPath 'K'
        @($r.Created, $r.Fresh, $script:cmds.Count, ($script:cmds -join '|' -match '--login')) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,False,1,False'
  }
  It 'ausente cria via --login e retorna Fresh (sem sudo/pam.d)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:n = 0; $script:cmds = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          $script:cmds += $Command
          if ($Command -match 'test -f') { $script:n++; if ($script:n -eq 1) { return @{ Code = 0; Out = 'MISSING' } } return @{ Code = 0; Out = 'OK' } }
          if ($Command -match 'get-property') { return @{ Code = 0; Out = 'b false' } }
          return @{ Code = 0; Out = '' } }
        $r = New-WslLoginKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000' -KeyringPath 'K'
        $joined = $script:cmds -join '|'
        @($r.Created, $r.Fresh, ($joined -match '--daemonize --login'), ($joined -match 'tee'), ($joined -match 'sudo')) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,True,True,False,False'
  }
  It '--login sem arquivo retorna Created False' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'MISSING' } }
        $r = New-WslLoginKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000' -KeyringPath 'K'
        @($r.Created, $r.Fresh) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'False,False'
  }
}

Describe 'Start-WslLoginKeyringDaemon' {
  It 'pkill e --login em chamadas separadas (anti-suicidio)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:cmds = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) $script:cmds += $Command; return @{ Code = 0; Out = 'b false' } }
        $r = Start-WslLoginKeyringDaemon -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000'
        $pk = @($script:cmds | Where-Object { $_ -match 'pkill' })[0]
        $dl = @($script:cmds | Where-Object { $_ -match 'daemonize' })[0]
        @($script:cmds.Count, $r.Started, $r.State, ($pk -notmatch 'daemonize'), ($dl -notmatch 'pkill')) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be '2,True,Unlocked,True,True'
  }
  It 'sonda trancada apos --login retorna Started com Locked' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          if ($Command -match 'get-property') { return @{ Code = 0; Out = 'b true' } }
          return @{ Code = 0; Out = '' } }
        $r = Start-WslLoginKeyringDaemon -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000'
        @($r.Started, $r.State) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,Locked'
  }
}

Describe 'Reset-WslLoginKeyring' {
  It 'recria via --login com backup (sem sudo/pam.d)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:n = 0; $script:cmds = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          $script:cmds += $Command
          if ($Command -match 'date \+') { return @{ Code = 0; Out = '20260915-000000' } }
          if ($Command -match 'test -f') { $script:n++; if ($script:n -eq 1) { return @{ Code = 0; Out = 'MISSING' } } return @{ Code = 0; Out = 'OK' } }
          if ($Command -match 'get-property') { return @{ Code = 0; Out = 'b false' } }
          return @{ Code = 0; Out = '' } }
        $r = Reset-WslLoginKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000' -KeyringPath 'K'
        $joined = $script:cmds -join '|'
        @($r.Recreated, ($r.Backup -match 'bak-'), ($joined -match '--daemonize --login'), ($joined -match 'tee'), ($joined -match 'sudo')) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,True,True,False,False'
  }
  It 'criacao falha restaura o original (2 mvs)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:cmds = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          $script:cmds += $Command
          if ($Command -match 'date \+') { return @{ Code = 0; Out = '20260915-000000' } }
          return @{ Code = 0; Out = 'MISSING' } }
        $r = Reset-WslLoginKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000' -KeyringPath 'K'
        @($r.Recreated, (@($script:cmds | Where-Object { $_ -match '^mv ' }).Count)) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'False,2'
  }
}

Describe 'Repair-WslKeyringBus' {
  It 'mata estranho e reporta (sem tocar nos arquivos)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-WslRoot}
      $script:sent = ''
      try {
        ${function:Invoke-WslRoot} = { param([string]$Command, [string]$Distro) $script:sent = $Command; return @{ Code = 0; Out = "estranho-99-root`nFEITO" } }
        $r = Repair-WslKeyringBus -LinuxUser 'daniel' -Uid '1000' -Distro 'Ubuntu'
        @($r.Repaired, ($script:sent -match 'kill'), ($script:sent -match '/run/user/1000/keyring'), ($script:sent -match 'local/share/keyrings'), ($script:sent -match '\[g\]nome'), ($script:sent -match '\$\$')) -join ','
      } finally { ${function:Invoke-WslRoot} = $real }
    }) | Should Be 'True,True,True,False,True,True'
  }
  It 'sem alvo retorna FEITO puro' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-WslRoot}
      try {
        ${function:Invoke-WslRoot} = { param([string]$Command, [string]$Distro) return @{ Code = 0; Out = 'FEITO' } }
        $r = Repair-WslKeyringBus -LinuxUser 'daniel' -Uid '1000' -Distro 'Ubuntu'
        @($r.Repaired, $r.Detail) -join ','
      } finally { ${function:Invoke-WslRoot} = $real }
    }) | Should Be 'False,FEITO'
  }
}

Describe 'Fail sem eco duplicado' {
  It 'Fail marca UBUNTUGUI_FAIL_REPORTED' {
    (& (Get-Module UbuntuGui) {
      $realFails = @($script:Failures); $realEnv = $env:UBUNTUGUI_FAIL_REPORTED
      try {
        $env:UBUNTUGUI_FAIL_REPORTED = $null
        Fail 'x-teste' | Out-Null
        $env:UBUNTUGUI_FAIL_REPORTED
      } finally { $script:Failures = $realFails; $env:UBUNTUGUI_FAIL_REPORTED = $realEnv }
    }) | Should Be '1'
  }
}

Describe 'Get-WslUnlockPipeline' {
  It 'comando byte-identico ao unlock historico' {
    (& (Get-Module UbuntuGui) { Get-WslUnlockPipeline -PasswordQuote 'pwq' -Uid '1000' }) | Should Be "printf '%s' 'pwq' | XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gnome-keyring-daemon --unlock 2>&1 | tail -n 3"
  }
}

Describe 'Read-UnlockProbeOutput' {
  It 'extrai codigo e sonda (trancado)' {
    (& (Get-Module UbuntuGui) {
      $p = Read-UnlockProbeOutput -Out "SSH_AUTH_SOCK=/x`nUBUNTUGUI_UNLOCKCODE=0`nUBUNTUGUI_PROBE=b true"
      @($p.UnlockCode, $p.Probe) -join ','
    }) | Should Be '0,b true'
  }
  It 'sem marcadores vira Error (-1)' {
    (& (Get-Module UbuntuGui) {
      $p = Read-UnlockProbeOutput -Out 'qualquer lixo'
      @($p.UnlockCode, $p.Probe) -join ','
    }) | Should Be '-1,'
  }
}

Describe 'UnlockAndProbe-WslKeyring' {
  It 'unlock+sonda numa UNICA chamada WSL (Locked)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      $script:calls = @()
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          $script:calls += $Command
          return @{ Code = 0; Out = "UBUNTUGUI_UNLOCKCODE=0`nUBUNTUGUI_PROBE=b true" } }
        $r = UnlockAndProbe-WslKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000'
        @($script:calls.Count, ($script:calls -join '|' -match 'gnome-keyring-daemon --unlock'), ($script:calls -join '|' -match 'get-property'), $r.UnlockCode, $r.State) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be '1,True,True,0,Locked'
  }
  It 'mapeia sonda aberta para Unlocked' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          return @{ Code = 0; Out = "UBUNTUGUI_UNLOCKCODE=0`nUBUNTUGUI_PROBE=b false" } }
        $r = UnlockAndProbe-WslKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000'
        @($r.UnlockCode, $r.State) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be '0,Unlocked'
  }
  It 'mapeia sonda sem colecao para Missing (nao Error)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command)
          return @{ Code = 0; Out = "UBUNTUGUI_UNLOCKCODE=0`nUBUNTUGUI_PROBE=Object does not exist at path /org/freedesktop/secrets/collection/login" } }
        $r = UnlockAndProbe-WslKeyring -LinuxUser 'u' -PasswordQuote 'pwq' -Uid '1000'
        @($r.UnlockCode, $r.State) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be '0,Missing'
  }
}

Describe 'Get-DefaultLinuxUser' {
  It 'prefere o salvo entre runs' {
    (& (Get-Module UbuntuGui) { Get-DefaultLinuxUser -SavedUser '  salvo  ' -WindowsUser 'Daniel' }) | Should Be 'salvo'
  }
  It 'sanitiza o usuario Windows e cai para ubuntu' {
    (& (Get-Module UbuntuGui) { Get-DefaultLinuxUser -SavedUser '' -WindowsUser 'Daniel-1' }) | Should Be 'daniel1'
    (& (Get-Module UbuntuGui) { Get-DefaultLinuxUser -SavedUser '' -WindowsUser '---' }) | Should Be 'ubuntu'
  }
}

Describe 'Move-MenuIndex' {
  It 'trava nas bordas' {
    (& (Get-Module UbuntuGui) { Move-MenuIndex -Current 0 -Direction -1 -Count 2 }) | Should Be 0
    (& (Get-Module UbuntuGui) { Move-MenuIndex -Current 1 -Direction 1 -Count 2 }) | Should Be 1
  }
  It 'anda no meio' {
    (& (Get-Module UbuntuGui) { Move-MenuIndex -Current 0 -Direction 1 -Count 2 }) | Should Be 1
  }
}

Describe 'FeedbackState' {
  It 'acumula por copia sem mutar o original' {
    (& (Get-Module UbuntuGui) {
      $s0 = New-UbuntuGuiFeedbackState
      $s1 = Add-UbuntuGuiFailure -State $s0 -Message 'a'
      if ((Get-UbuntuGuiFailures -State $s0).Count -eq 0) { (Get-UbuntuGuiFailures -State $s1) -join ',' } else { 'MUTOU' }
    }) | Should Be 'a'
  }
}

Describe 'Get-UbuntuGuiDefaults' {
  It 'retorna clone (mutar nao afeta a fonte)' {
    (& (Get-Module UbuntuGui) {
      $a = Get-UbuntuGuiDefaults; $a.RdpPort = 1
      (Get-UbuntuGuiDefaults).RdpPort
    }) | Should Be 3390
  }
}

Describe 'ConvertFrom-SecureStringPlain' {
  It 'round-trip preserva a senha' {
    (& (Get-Module UbuntuGui) {
      ConvertFrom-SecureStringPlain (ConvertTo-SecureString 's3nh@!' -AsPlainText -Force)
    }) | Should Be 's3nh@!'
  }
  It 'nulo vira vazio' {
    (& (Get-Module UbuntuGui) { ConvertFrom-SecureStringPlain $null }) | Should Be ''
  }
}

Describe 'Test-WslServiceHealth' {
  It 'comando do shell e exato' {
    (& (Get-Module UbuntuGui) { Get-WslShellActiveCommand -Service 's.svc' }) | Should Be 'systemctl --user is-active s.svc'
  }
  It 'comando do RDP carrega servico e porta' {
    (& (Get-Module UbuntuGui) { Get-WslRdpListeningCommand -Service 'r.svc' -Port 3390 }) | Should Be "systemctl --user is-active r.svc && ss -tlnp 2>/dev/null | grep -q ':3390' && echo OK || echo DOWN"
  }
  It 'shell exige active exato (inactive nao passa)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'active' } }
        $a = Test-WslShellActive -LinuxUser 'u' -Service 's'
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'inactive' } }
        $i = Test-WslShellActive -LinuxUser 'u' -Service 's'
        @($a, $i) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,False'
  }
  It 'rdp exige OK (DOWN nao passa)' {
    (& (Get-Module UbuntuGui) {
      $real = ${function:Invoke-Wsl}
      try {
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'OK' } }
        $a = Test-WslRdpListening -LinuxUser 'u' -Service 's' -Port 3390
        ${function:Invoke-Wsl} = { param([string]$AsUser, [string]$Command) return @{ Code = 0; Out = 'DOWN' } }
        $i = Test-WslRdpListening -LinuxUser 'u' -Service 's' -Port 3390
        @($a, $i) -join ','
      } finally { ${function:Invoke-Wsl} = $real }
    }) | Should Be 'True,False'
  }
}

Describe 'Get-WslIpAddress' {
  It 'retorna o primeiro IP (mock do wsl)' {
    (& (Get-Module UbuntuGui) {
      $had = Test-Path function:wsl
      $real = if ($had) { ${function:wsl} } else { $null }
      try {
        ${function:wsl} = { return '10.1.2.3 10.1.2.4 ' }
        Get-WslIpAddress -Distro 'Ubuntu'
      } finally {
        if ($had) { ${function:wsl} = $real } else { Remove-Item function:wsl -ErrorAction SilentlyContinue }
      }
    }) | Should Be '10.1.2.3'
  }
}

Describe 'Test-RebootAnswer' {
  It 'vazio e S/sim = sim (padrao)' {
    (& (Get-Module UbuntuGui) { Test-RebootAnswer -Answer '' }) | Should Be $true
    (& (Get-Module UbuntuGui) { Test-RebootAnswer -Answer 'S' }) | Should Be $true
    (& (Get-Module UbuntuGui) { Test-RebootAnswer -Answer 'sim' }) | Should Be $true
  }
  It 'n/nao = nao' {
    (& (Get-Module UbuntuGui) { Test-RebootAnswer -Answer 'n' }) | Should Be $false
    (& (Get-Module UbuntuGui) { Test-RebootAnswer -Answer 'Nao' }) | Should Be $false
  }
}

Describe 'Test-UnattendedInput' {
  It 'exige usuario e senha' {
    (& (Get-Module UbuntuGui) { (Test-UnattendedInput -LinuxUser 'daniel' -HasPassword $true).Ok }) | Should Be $true
    (& (Get-Module UbuntuGui) { (Test-UnattendedInput -LinuxUser '' -HasPassword $true).Reason }) | Should Be 'missing-credentials'
    (& (Get-Module UbuntuGui) { (Test-UnattendedInput -LinuxUser 'daniel' -HasPassword $false).Reason }) | Should Be 'missing-credentials'
  }
}

Describe 'Test-PasswordConfirmation' {
  It 'iguais e nao-vazias = true (case-sensitive)' {
    (& (Get-Module UbuntuGui) { Test-PasswordConfirmation -First 'abc123' -Second 'abc123' }) | Should Be $true
    (& (Get-Module UbuntuGui) { Test-PasswordConfirmation -First 'Abc' -Second 'abc' }) | Should Be $false
  }
  It 'vazia nunca confirma' {
    (& (Get-Module UbuntuGui) { Test-PasswordConfirmation -First '' -Second '' }) | Should Be $false
    (& (Get-Module UbuntuGui) { Test-PasswordConfirmation -First '' -Second 'x' }) | Should Be $false
  }
}
