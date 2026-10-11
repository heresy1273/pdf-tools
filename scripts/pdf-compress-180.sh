#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAMEHELPER="$SCRIPT_DIR/pdf-name.py"

for cmd in gs qpdf gio python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "FEHLER: Benötigtes Programm fehlt: $cmd"
        echo
        echo "Taste drücken zum Schließen."
        read -n 1
        exit 1
    fi
done

if (( $# == 0 )); then
    echo "FEHLER: Keine PDF-Datei übergeben."
    echo
    echo "Taste drücken zum Schließen."
    read -n 1
    exit 1
fi

for input in "$@"; do

    if [[ "$(basename "$input")" == *_CMP_* ]]; then
        echo
        echo "ÜBERSPRUNGEN:"
        echo "$(basename "$input")"
        echo "CMP ist bereits im Dateinamen vorhanden."
        echo "Keine erneute Komprimierung durchgeführt."
        continue
    fi

    if [[ ! -f "$input" ]]; then
        echo "FEHLER: Datei nicht gefunden:"
        echo "$input"
        continue
    fi

    timestamp="$(date +%Y%m%d_%H%M%S)"
    output="$("$NAMEHELPER" "$input" --add CMP --timestamp "$timestamp")"

    while [[ "$output" == "$input" || -e "$output" ]]; do
        sleep 1
        timestamp="$(date +%Y%m%d_%H%M%S)"
        output="$("$NAMEHELPER" "$input" --add CMP --timestamp "$timestamp")"
    done

    workdir="$(mktemp -d)"
    temp_output="${workdir}/compressed.pdf"

    echo
    echo "=========================================="
    echo "PDF KOMPRIMIEREN (180 dpi)"
    echo "=========================================="
    echo "Eingabe : $input"
    echo "Ausgabe : $output"
    echo

    echo "[1/2] PDF komprimieren ..."

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
        -sOutputFile="$temp_output" \
        "$input"
    then
        echo
        echo "FEHLER bei der Komprimierung."
        echo "Original bleibt erhalten."
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[2/2] Ergebnis prüfen ..."

    if [[ ! -s "$temp_output" ]]; then
        echo "FEHLER: Ergebnisdatei ist leer."
        echo "Original bleibt erhalten."
        rm -rf "$workdir"
        continue
    fi

    if ! qpdf --check "$temp_output" >/dev/null 2>&1; then
        echo "FEHLER: Ergebnis-PDF ist nicht valide."
        echo "Original bleibt erhalten."
        rm -rf "$workdir"
        continue
    fi

    if ! mv -- "$temp_output" "$output"; then
        echo "FEHLER: Ergebnis konnte nicht ins Ziel verschoben werden."
        echo "Original bleibt erhalten."
        rm -rf "$workdir"
        continue
    fi

    if gio trash "$input"; then
        echo
        echo "=========================================="
        echo "FERTIG"
        echo "=========================================="
        echo "Neue Datei : $output"
        echo "Original   : Papierkorb"
        echo
        echo "Dateigröße:"
        du -h "$output"
        echo "=========================================="
    else
        echo
        echo "WARNUNG:"
        echo "Komprimierte PDF wurde erstellt,"
        echo "aber das Original blieb erhalten."
        echo
        echo "$output"
    fi

    rm -rf "$workdir"

done

echo
echo "Taste drücken zum Schließen."
read -n 1
