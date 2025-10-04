#!/bin/bash

# Script pour automatiser l'utilisation de malicious-pdf avec dashpdf
# Usage : ./generate_pdfs.sh <host> <port>

set -e

# Vérification arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <host> <port>"
    exit 1
fi

HOST=$1
PORT=$2
BURP_URL="http://${HOST}:${PORT}"

# Répertoires
BASE_DIR="$HOME/dashpdf"
MALPDF_DIR="${BASE_DIR}/malicious-pdf"

cd "$BASE_DIR"

echo "[*] Dossier de travail : $BASE_DIR"
echo "[*] URL cible : $BURP_URL"

# Clonage si nécessaire
if [ ! -d "$MALPDF_DIR" ]; then
    echo "[*] Clonage du repo malicious-pdf..."
    git clone https://github.com/tucommenceapousser/malicious-pdf.git "$MALPDF_DIR"
else
    echo "[*] Repo malicious-pdf déjà présent. Pull des dernières mises à jour..."
    cd "$MALPDF_DIR" && git pull && cd "$BASE_DIR"
fi

# Installation requirements
echo "[*] Installation des requirements Python..."
cd "$MALPDF_DIR"
pip3 install -r requirements.txt

# Exécution
echo "[*] Génération des PDF malicieux..."
python3 malicious-pdf.py "$BURP_URL"

# Copie des fichiers générés dans dashpdf
echo "[*] Copie des fichiers PDF générés dans $BASE_DIR..."
cp test*.pdf "$BASE_DIR/"

# Retour dans ~/dashpdf
cd "$BASE_DIR"

echo "[+] Terminé ! Les fichiers sont disponibles dans $BASE_DIR"
