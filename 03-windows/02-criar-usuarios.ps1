# 02-criar-usuarios.ps1
# Cria o usuario cassio.aluno e o grupo DU-Enrollers no AD DS, e configura
# o KDC do dominio para aceitar PKINIT por mapeamento implicito (UPN no SAN),
# que e o caminho usado pelos ataques ESC1 e ESC2.
#
# Roda em: DC01 (apos promocao a Domain Controller)
# Como executar (via netexec winrm com -EncodedCommand em base64; ver README):
#   netexec winrm 10.10.10.10 -u Administrator -p 'Lab@TCC2026' -X "powershell -EncodedCommand <BASE64>"

$ErrorActionPreference = 'Stop'

Import-Module ActiveDirectory

$domain = 'tcc-adcs.local'
$userName = 'cassio.aluno'
$userPassword = 'Aluno@2026'
$groupName = 'DU-Enrollers'

# Cria o grupo DU-Enrollers (Global, Security) se ainda nao existir
if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
    Write-Output "[+] Criando grupo $groupName..."
    New-ADGroup -Name $groupName `
                -SamAccountName $groupName `
                -GroupCategory Security `
                -GroupScope Global `
                -Description 'Usuarios autorizados a fazer enrollment em templates AD CS (lab)'
} else {
    Write-Output "[*] Grupo $groupName ja existe."
}

# Cria o usuario cassio.aluno se ainda nao existir
if (-not (Get-ADUser -Filter "SamAccountName -eq '$userName'" -ErrorAction SilentlyContinue)) {
    Write-Output "[+] Criando usuario $userName..."
    $securePwd = ConvertTo-SecureString $userPassword -AsPlainText -Force
    New-ADUser -Name $userName `
               -SamAccountName $userName `
               -UserPrincipalName "$userName@$domain" `
               -GivenName 'Cassio' `
               -Surname 'Aluno' `
               -DisplayName 'Cassio Aluno (low-priv)' `
               -AccountPassword $securePwd `
               -Enabled $true `
               -PasswordNeverExpires $true `
               -ChangePasswordAtLogon $false
} else {
    Write-Output "[*] Usuario $userName ja existe."
}

# Adiciona cassio.aluno ao grupo DU-Enrollers
Write-Output "[+] Adicionando $userName ao grupo $groupName..."
Add-ADGroupMember -Identity $groupName -Members $userName

Write-Output ''
Write-Output 'Estado final:'
Get-ADGroupMember -Identity $groupName | Format-Table Name, SamAccountName

# ===========================================================================
# Configuracao do KDC para PKINIT por mapeamento implicito (UPN no SAN)
# ===========================================================================
# Sem essas duas chaves, o Windows Server 2022 com patches recentes
# (KB5014754, default = Full Enforcement) rejeita certificados cujo unico
# vinculo a uma conta seja o UPN no Subject Alternative Name. ESC1 e ESC2
# exploram justamente esse caminho, entao precisamos colocar o KDC em modo
# Compatibility (aceita UPN implicito).
#
# Em ambiente real, manter o default (Full Enforcement) e a mitigacao
# recomendada pela Microsoft. Estamos REDUZINDO a seguranca para reproduzir
# o ataque em laboratorio.

Write-Output ''
Write-Output '[+] Configurando KDC para aceitar PKINIT legacy (modo lab)...'

# StrongCertificateBindingEnforcement = 0 (Disabled, comportamento pre-2022)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc' `
    -Name 'StrongCertificateBindingEnforcement' -Value 0 -Type DWORD -Force

# CertificateMappingMethods = 0x1F (todos os 5 metodos: Subject/Issuer, Issuer,
# UPN, S4U2Self, S4U2Self explicit). 0x04 (UPN) e o que permite ESC1/ESC2.
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters' `
    -Name 'CertificateMappingMethods' -Value 0x1F -Type DWORD -Force

Write-Output '    StrongCertificateBindingEnforcement = 0'
Write-Output '    CertificateMappingMethods           = 0x1F'

Restart-Service -Name kdc -Force
Write-Output '    KDC reiniciado.'

# ===========================================================================
# Habilita LDAP anonymous bind nos containers de PKI (necessario p/ CRL/AIA)
# ===========================================================================
# O CryptoAPI do KDC acessa a CRL via "ldap:///" (sem credenciais) durante a
# validacao do certificado apresentado em PKINIT. Win Server 2022 por default
# rejeita esse bind anonimo e o KDC sinaliza CRYPT_E_REVOCATION_OFFLINE,
# fazendo PKINIT falhar com KDC_ERROR_CLIENT_NOT_TRUSTED.
# O 7o caractere de dSHeuristics = '2' permite anonymous bind/query.

Write-Output ''
Write-Output '[+] Habilitando LDAP anonymous bind (dSHeuristics)...'
$configNC = (Get-ADRootDSE).configurationNamingContext
$dsPath = "CN=Directory Service,CN=Windows NT,CN=Services,$configNC"
$current = (Get-ADObject $dsPath -Properties dSHeuristics).dSHeuristics
if ([string]::IsNullOrEmpty($current)) {
    $new = '0000002'
} elseif ($current.Length -lt 7) {
    $new = $current.PadRight(7, '0').Substring(0, 6) + '2'
} else {
    $new = $current.Substring(0, 6) + '2' + $current.Substring(7)
}
Set-ADObject $dsPath -Replace @{dSHeuristics = $new}
Write-Output "    dSHeuristics = $new"

# ===========================================================================
# Garante que o DC tenha certificado de servidor para responder PKINIT
# ===========================================================================
# PKINIT exige que o KDC tenha um certificado proprio (com EKU Server Auth ou
# Kerberos Authentication) instalado no LocalMachine\My. Sem isso, o KDC
# responde KDC_ERR_PADATA_TYPE_NOSUPP em qualquer AS-REQ via PKINIT.
# gpupdate + certutil -pulse forca autoenrollment do template Computer (que
# 'Domain Controllers' herdam por default).

Write-Output ''
Write-Output '[+] Forcando autoenrollment do DC (certificado para PKINIT)...'
gpupdate /force | Out-Null
certutil -pulse | Out-Null
Start-Sleep -Seconds 5
$dcCert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$env:COMPUTERNAME*" } | Select-Object -First 1
if ($dcCert) {
    Write-Output "    Cert do DC instalado: $($dcCert.Subject)"
} else {
    Write-Output "    AVISO: nenhum cert encontrado em LocalMachine\\My. PKINIT pode falhar."
}
