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
}

Describe 'New-LauncherContent' {
  $c = & (Get-Module UbuntuGui) { New-LauncherContent -AppName 'Ubuntu-GUI' -Distro 'Ubuntu' -LinuxUser 'daniel' `
    -RdpPort 3390 -Thumbprint 'ABC123' -DiscoveryBlock 'rem X' -RewriteBlock 'rem Y THUMBPRINT_VAL' }
  It 'troca todos os placeholders' {
    $c | Should Not Match 'DISTRO_VAL|RDP_PORT_VAL|THUMBPRINT_VAL|IPDISCOVERY_VAL|RDPREWRITE_VAL|LINUXUSER_VAL|SHELLSVC_VAL|RDPSVC_VAL'
  }
  It 'embute thumbprint e usuario' {
    $c | Should Match 'ABC123'
    $c | Should Match 'daniel'
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

Describe 'New-WslSessionEnv' {
  It 'monta XDG e bus da sessao' {
    (& (Get-Module UbuntuGui) { New-WslSessionEnv -Uid '1000' }) | Should Be 'XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus'
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
