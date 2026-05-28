# 01-promover-dc.ps1
# Promove DC01 a primeiro Domain Controller da floresta tcc-adcs.local.
#
# Roda em: DC01 (recem-instalado pelo autounattend)
# Como executar (a partir do host Kali, via netexec winrm):
#   netexec winrm 10.10.10.10 -u Administrator -p 'Lab@TCC2026' -X "$(cat 01-promover-dc.ps1)"
# Ou copiar pra DC01 e executar localmente como Administrator.

$ErrorActionPreference = 'Stop'

Write-Output '[+] Instalando role AD-Domain-Services...'
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

Write-Output '[+] Promovendo DC01 a primeiro DC da floresta tcc-adcs.local...'
$securePwd = ConvertTo-SecureString 'Lab@TCC2026' -AsPlainText -Force

Install-ADDSForest `
    -DomainName tcc-adcs.local `
    -DomainNetbiosName TCCADCS `
    -DomainMode WinThreshold `
    -ForestMode WinThreshold `
    -InstallDns:$true `
    -SafeModeAdministratorPassword $securePwd `
    -NoRebootOnCompletion:$false `
    -Force:$true

# Apos o Install-ADDSForest, o sistema reinicia automaticamente.
# Login pos-reboot: TCCADCS\Administrator / Lab@TCC2026
