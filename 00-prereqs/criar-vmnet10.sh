#!/bin/bash
# Cria a rede host-only vmnet10 (10.10.10.0/24) usada pelo laboratorio.
#
# Topologia:
#   - vmnet10 host-only puro, sem DHCP, sem NAT
#   - host Kali em 10.10.10.1 (gateway logico)
#   - DC01 em 10.10.10.10, CA01 em 10.10.10.11, WS01 em 10.10.10.20
#
# Metodo: edita /etc/vmware/networking e reinicia o servico VMware.
# A CLI vmware-networks do Workstation 25 Linux nao expoe flags --add/--add-ip-subnet;
# a unica via scriptavel e o arquivo de configuracao.
#
# Pre-requisitos:
#   - VMware Workstation Pro instalado
#   - rodar como root (sudo)
#   - nenhuma VM ligada no momento (o restart derruba todas)

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: rodar como root (sudo $0)" >&2
    exit 1
fi

# Permite parametrizar o numero da vnet (para teste, ex: VNET=11 sudo ./criar-vmnet10.sh)
VNET="${VNET:-10}"
SUBNET="${SUBNET:-10.10.10.0}"
NETMASK='255.255.255.0'

NETWORKING_FILE='/etc/vmware/networking'

if [ ! -f "$NETWORKING_FILE" ]; then
    echo "ERRO: $NETWORKING_FILE nao encontrado. VMware Workstation instalado?" >&2
    exit 1
fi

# Verifica se ha VMs ligadas; o restart do servico VMware derruba todas.
if pgrep -f vmware-vmx >/dev/null 2>&1; then
    echo "ERRO: ha VMs em execucao. Pare todas antes de continuar:" >&2
    pgrep -af vmware-vmx >&2
    exit 1
fi

if grep -q "^answer VNET_${VNET}_HOSTONLY_SUBNET" "$NETWORKING_FILE"; then
    echo "[*] VNET_${VNET} ja configurada em $NETWORKING_FILE. Nada a fazer."
    grep "VNET_${VNET}_" "$NETWORKING_FILE"
    exit 0
fi

echo "[+] Backup de $NETWORKING_FILE -> ${NETWORKING_FILE}.bak.$(date +%s)"
cp -a "$NETWORKING_FILE" "${NETWORKING_FILE}.bak.$(date +%s)"

echo "[+] Adicionando vmnet${VNET} (${SUBNET}/24) host-only puro..."
cat >> "$NETWORKING_FILE" <<EOF
answer VNET_${VNET}_HOSTONLY_NETMASK ${NETMASK}
answer VNET_${VNET}_HOSTONLY_SUBNET ${SUBNET}
answer VNET_${VNET}_VIRTUAL_ADAPTER yes
EOF

echo "[+] Recarregando modulos VMware e reiniciando o servico..."
# Em hosts Linux com kernel atualizado, "vmware-networks --stop && --start" pode falhar
# em recarregar os modulos vmnet/vmmon (testado em Kali kernel 6.19.11). O caminho
# confiavel e usar vmware-modconfig, que recompila e instala os modulos.
vmware-modconfig --console --install-all >/dev/null 2>&1
sleep 2
vmware-networks --start >/dev/null 2>&1

echo
echo "[+] Verificacao:"
if ip addr show "vmnet${VNET}" >/dev/null 2>&1; then
    echo "    interface vmnet${VNET} foi criada:"
    ip addr show "vmnet${VNET}" | grep -E 'inet |link/ether'
else
    echo "    ATENCAO: interface vmnet${VNET} nao apareceu. Verifique:"
    echo "      sudo vmware-networks --status"
    exit 1
fi

echo
echo "[+] O host recebe automaticamente o IP .1 desta rede (vmnet${VNET}),"
echo "    usado pelo agente ofensivo (Kali) para falar com as VMs."
echo
echo "Pronto."
