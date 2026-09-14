# Certificado de publicador p/ assinar o .rdp (some o aviso "fornecedor desconhecido").
# Idempotente: reaproveita se ja existir no CurrentUser\My.
function New-PublisherCertificate([string]$Subject = $script:UbuntuGuiDefaults.PublisherSubject) {
  $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Subject } | Select-Object -First 1
  if ($cert) { return $cert }
  $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
    -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears($script:UbuntuGuiDefaults.CertYears)
  $store = New-Object Security.Cryptography.X509Certificates.X509Store("TrustedPublishers", "CurrentUser")
  $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
  Ok "Publicador confiavel criado"
  return $cert
}
