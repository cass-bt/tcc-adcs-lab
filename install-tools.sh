#!/bin/bash
# Instala as ferramentas Python listadas em requirements.txt via pipx.
# pipx isola cada ferramenta em seu proprio venv e expoe os binarios em ~/.local/bin/.
#
# Pre-requisitos:
#   - pipx instalado (sudo apt install pipx)
#   - ~/.local/bin no PATH (rodar 'pipx ensurepath' uma vez se necessario)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

if ! command -v pipx >/dev/null 2>&1; then
    echo "ERRO: pipx nao encontrado." >&2
    echo "      Instalar com: sudo apt install pipx && pipx ensurepath" >&2
    exit 1
fi

if [ ! -f "$REQ_FILE" ]; then
    echo "ERRO: $REQ_FILE nao encontrado." >&2
    exit 1
fi

echo "[+] Instalando ferramentas listadas em requirements.txt via pipx..."
echo

# Le linha por linha, ignora comentarios e linhas em branco
grep -vE '^\s*(#|$)' "$REQ_FILE" | while IFS= read -r pkg; do
    pkg="${pkg// /}"
    if [ -z "$pkg" ]; then continue; fi
    echo "    pipx install $pkg"
    pipx install "$pkg" || pipx upgrade "${pkg%%[<>=!]*}"
    echo
done

echo "[+] Validando instalacao:"
for tool in certipy netexec; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf "    %-12s %s\n" "$tool" "$(command -v "$tool")"
    else
        printf "    %-12s NAO ENCONTRADO no PATH (rodar 'pipx ensurepath' e reabrir terminal)\n" "$tool"
    fi
done
