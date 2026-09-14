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
