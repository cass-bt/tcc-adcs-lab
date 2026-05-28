# 04-instalar-ca.ps1
# Instala o role AD CS em CA01 como Enterprise Root Certification Authority.
#
# Roda em: CA01 (apos ingresso no dominio tcc-adcs.local)
# Como executar:
#   netexec winrm 10.10.10.11 -u TCCADCS\\Administrator -p 'Lab@TCC2026' -X "$(cat 04-instalar-ca.ps1)"
#
# Parametros: chave RSA 2048, hash SHA-256, validade 5 anos.
# Sem Web Enrollment e sem NDES (escopo do lab nao inclui).

$ErrorActionPreference = 'Stop'

Write-Output '[+] Instalando role ADCS-Cert-Authority...'
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools | Out-Null

Write-Output '[+] Configurando Enterprise Root CA tcc-adcs-Root-CA...'
$securePwd = ConvertTo-SecureString 'Lab@TCC2026' -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential('TCCADCS\Administrator', $securePwd)

Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCA `
    -CACommonName 'tcc-adcs-Root-CA' `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 5 `
    -Credential $credential `
    -Force:$true

Write-Output '[+] Reiniciando o servico de Certificate Services...'
Restart-Service -Name CertSvc

Write-Output ''
Write-Output 'CA pronta. Templates padrao publicados em CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration.'
Write-Output 'Proximo passo: rodar 05-criar-templates-vulneraveis.ps1.'
