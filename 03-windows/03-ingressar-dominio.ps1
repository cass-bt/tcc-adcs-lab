# 03-ingressar-dominio.ps1
# Ingressa CA01 ou WS01 no dominio tcc-adcs.local.
#
# Roda em: CA01 e WS01 (membros futuros do dominio, ainda em workgroup)
# Pre-requisito: DC01 ja promovido e DNS configurado para 10.10.10.10.
#
# Como executar (a partir do host Kali, via netexec winrm):
#   netexec winrm 10.10.10.11 -u Administrator -p 'Lab@TCC2026' -X "$(cat 03-ingressar-dominio.ps1)"
#   netexec winrm 10.10.10.20 -u Administrator -p 'Lab@TCC2026' -X "$(cat 03-ingressar-dominio.ps1)"
#
# A maquina reinicia automaticamente apos o join.

$ErrorActionPreference = 'Stop'

$domain = 'tcc-adcs.local'
$domainAdmin = 'TCCADCS\Administrator'
$domainPwd = 'Lab@TCC2026'

# Garante que o DNS aponta para o DC01
Write-Output '[+] Ajustando DNS para 10.10.10.10 (DC01)...'
$adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses '10.10.10.10'

# Aguarda DNS responder pelo dominio
Write-Output '[+] Aguardando DNS responder por tcc-adcs.local...'
$ok = $false
for ($i=0; $i -lt 30; $i++) {
    try {
        Resolve-DnsName -Name $domain -ErrorAction Stop | Out-Null
        $ok = $true; break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $ok) { throw "DNS de $domain nao respondeu em 60s" }

# Ingressa no dominio (Add-Computer dispara reboot)
$securePwd = ConvertTo-SecureString $domainPwd -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($domainAdmin, $securePwd)

Write-Output "[+] Ingressando $env:COMPUTERNAME no dominio $domain ..."
Add-Computer -DomainName $domain -Credential $credential -Force -Restart
