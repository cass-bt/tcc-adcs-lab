# 06-emitir-cert-dc.ps1
# Emite o certificado de Domain Controller no DC01 (LocalMachine\My).
#
# DEVE rodar DEPOIS de 04-instalar-ca.ps1 e 05-criar-templates-vulneraveis.ps1,
# porque depende da CA estar instalada e dos templates de DC publicados. A
# tentativa de autoenrollment feita no passo 02 nao emite nada, pois naquele
# momento a CA ainda nao existe.
#
# Por que este certificado e necessario:
#   - PKINIT: o KDC precisa de cert proprio para responder AS-REQ via PKINIT.
#     Sem ele: KDC_ERR_PADATA_TYPE_NOSUPP.
#   - LDAPS: o mesmo cert sobe o LDAP sobre TLS na porta 636. Sem ele, o
#     handshake e resetado e o certipy (que usa LDAPS por padrao) falha com
#     'socket ssl wrapping error: [Errno 104] Connection reset by peer'.
#
# O autoenrollment via 'certutil -pulse' nao basta quando a GPO de
# auto-enrollment nao esta ativa: o comando retorna sucesso mas nao emite
# certificado. Por isso este script solicita o certificado explicitamente com
# Get-Certificate. O script e idempotente.

$ErrorActionPreference = 'Stop'

$existing = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
if ($existing -and $existing.Count -gt 0) {
    Write-Output "[+] DC ja possui $($existing.Count) certificado(s) em LocalMachine\My. Nada a fazer."
    $existing | ForEach-Object { Write-Output "    $($_.Subject)" }
} else {
    # KerberosAuthentication e o template ideal: traz Server Authentication (sobe
    # o LDAPS) E KDC Authentication (necessario para o KDC responder PKINIT). O
    # DomainControllerAuthentication sozinho sobe o LDAPS mas NAO tem KDC
    # Authentication, entao o PKINIT falha com KDC_ERR_PADATA_TYPE_NOSUPP.
    Write-Output '[+] Emitindo certificado de DC (template KerberosAuthentication)...'
    try {
        $r = Get-Certificate -Template KerberosAuthentication -CertStoreLocation Cert:\LocalMachine\My
        Write-Output "    Status: $($r.Status)"
        if ($r.Certificate) { Write-Output "    Thumbprint: $($r.Certificate.Thumbprint)" }
    } catch {
        Write-Output "    Falhou com KerberosAuthentication: $($_.Exception.Message)"
        Write-Output '[+] Fallback: tentando template DomainController...'
        $r = Get-Certificate -Template DomainController -CertStoreLocation Cert:\LocalMachine\My
        Write-Output "    Status: $($r.Status)"
    }
}

$dcCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dcCert) {
    Write-Output "[+] Cert do DC presente: $($dcCert.Subject)"
    Write-Output '    LDAPS (636) e PKINIT agora operacionais.'
} else {
    Write-Output '    AVISO: LocalMachine\My continua vazio. Verifique se a CA esta instalada'
    Write-Output '           e se os templates de DC estao publicados.'
}
