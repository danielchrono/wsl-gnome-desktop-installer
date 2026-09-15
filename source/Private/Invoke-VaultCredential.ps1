# Gestor de cofre (credencial RDP no Secret Service via gnome-keyring/grdctl).
# Todo acesso ao cofre passa por aqui: elimina a duplicacao entre Install
# (etapa 5) e Get-WslUbuntuGuiStatus e nunca engole resultado (sem Out-Null
# cego). I/O com o daemon fica isolado nestas fronteiras; retry e mensagens
# ficam na View. Cobertura Pester no construtor puro.
function New-WslSessionEnv([string]$Uid) {
  return "XDG_RUNTIME_DIR=/run/user/$Uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$Uid/bus"
}

# Pipeline de unlock (sem exit): printf|unlock|tail. O exit com PIPESTATUS vive
# no chamador, p/ compor unlock+sonda na MESMA chamada WSL (daemon efemero:
# unlock e sonda em chamadas separadas podem falar com instancias diferentes).
function Get-WslUnlockPipeline([string]$PasswordQuote, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return "printf '%s' '$PasswordQuote' | $envPrefix gnome-keyring-daemon --unlock 2>&1 | tail -n 3"
}

# Comando da sonda Locked (com 2>&1: o texto do erro e diagnostico, nao lixo).
function Get-WslKeyringProbeCommand([string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return "$envPrefix busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>&1"
}

# Desbloqueia o cofre 'login' com a senha informada. Retorna @{ Code; Out }.
# Code != 0 = senha nao confere ou daemon fora: o chamador falha rapido com
# instrucao (nunca retry cego que queima 2x60s). PIPESTATUS[1] e o exit do
# unlock (sem ele, o tail mascarava tudo com 0).
function Unlock-WslKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  return Invoke-Wsl $LinuxUser "$(Get-WslUnlockPipeline -PasswordQuote $PasswordQuote -Uid $Uid); exit `${PIPESTATUS[1]}"
}

# Parser puro do protocolo unlock+sonda (marcadores UBUNTUGUI_*). Fail-closed:
# sem marcador de codigo (-1) ou sonda vazia, o chamador trata como Error.
function Read-UnlockProbeOutput([string]$Out) {
  $code = -1; $probe = ''
  foreach ($line in ($Out -split "`n")) {
    if ($line -match '^UBUNTUGUI_UNLOCKCODE=(\d+)\s*$') { $code = [int]$Matches[1] }
    elseif ($line -match '^UBUNTUGUI_PROBE=(.*)$') { $probe = $Matches[1].Trim() }
  }
  return @{ UnlockCode = $code; Probe = $probe }
}

