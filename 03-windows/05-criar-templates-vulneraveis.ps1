# 05-criar-templates-vulneraveis.ps1
# Cria os templates intencionalmente vulneraveis ESC1_TCC e ESC2_TCC e os publica na CA.
#
# Roda em: CA01 (membro do dominio, com role AD CS instalado)
#
# Como executar:
#   - Localmente (console VMware ou RDP): powershell -ExecutionPolicy Bypass -File 05-...
#   - Remoto via WinRM (do Kali): exige credenciais explicitas no script porque
#     NTLM via WinRM nao delega para o segundo hop (DC01 LDAP). As variaveis
#     $AD_USER e $AD_PASS abaixo sao usadas para autenticar no AD DS.

param(
    [string]$ADUser = 'TCCADCS\Administrator',
    [string]$ADPass = 'Lab@TCC2026'
)

$ErrorActionPreference = 'Stop'

# OIDs
$OID_CLIENT_AUTH = '1.3.6.1.5.5.7.3.2'
$OID_ANY_PURPOSE = '2.5.29.37.0'
# Flags msPKI-Certificate-Name-Flag
$FLAG_ENROLLEE_SUPPLIES_SUBJECT = 0x1
# Schema
# Usa credenciais explicitas para evitar double-hop quando rodado via WinRM remoto.
$ConfigContext = (New-Object DirectoryServices.DirectoryEntry('LDAP://RootDSE', $ADUser, $ADPass)).configurationNamingContext
$TemplatesPath = "LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext"
$TemplatesContainer = New-Object DirectoryServices.DirectoryEntry($TemplatesPath, $ADUser, $ADPass)

# Enroll = ExtendedRight com objectGUID conhecido
$EnrollRightGuid = [Guid]'0e10c968-78fb-11d2-90d4-00c04f79dc55'

function New-VulnTemplate {
    param(
        [string]$Name,
        [string[]]$EKUs,
        [string]$DUEnrollersSid
    )

    # Se ja existe, remove para garantir estado limpo (lab apenas)
    try {
        $check = New-Object DirectoryServices.DirectoryEntry("LDAP://CN=$Name,$($TemplatesContainer.distinguishedName)", $ADUser, $ADPass)
        if ($check.Name) {
            Write-Output "[*] $Name existe, removendo para recriar..."
            $TemplatesContainer.Delete('pKICertificateTemplate', "CN=$Name")
        }
    } catch { }

    Write-Output "[+] Criando template $Name"
    $tpl = $TemplatesContainer.Create('pKICertificateTemplate', "CN=$Name")
    $tpl.Put('displayName', $Name)
    $tpl.Put('flags', [int]66176)                      # template visivel para autoenrollment
    $tpl.Put('revision', [int]100)
    $tpl.Put('pKIDefaultKeySpec', [int]1)              # AT_KEYEXCHANGE
    $tpl.Put('pKIKeyUsage', [byte[]](0xA0, 0x00))      # digitalSignature + keyEncipherment
    $tpl.Put('pKIMaxIssuingDepth', [int]0)
    # 1 ano de validade (FILETIME negativo, little-endian 8 bytes)
    $tpl.Put('pKIExpirationPeriod', [byte[]](0x00,0x80,0xC4,0xCC,0x32,0xE1,0xFE,0xFF))
    # 6 semanas de overlap
    $tpl.Put('pKIOverlapPeriod',    [byte[]](0x00,0x80,0xA6,0x0A,0xFF,0xDE,0xFF,0xFF))
    # EKUs (atributos multi-valued, mas templates ESC1/ESC2 usam apenas um OID cada)
    foreach ($oid in $EKUs) {
        $tpl.Properties['pKIExtendedKeyUsage'].Add($oid) | Out-Null
        $tpl.Properties['msPKI-Certificate-Application-Policy'].Add($oid) | Out-Null
    }
    # ENROLLEE_SUPPLIES_SUBJECT (premissa de ESC1 e tambem usada em ESC2)
    $tpl.Put('msPKI-Certificate-Name-Flag', [int]$FLAG_ENROLLEE_SUPPLIES_SUBJECT)
    # Sem aprovacao do gerente, sem assinatura
    $tpl.Put('msPKI-Enrollment-Flag', [int]0)
    $tpl.Put('msPKI-RA-Signature', [int]0)
    $tpl.Put('msPKI-Minimal-Key-Size', [int]2048)
    $tpl.Put('msPKI-Template-Schema-Version', [int]2)
    $tpl.Put('msPKI-Template-Minor-Revision', [int]1)
    $tpl.Put('msPKI-Private-Key-Flag', [int]0)
    # OID unico (obrigatorio: a CA recusa templates sem msPKI-Cert-Template-OID
    # com 0x80070490 ERROR_NOT_FOUND -> certipy req recebe UNSUPPORTED_CERT_TYPE)
    $parts = 1..5 | ForEach-Object { Get-Random -Minimum 1000000 -Maximum 99999999 }
    $oidTpl = "1.3.6.1.4.1.311.21.8." + ($parts -join '.') + ".1.1"
    $tpl.Put('msPKI-Cert-Template-OID', $oidTpl)
    $tpl.SetInfo()

    # ACL: Enroll para DU-Enrollers
    Write-Output "    -> concedendo Enroll para DU-Enrollers"
    $tpl.psbase.ObjectSecurity | Out-Null  # forca load
    $sid = New-Object System.Security.Principal.SecurityIdentifier($DUEnrollersSid)
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid,
        [System.DirectoryServices.ActiveDirectoryRights]'ExtendedRight',
        [System.Security.AccessControl.AccessControlType]::Allow,
        $EnrollRightGuid
    )
    $tpl.psbase.ObjectSecurity.AddAccessRule($ace)
    $tpl.psbase.CommitChanges()
}

