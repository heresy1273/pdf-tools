#!/bin/bash
set -euo pipefail

if (( EUID == 0 )); then
    echo "Bitte als normaler Benutzer starten."
    exit 1
fi

INSTALL_DIR="$HOME/Scripts/pdf-tools"
SERVICE="$HOME/.local/share/kio/servicemenus/ocr-pdf.desktop"

rm -f "$SERVICE"
rm -rf "$INSTALL_DIR"

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 || true
fi

echo "PDF Tools entfernt."
echo "Systempakete bleiben installiert."
