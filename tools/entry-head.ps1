[CmdletBinding()]
param([switch]$Resume)
$SCRIPT_VERSION = "0.1.0"
try { Start-Transcript -Path (Join-Path $env:TEMP 'Ubuntu-GUI-install.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
