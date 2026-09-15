@{
  RootModule        = 'UbuntuGui.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = '975c5990-d708-43a2-8446-c2311f7a2b8d'
  Author            = 'danielchrono'
  Description       = 'Instala o Ubuntu no WSL2 com desktop GNOME completo via RDP.'
  PowerShellVersion = '5.1'
  FunctionsToExport = @('Install-WslUbuntuGui', 'Get-WslUbuntuGuiStatus')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  PrivateData       = @{
    PSData = @{
      Tags       = @('WSL', 'Ubuntu', 'GNOME', 'RDP')
      LicenseUri = 'https://github.com/danielchrono/wsl-gnome-desktop-installer/blob/main/LICENSE'
      ProjectUri = 'https://github.com/danielchrono/wsl-gnome-desktop-installer'
    }
  }
}
