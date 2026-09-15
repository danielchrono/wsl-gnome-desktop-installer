# Monta as linhas do .rdp com login automatico (senha em blob DPAPI, so este usuario le).
function New-RdpFileContent(
  [string]$RdpHost,
  [int]$RdpPort,
  [string]$LinuxUser,
  [string]$PasswordHex,
  [string]$Resolution
) {
  $rdp = @('screen mode id:i:1', 'session bpp:i:32')  # 1 = janela (2 = tela cheia); maximizar continua possivel
  $rdp += 'usbdevicestoredirect:s:*'  # USB do host na sessao (o servidor/GNOME pode recusar algumas classes)
  if ($Resolution -match '^(\d+)x(\d+)$') {
    $rdp += "desktopwidth:i:$($Matches[1])"
    $rdp += "desktopheight:i:$($Matches[2])"
  }
  $rdp += "full address:s:${RdpHost}:$RdpPort"
  $rdp += "username:s:$LinuxUser"
  $rdp += "password 51:b:$PasswordHex"
  $rdp += 'prompt for credentials:i:0'
  $rdp += 'enablecredsspsupport:i:1'
  $rdp += 'authentication level:i:0'  # 0 = nao avisar: cert e autoassinado (loopback/WSL, sem MITM pratico)
  $rdp += 'promptcredentialonce:i:1'
  $rdp += 'negotiate security layer:i:1'
  return $rdp
}
