#!/bin/bash
# Gera 3 Autounattend.xml (DC01, CA01, WS01) e empacota em ISOs seed.
#
# Cada XML configura: hostname, IP fixo, DNS, idioma en-US, autologon Administrator,
# firewall desabilitado (lab), Defender realtime off, e marca de conclusao em C:\setup-complete.flag.
#
# Pre-requisitos:
#  - genisoimage (Debian/Ubuntu/Kali: apt install genisoimage)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="$SCRIPT_DIR/gerados"
mkdir -p "$OUT"

gen_xml() {
    local hostname="$1"
    local ip="$2"
    local dns="$3"
    local image_name="$4"
    local out_file="$5"

cat > "$out_file" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>2</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>3</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>4</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>5</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
      </RunSynchronous>
      <DiskConfiguration>
        <Disk wcm:action="add">
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>500</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>NTFS</Format><Active>true</Active></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format></ModifyPartition>
          </ModifyPartitions>
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/NAME</Key><Value>${image_name}</Value></MetaData></InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>2</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <ProductKey><WillShowUI>OnError</WillShowUI></ProductKey>
        <AcceptEula>true</AcceptEula>
        <FullName>TCC AD CS</FullName>
        <Organization>IFPB</Organization>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>${hostname}</ComputerName>
      <TimeZone>E. South America Standard Time</TimeZone>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword><Value>Lab@TCC2026</Value><PlainText>true</PlainText></AdministratorPassword>
      </UserAccounts>
      <AutoLogon>
        <Password><Value>Lab@TCC2026</Value><PlainText>true</PlainText></Password>
        <Enabled>true</Enabled>
        <LogonCount>3</LogonCount>
        <Username>Administrator</Username>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Get-NetAdapter | Where-Object Status -eq Up | Rename-NetAdapter -NewName Ethernet0 -PassThru"</CommandLine>
          <Description>Rename NIC</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "New-NetIPAddress -InterfaceAlias Ethernet0 -IPAddress ${ip} -PrefixLength 24 -ErrorAction SilentlyContinue"</CommandLine>
          <Description>Set static IP</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Set-DnsClientServerAddress -InterfaceAlias Ethernet0 -ServerAddresses ${dns}"</CommandLine>
          <Description>Set DNS</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>4</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"</CommandLine>
          <Description>Disable firewall (lab)</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>5</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"</CommandLine>
          <Description>Install OpenSSH Server</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>6</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Set-Service -Name sshd -StartupType Automatic; Start-Service sshd"</CommandLine>
          <Description>Start sshd</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>7</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force"</CommandLine>
          <Description>SSH default shell = PowerShell</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>8</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Set-MpPreference -DisableRealtimeMonitoring \$true -ErrorAction SilentlyContinue"</CommandLine>
          <Description>Disable Defender realtime (lab)</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>9</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "New-Item -Path C:\setup-complete.flag -ItemType File -Force; Get-Date | Out-File C:\setup-complete.flag"</CommandLine>
          <Description>Mark ready</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XMLEOF
}

# Gerar 3 Autounattend
gen_xml "DC01" "10.10.10.10" "127.0.0.1" "Windows Server 2022 SERVERSTANDARD" "$OUT/DC01.xml"
gen_xml "CA01" "10.10.10.11" "10.10.10.10" "Windows Server 2022 SERVERSTANDARD" "$OUT/CA01.xml"
gen_xml "WS01" "10.10.10.20" "10.10.10.10" "Windows 11 Enterprise LTSC 2024 Evaluation" "$OUT/WS01.xml"

echo "Autounattend XMLs gerados em $OUT:"
ls -lh "$OUT"/*.xml

# Empacotar cada XML em uma ISO secundaria (Autounattend.xml na raiz)
for vm in DC01 CA01 WS01; do
    workdir=$(mktemp -d)
    cp "$OUT/$vm.xml" "$workdir/Autounattend.xml"
    iso_out="$REPO_ROOT/vmware/$vm/iso/autounattend-$vm.iso"
    mkdir -p "$(dirname "$iso_out")"
    genisoimage -quiet -J -r -o "$iso_out" "$workdir"
    rm -rf "$workdir"
    echo "ISO: $iso_out ($(du -h "$iso_out" | cut -f1))"
done

echo "Pronto."
