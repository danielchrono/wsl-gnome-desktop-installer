# Gera o helper que grava a credencial RDP no Cofre do Windows (Credential Manager)
# para o mstsc abrir sem o aviso de fornecedor (sem precisar do .rdp assinado).
# Estatico (sem placeholder): recebe RdpPath, Host e Port por argumento.
# Fonte da credencial: sidecar `-Cred.txt` (usuario + blob DPAPI, gravado na
# instalacao) — o `.rdp` assinado NAO serve: o rdpsign deforma a linha longa
# `password 51:b:` (uppercase + zeros + hex impar) e a extracao quebra.
# Fallback: le usuario/blob do proprio .rdp (sanitizado; senha nunca em texto).
# Falha nunca e fatal: o launcher volta ao .rdp quando sai codigo != 0.
function New-CredHelperContent {
  return @'
param([string]$RdpPath, [string]$RdpHost, [int]$RdpPort)
try {
  $u = ''; $h = ''
  $sidecar = $PSCommandPath -replace '\.ps1$', '.txt'
  if (Test-Path $sidecar) {
    $sc = [IO.File]::ReadAllLines($sidecar)
    if ($sc.Count -ge 2) { $u = $sc[0].Trim(); $h = $sc[1] -replace '[^0-9a-fA-F]', '' }
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h)) {
    $lines = [IO.File]::ReadAllLines($RdpPath)
    $u = @($lines | Where-Object { $_ -like 'username:s:*' })[0] -replace '^username:s:', ''
    $h = @($lines | Where-Object { $_ -like 'password 51:b:*' })[0] -replace '^password 51:b:', ''
    $u = "$u".Trim()
    $h = "$h" -replace '[^0-9a-fA-F]', ''
  }
  if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($h) -or ($h.Length % 2 -eq 1)) { exit 1 }
  $raw = New-Object byte[] ($h.Length / 2)
  for ($i = 0; $i -lt $h.Length; $i += 2) { $raw[$i / 2] = [Convert]::ToByte($h.Substring($i, 2), 16) }
  Add-Type -AssemblyName System.Security
  $pass = [Text.Encoding]::Unicode.GetString([Security.Cryptography.ProtectedData]::Unprotect($raw, $null, 'CurrentUser'))
  if ([string]::IsNullOrEmpty($pass)) { exit 1 }
  $cs = 'using System; using System.Runtime.InteropServices; public static class CredMan { [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct CREDENTIAL { public UInt32 Flags; public UInt32 Type; [MarshalAs(UnmanagedType.LPWStr)] public string TargetName; [MarshalAs(UnmanagedType.LPWStr)] public string Comment; public UInt64 LastWritten; public UInt32 CredentialBlobSize; public IntPtr CredentialBlob; public UInt32 Persist; public UInt32 AttributeCount; public IntPtr Attributes; [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias; [MarshalAs(UnmanagedType.LPWStr)] public string UserName; } [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CredWriteW")] public static extern bool Write(ref CREDENTIAL cred, UInt32 flags); public static bool Save(string target, string user, string secret) { byte[] b = System.Text.Encoding.Unicode.GetBytes(secret); IntPtr p = Marshal.AllocCoTaskMem(b.Length); Marshal.Copy(b, 0, p, b.Length); CREDENTIAL c = new CREDENTIAL(); c.Flags = 0; c.Type = 1; c.TargetName = target; c.CredentialBlobSize = (UInt32)b.Length; c.CredentialBlob = p; c.Persist = 3; c.UserName = user; bool ok = Write(ref c, 0); Marshal.FreeCoTaskMem(p); return ok; } }'
  Add-Type -TypeDefinition $cs -Language CSharp
  $ok = $true
  foreach ($t in @("TERMSRV/$RdpHost", "TERMSRV/${RdpHost}:$RdpPort")) { if (-not [CredMan]::Save($t, $u, $pass)) { $ok = $false } }
  if (-not $ok) { exit 1 }
} catch { exit 1 }
exit 0
'@
}
