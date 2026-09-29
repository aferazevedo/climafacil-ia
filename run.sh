#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    cp .env.example .env
    echo
    echo "Arquivo .env criado."
    echo "Configure GEMINI_API_KEY antes de executar."
    exit 1
fi

if grep -q "COLE_SUA_CHAVE_AQUI" .env; then
    echo "Configure sua GEMINI_API_KEY no arquivo .env."
    exit 1
fi

python app.py
