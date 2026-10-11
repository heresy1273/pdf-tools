#!/bin/bash

set -u

MODE="${1:-}"
shift || true

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAMEHELPER="$SCRIPT_DIR/pdf-name.py"

case "$MODE" in
    odd-left)
        TAG="ODL"
        ODD_ROT="-90"
        EVEN_ROT="+90"
        LABEL="Ungerade links / Gerade rechts"
        ;;
    odd-right)
        TAG="ODR"
        ODD_ROT="+90"
        EVEN_ROT="-90"
        LABEL="Ungerade rechts / Gerade links"
        ;;
    *)
        echo "FEHLER: Unbekannter Modus: $MODE"
        echo
        echo "Taste drücken zum Schließen."
        read -n 1
        exit 1
        ;;
esac

for cmd in qpdf gio python3; do
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

    if [[ ! -f "$input" ]]; then
        echo "FEHLER: Datei nicht gefunden:"
        echo "$input"
        continue
    fi

    timestamp="$(date +%Y%m%d_%H%M%S)"
    output="$("$NAMEHELPER" "$input" --add "$TAG" --timestamp "$timestamp")"

    while [[ "$output" == "$input" || -e "$output" ]]; do
        sleep 1
        timestamp="$(date +%Y%m%d_%H%M%S)"
        output="$("$NAMEHELPER" "$input" --add "$TAG" --timestamp "$timestamp")"
    done

    pages="$(qpdf --show-npages "$input" 2>/dev/null)"

    if [[ ! "$pages" =~ ^[0-9]+$ ]] || (( pages < 1 )); then
        echo "FEHLER: Seitenzahl konnte nicht ermittelt werden:"
        echo "$input"
        continue
    fi

    echo
    echo "=========================================="
    echo "PDF SEITEN WECHSELSEITIG DREHEN"
    echo "=========================================="
    echo "Datei    : $input"
    echo "Modus    : $LABEL"
    echo "Seiten   : $pages"
    echo "Ausgabe  : $output"
    echo

    args=()

    for (( page=1; page<=pages; page++ )); do
        if (( page % 2 == 1 )); then
            args+=( "--rotate=${ODD_ROT}:${page}" )
        else
            args+=( "--rotate=${EVEN_ROT}:${page}" )
        fi
    done

    echo "[1/2] Seiten drehen ..."

    if ! qpdf \
        "$input" \
        "${args[@]}" \
        "$output"
    then
        echo
        echo "FEHLER beim Drehen."
        rm -f "$output"
        echo "Original bleibt erhalten."
        continue
    fi

    echo
    echo "[2/2] Ergebnis prüfen ..."

    if [[ ! -s "$output" ]] || ! qpdf --check "$output" >/dev/null 2>&1; then
        echo "FEHLER: Ergebnis-PDF ist nicht valide."
        rm -f "$output"
        echo "Original bleibt erhalten."
        continue
    fi

    if gio trash "$input"; then
        echo
        echo "=========================================="
        echo "FERTIG"
        echo "=========================================="
        echo "Neue Datei : $output"
        echo "Original   : Papierkorb"
    else
        echo
        echo "WARNUNG: PDF wurde erfolgreich erstellt,"
        echo "aber das Original blieb erhalten."
    fi

done

echo
echo "Taste drücken zum Schließen."
read -n 1
