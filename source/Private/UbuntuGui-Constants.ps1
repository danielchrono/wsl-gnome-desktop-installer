# Fonte unica de tunables tecnicos: mude AQUI, nunca espalhado no fluxo.
# Install-WslUbuntuGui mapeia para locais curtas ($RDP_PORT, $MinBuild, ...);
# Private/* leem via $script:UbuntuGuiDefaults (vale no modulo e no .cmd).
$script:UbuntuGuiDefaults = @{
  Distro               = 'Ubuntu'
  GuiPackage           = 'ubuntu-desktop-minimal'
  FallbackResolution   = '1600x900'
  RdpPort              = 3390    # longe da 3389 (erro 0x708 no loopback)
  AppName              = 'Ubuntu-GUI'
  IconUrl              = 'https://commons.wikimedia.org/wiki/Special:FilePath/Ubuntu-logo-no-wordmark-solid-o-2022.svg?width=512'
  MinBuildMirrored     = 22621   # Win11 22H2+: mirrored networking
  CredTimeoutSec       = 60      # timeout por tentativa de set-credentials
  CredRetries          = 2       # tentativas de gravacao no cofre
  AptRetries           = 3       # tentativas de apt install
  RdpSettleSec         = 4       # espera pos-restart do RDP
  WslShutdownWaitSec   = 8       # espera pos wsl --shutdown
  ShellRestartWaitSec  = 12      # espera pos-restart do Shell
  FreshInstallWaitSec  = 15      # espera pos wsl --install
  RebootDelaySec       = 30      # shutdown /r /t
  CertYears            = 10      # validade do cert de publicador
  TlsCertDays          = 825     # validade do cert TLS do RDP
  PublisherSubject     = 'CN=Ubuntu-GUI RDP'
  ShellService         = 'gnome-shell-headless.service'
  ShellBinary          = 'gnome-shell'
  ShellRestartSec      = 3
  RdpService           = 'gnome-remote-desktop'
  GdmService           = 'gdm3'
  GdmAlias             = 'gdm'
  KeyringPath          = '~/.local/share/keyrings/login.keyring'
  TlsCertPath          = '~/.local/share/gnome-remote-desktop/rdp-cert.pem'
  TlsKeyPath           = '~/.local/share/gnome-remote-desktop/rdp-key.pem'
  PamSudoPath          = '/etc/pam.d/sudo'
  IconSizes            = @(16, 32, 48, 128, 256)
}