# Unlock + sonda na MESMA invocacao WSL. Retorna @{ UnlockCode; State; Probe;
# UnlockText }. O Code do Invoke-Wsl e ignorado de proposito (o echo final
# sempre sai 0): vale o UnlockCode parseado. UnlockText nunca vem vazio
# (vira '(vazio)') p/ as mensagens de falha nao sairem ocas.
function UnlockAndProbe-WslKeyring([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid) {
  $unlockPipe = Get-WslUnlockPipeline -PasswordQuote $PasswordQuote -Uid $Uid
  $probeCmd = Get-WslKeyringProbeCommand -Uid $Uid
  $r = Invoke-Wsl $LinuxUser "$unlockPipe; ucode=`${PIPESTATUS[1]}; probe=`$($probeCmd); echo UBUNTUGUI_UNLOCKCODE=`$ucode; echo UBUNTUGUI_PROBE=`$probe"
  $parsed = Read-UnlockProbeOutput -Out $r.Out
  if ($parsed.UnlockCode -lt 0 -or [string]::IsNullOrWhiteSpace($parsed.Probe)) { $state = 'Error' }
  elseif (Test-UnlockedPropertyOutput -Out $parsed.Probe) { $state = 'Unlocked' }
  elseif ($parsed.Probe -match 'b true') { $state = 'Locked' }
  else { $state = 'Error' }
  $ut = ((($r.Out -split "`n") | Where-Object { $_ -notmatch '^UBUNTUGUI_' }) -join "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($ut)) { $ut = '(vazio)' }
  return @{ UnlockCode = $parsed.UnlockCode; State = $state; Probe = $parsed.Probe; UnlockText = $ut }
}

# Grava usuario+senha do RDP no cofre. 'env' e obrigatorio apos 'timeout'
# (timeout executa o 1o argumento como programa: prefixo VAR=x puro falharia).
function Set-WslRdpCredential([string]$LinuxUser, [string]$PasswordQuote, [string]$Uid, [int]$TimeoutSec) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  return Invoke-Wsl $LinuxUser "timeout $TimeoutSec env $envPrefix grdctl rdp set-credentials '$LinuxUser' '$PasswordQuote' 2>&1 | tail -n 5"
}

# Verifica de verdade no daemon (o cofre existir nao basta: item vazio tambem conta).
function Test-WslRdpCredential([string]$LinuxUser, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  $r = Invoke-Wsl $LinuxUser "$envPrefix grdctl status 2>/dev/null | grep -E 'Username:' | grep -qv '(empty)' && echo YES || echo NO"
  return ($r.Out.Trim() -eq "YES")
}

# Parser puro da sonda (fail-closed: so 'b false' prova destravado).
function Test-UnlockedPropertyOutput([string]$Out) {
  return ($Out -match 'b false')
}

# Estado da sonda do cofre: Locked vs Unlocked vs Error. Fail-closed como
# antes (so 'b false' prova destravado), mas sem confundir 'trancado' com
# 'sonda quebrou': 'b true' = trancado de verdade; qualquer outra saida (bus
# fora, alias ausente) = Error, que pede outro conserto (D-Bus/sessao, nao
# apagar o keyring). 2>&1 de proposito: o texto do erro e o diagnostico.
function Get-WslKeyringProbeState([string]$LinuxUser, [string]$Uid) {
  $r = Invoke-Wsl $LinuxUser (Get-WslKeyringProbeCommand -Uid $Uid)
  $out = if ($r.Out) { $r.Out.Trim() } else { '' }
  if (Test-UnlockedPropertyOutput -Out $out) { return @{ State = 'Unlocked'; Out = $out } }
  if ($out -match 'b true') { return @{ State = 'Locked'; Out = $out } }
  return @{ State = 'Error'; Out = $out }
}

# Sonda sem prompt: colecao 'default' destravada? Le a propriedade Locked via
# busctl (retorna na hora, nunca abre prompt). Qualquer duvida = $false:
# melhor falhar rapido com instrucao do que travar 60s no set-credentials.
function Test-WslKeyringUnlocked([string]$LinuxUser, [string]$Uid) {
  return ((Get-WslKeyringProbeState -LinuxUser $LinuxUser -Uid $Uid).State -eq 'Unlocked')
}

# Teste de controle: unlock com senha GARANTIDAMENTE errada (sem efeito
# colateral: unlock falho nao muda nada). Se sair != 0, exit codes sao
# significativos neste sistema (e unlock-0 com a senha do usuario = senha
# aceita => senha incorreta p/ o cofre existente). Se sair 0, o unlock por
# stdin nao valida nada aqui (e a senha do usuario e inocentada). So chamado
# no caminho de falha Locked.
function Test-WslUnlockExitMeaningful([string]$LinuxUser, [string]$Uid) {
  $probe = UnlockAndProbe-WslKeyring -LinuxUser $LinuxUser -PasswordQuote 'ubuntugui-sonda-falsa-000' -Uid $Uid
  return ($probe.UnlockCode -ne 0)
}

# Detalhe so p/ falha Locked: a colecao LOGIN esta trancada ou o DEFAULT aponta
# p/ outra colecao? Quais arquivos existem, quantos daemons rodam. So leitura,
# so chamado no caminho de falha (custo zero no sucesso). Se o caminho da
# colecao estiver errado, o busctl devolve erro como texto - que tambem e
# evidencia, nunca quebra.
function Get-WslKeyringLockDetail([string]$LinuxUser, [string]$Uid) {
  $envPrefix = New-WslSessionEnv -Uid $Uid
  $login = Invoke-Wsl $LinuxUser "$envPrefix busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked 2>&1"
  $files = Invoke-Wsl $LinuxUser "ls ~/.local/share/keyrings/ 2>/dev/null || echo SEM-DIR"
  $daemons = Invoke-Wsl $LinuxUser "daemons=`$(pgrep -fc 'gnome-keyring-daemon' 2>/dev/null); echo daemons=`$daemons"
  $loginOut = if ($login.Out) { $login.Out.Trim() } else { '(vazio)' }
  $filesOut = if ($files.Out) { $files.Out.Trim() } else { '(vazio)' }
  $daemonOut = if ($daemons.Out) { $daemons.Out.Trim() } else { '(vazio)' }
  return "login Locked=[$loginOut] arquivos=[$filesOut] $daemonOut"
}
