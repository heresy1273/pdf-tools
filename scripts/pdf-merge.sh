#!/bin/bash

set -u

for cmd in qpdf gs gio python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "FEHLER: Benötigtes Programm fehlt: $cmd"
        echo
        echo "Taste drücken zum Schließen."
        read -n 1
        exit 1
    fi
done

if (( $# < 2 )); then
    echo "FEHLER:"
    echo "Zum Zusammenführen müssen mindestens zwei PDFs markiert sein."
    echo
    echo "Taste drücken zum Schließen."
    read -n 1
    exit 1
fi

for input in "$@"; do
    if [[ ! -f "$input" ]]; then
        echo "FEHLER: Datei nicht gefunden:"
        echo "$input"
        read -n 1
        exit 1
    fi
done

mapfile -d '' SORTED < <(
    python3 - "$@" <<'PY'
import os
import sys

files = sys.argv[1:]
files.sort(
    key=lambda p: (
        os.stat(p).st_mtime_ns,
        os.path.basename(p).casefold(),
        p.casefold()
    )
)

for p in files:
    sys.stdout.buffer.write(os.fsencode(p) + b"\0")
PY
)

TARGET_DIR="$(dirname "${SORTED[0]}")"

for input in "${SORTED[@]}"; do
    if [[ "$(dirname "$input")" != "$TARGET_DIR" ]]; then
        echo "FEHLER: Alle PDFs müssen aus demselben Verzeichnis stammen."
        read -n 1
        exit 1
    fi
done

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT="${TARGET_DIR}/PDFs_MRG_${TIMESTAMP}.pdf"

WORKDIR="$(mktemp -d)"
MERGED="${WORKDIR}/merged.pdf"
COMPRESSED="${WORKDIR}/compressed.pdf"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo
echo "=========================================="
echo "PDFs ZUSAMMENFÜHREN"
echo "=========================================="
echo
echo "Reihenfolge:"
echo

i=1
for input in "${SORTED[@]}"; do
    printf "  [%03d] %s\n" "$i" "$(basename "$input")"
    ((i++))
done

echo
echo "Anzahl PDFs: ${#SORTED[@]}"
echo

echo "[1/3] PDFs zusammenführen ..."

if ! qpdf --empty --pages "${SORTED[@]}" -- "$MERGED"; then
    echo
    echo "FEHLER beim Zusammenführen."
    echo "Originaldateien bleiben erhalten."
    read -n 1
    exit 1
fi

echo
echo "[2/3] Für Bücher/Anleitungen komprimieren (180 dpi) ..."

if ! gs \
    -sDEVICE=pdfwrite \
    -dCompatibilityLevel=1.6 \
    -dNOPAUSE \
    -dQUIET \
    -dBATCH \
    -dDetectDuplicateImages=true \
    -dCompressFonts=true \
    -dSubsetFonts=true \
    -dDownsampleColorImages=true \
    -dColorImageResolution=180 \
    -dDownsampleGrayImages=true \
    -dGrayImageResolution=180 \
    -dDownsampleMonoImages=true \
    -dMonoImageResolution=300 \
    -sOutputFile="$COMPRESSED" \
    "$MERGED"
then
    echo
    echo "FEHLER bei der Komprimierung."
    echo "Originaldateien bleiben erhalten."
    read -n 1
    exit 1
fi

echo
echo "[3/3] Ergebnis prüfen ..."

if [[ ! -s "$COMPRESSED" ]]; then
    echo "FEHLER: Ergebnisdatei ist leer."
    read -n 1
    exit 1
fi

if ! qpdf --check "$COMPRESSED" >/dev/null 2>&1; then
    echo "FEHLER: Ergebnis-PDF ist nicht valide."
    echo "Originaldateien bleiben erhalten."
    read -n 1
    exit 1
fi

if ! mv -- "$COMPRESSED" "$OUTPUT"; then
    echo "FEHLER: Ergebnis konnte nicht ins Ziel verschoben werden."
    read -n 1
    exit 1
fi

TRASH_ERRORS=0

for input in "${SORTED[@]}"; do
    if ! gio trash "$input"; then
        echo "WARNUNG: Konnte nicht in Papierkorb verschieben:"
        echo "$input"
        TRASH_ERRORS=$((TRASH_ERRORS + 1))
    fi
done

echo
echo "=========================================="
echo "FERTIG"
echo "=========================================="
echo "Neue Datei : $OUTPUT"

if (( TRASH_ERRORS == 0 )); then
    echo "Originale   : Papierkorb"
else
    echo "Originale   : $TRASH_ERRORS Datei(en) blieben erhalten"
fi

echo
echo "Dateigröße:"
du -h "$OUTPUT"

echo "=========================================="
echo
echo "Taste drücken zum Schließen."
read -n 1