# Buscar SID do grupo DU-Enrollers via ADSI (sem dependencia do modulo AD)
$rootDse = New-Object DirectoryServices.DirectoryEntry('LDAP://RootDSE', $ADUser, $ADPass)
$domainNC = $rootDse.defaultNamingContext
$searchRoot = New-Object DirectoryServices.DirectoryEntry("LDAP://$domainNC", $ADUser, $ADPass)
$searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
$searcher.Filter = '(sAMAccountName=DU-Enrollers)'
$searcher.PropertiesToLoad.AddRange(@('objectSid','distinguishedName'))
$res = $searcher.FindOne()
if (-not $res) { throw 'Grupo DU-Enrollers nao encontrado' }
$sidBytes = $res.Properties['objectsid'][0]
$enrollersSid = (New-Object System.Security.Principal.SecurityIdentifier($sidBytes,0)).Value
Write-Output "[*] DU-Enrollers SID: $enrollersSid"

# ESC1: EKU Client Authentication (legitimo, mas combinado com ENROLLEE_SUPPLIES_SUBJECT vira ESC1)
New-VulnTemplate -Name 'ESC1_TCC' -EKUs @($OID_CLIENT_AUTH) -DUEnrollersSid $enrollersSid

# ESC2: EKU Any Purpose (cobre tudo, inclusive Client Auth implicito)
New-VulnTemplate -Name 'ESC2_TCC' -EKUs @($OID_ANY_PURPOSE) -DUEnrollersSid $enrollersSid

Write-Output "[+] Templates criados no AD. Aguardando 5s para replicacao..."
Start-Sleep -Seconds 5

# Publica os templates na CA. Em vez de Add-CATemplate (que faz RPC local no
# servico CertSvc e falha por nao-autenticacao quando rodado via WinRM),
# usa modificacao LDAP direta do objeto pKIEnrollmentService. Funciona
# em qualquer membro do dominio que tenha credenciais validas.
Write-Output "[+] Publicando ESC1_TCC e ESC2_TCC na CA tcc-adcs-Root-CA..."
$caDN = "CN=tcc-adcs-Root-CA,CN=Enrollment Services,CN=Public Key Services,CN=Services,$ConfigContext"
$caEntry = New-Object DirectoryServices.DirectoryEntry("LDAP://$caDN", $ADUser, $ADPass)
$caEntry.RefreshCache(@('certificateTemplates'))
$existingProp = $caEntry.Properties['certificateTemplates']
$existing = @()
if ($existingProp.Count -gt 0) { $existing = @($existingProp) }
foreach ($t in @('ESC1_TCC', 'ESC2_TCC')) {
    if ($existing -notcontains $t) {
        $caEntry.Properties['certificateTemplates'].Add($t) | Out-Null
        Write-Output "    + $t adicionado a certificateTemplates"
    } else {
        Write-Output "    * $t ja publicado"
    }
}
$caEntry.CommitChanges()

# Reinicia CertSvc local para a CA reler a lista de templates publicados
Write-Output "[+] Reiniciando CertSvc..."
Restart-Service -Name CertSvc -Force

Write-Output ""
Write-Output "[+] Templates vulneraveis publicados. Validar do host Kali com:"
Write-Output "    certipy find -u cassio.aluno@tcc-adcs.local -p 'Aluno@2026' -dc-ip 10.10.10.10 -vulnerable -stdout"
