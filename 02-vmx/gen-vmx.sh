#!/bin/bash
# Gera os 3 .vmx + VMDKs das maquinas virtuais do laboratorio (DC01, CA01, WS01).
#
# Decisoes de design (ver README.md):
#  - firmware=bios (BIOS legacy): EFI default do Workstation 25 reporta "No Media"
#  - Disco em SATA: SCSI/lsisas1068 esgota slots PCIe em UEFI/Win11
#  - pciBridge4-7 adicionais: UEFI default tem poucos secondary slots
#  - usb.present=FALSE: libera slot 16, nao e usado em lab headless
#
# Pre-requisitos:
#  - vmware-vdiskmanager no PATH (acompanha VMware Workstation Pro)
#  - rede host-only vmnet10 ja criada (rodar 00-prereqs/criar-vmnet10.sh)
#  - ISOs Windows em <repo>/iso/ (ver 00-prereqs/README.md)
#  - Autounattend ISOs em <repo>/vmware/<VM>/iso/ (rodar 01-autounattend/gen-autounattend.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ISO_SRV="$REPO_ROOT/iso/win-server-2022-eval.iso"
ISO_W11="$REPO_ROOT/iso/win11-eval.iso"

for iso in "$ISO_SRV" "$ISO_W11"; do
    if [ ! -f "$iso" ]; then
        echo "ERRO: ISO nao encontrada: $iso" >&2
        echo "      Ver instrucoes em 00-prereqs/README.md" >&2
        exit 1
    fi
done

gen_vmx() {
    local vm="$1"
    local mem_mb="$2"
    local disk_gb="$3"
    local install_iso="$4"
    local guest_os="$5"

    local vmdir="$REPO_ROOT/vmware/$vm"
    local vmx="$vmdir/$vm.vmx"
    local vmdk="$vmdir/disks/$vm.vmdk"
    local autoiso="$vmdir/iso/autounattend-$vm.iso"

    mkdir -p "$vmdir/disks"

    if [ ! -f "$vmdk" ]; then
        echo "[+] Criando VMDK $vmdk (${disk_gb}GB, sparse)..."
        vmware-vdiskmanager -c -s "${disk_gb}GB" -a lsilogic -t 0 "$vmdk" >/dev/null 2>&1
    fi

    cat > "$vmx" <<VMXEOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$vm"
guestOS = "$guest_os"
firmware = "bios"
memSize = "$mem_mb"
numvcpus = "2"
cpuid.coresPerSocket = "2"
nvram = "$vm.nvram"
floppy0.present = "FALSE"
sound.present = "FALSE"
serial0.present = "FALSE"
parallel0.present = "FALSE"
usb.present = "FALSE"
mks.enable3d = "FALSE"
svga.autodetect = "FALSE"
svga.vramSize = "16777216"

# Disco e CDs no controller SATA unico (evita exhaustion PCI)
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$install_iso"
sata0:0.startConnected = "TRUE"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$autoiso"
sata0:1.startConnected = "TRUE"
sata0:2.present = "TRUE"
sata0:2.deviceType = "disk"
sata0:2.fileName = "disks/$vm.vmdk"

ethernet0.present = "TRUE"
ethernet0.virtualDev = "e1000e"
ethernet0.connectionType = "custom"
ethernet0.vnet = "vmnet10"
ethernet0.startConnected = "TRUE"
ethernet0.addressType = "generated"

# PCIe root ports adicionais (UEFI default tem poucos slots secundarios)
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"

bios.bootOrder = "cdrom,hdd"
bios.bootDelay = "2000"
uefi.secureBoot.enabled = "FALSE"

tools.syncTime = "TRUE"
tools.upgrade.policy = "manual"
VMXEOF

    chmod 644 "$vmx"
    echo "[+] VMX criado: $vmx"
}

gen_vmx "DC01" "4096" "60" "$ISO_SRV" "windows2019srv-64"
gen_vmx "CA01" "3072" "60" "$ISO_SRV" "windows2019srv-64"
gen_vmx "WS01" "3072" "50" "$ISO_W11" "windows11-64"

echo
echo "=== Resumo ==="
ls -la "$REPO_ROOT"/vmware/{DC01,CA01,WS01}/*.vmx
du -sh "$REPO_ROOT"/vmware/{DC01,CA01,WS01}/disks/
