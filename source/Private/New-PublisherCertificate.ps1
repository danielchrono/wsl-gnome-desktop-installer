# Certificado de publicador p/ assinar o .rdp (some o aviso "fornecedor desconhecido").
# Idempotente: reaproveita se ja existir no CurrentUser\My.
function New-PublisherCertificate([string]$Subject = $script:UbuntuGuiDefaults.PublisherSubject) {
  $all = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Subject })
  # So reaproveita com chave privada (cert sem chave nao assina: rdpsign 0x8009200B):
  # limpa as sobras do caminho antigo.
  $all | Where-Object { -not $_.HasPrivateKey } | ForEach-Object { try { $_ | Remove-Item -ErrorAction Stop } catch {} }
  $cert = @($all | Where-Object { $_.HasPrivateKey }) | Select-Object -First 1
  if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
      -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears($script:UbuntuGuiDefaults.CertYears)
  }
  # Store real no singular (o plural abre um custom que o mstsc ignora).
  # Vale tambem no reuso: sem essa gravacao o mstsc acusava fornecedor
  # desconhecido mesmo com o .rdp assinado.
  $store = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "CurrentUser")
  $store.Open("ReadWrite")
  try {
    $known = @($store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }).Count -gt 0
    if (-not $known) { $store.Add($cert); Ok "Publicador confiavel criado" }
    else { Ok "Publicador ja confiavel" }
  } finally { $store.Close() }
  return $cert
}
