#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

NAMEHELPER="$SCRIPT_DIR/pdf-name.py"

for cmd in pdftoppm pdfseparate pdfunite qpdf gio; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "FEHLER: Benötigtes Programm fehlt: $cmd"
        echo
        echo "Taste drücken zum Schließen."
        read -n 1
        exit 1
    fi
done

if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    echo "FEHLER: Python Pillow fehlt."
    echo
    echo "Installieren mit:"
    echo "sudo apt install python3-pil"
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
    output="$("$NAMEHELPER" "$input" --add EPR --timestamp "$timestamp")"

    while [[ "$output" == "$input" || -e "$output" ]]; do
        sleep 1
        timestamp="$(date +%Y%m%d_%H%M%S)"
        output="$("$NAMEHELPER" "$input" --add EPR --timestamp "$timestamp")"
    done

    workdir="$(mktemp -d)"
    renderdir="${workdir}/render"
    splitdir="${workdir}/split"

    mkdir -p "$renderdir" "$splitdir"

    echo
    echo "=========================================="
    echo "LEERE SEITEN ENTFERNEN"
    echo "=========================================="
    echo "Datei   : $input"
    echo "Ausgabe : $output"
    echo
    echo "[1/3] Seiten analysieren ..."
    echo

    if ! pdftoppm \
        -r 60 \
        -gray \
        "$input" \
        "${renderdir}/page" >/dev/null 2>&1
    then
        echo "FEHLER beim Rendern der PDF."
        rm -rf "$workdir"
        continue
    fi

    EMPTY_LIST="$(python3 - "$renderdir" <<'PY'
import sys
import glob
import os
from PIL import Image

workdir = sys.argv[1]

files = sorted(
    glob.glob(os.path.join(workdir, "page-*.pgm")),
    key=lambda p: int(os.path.basename(p).split("-")[-1].split(".")[0])
)

empty_pages = []

for number, filename in enumerate(files, start=1):

    with Image.open(filename) as img:
        img = img.convert("L")

        w, h = img.size

        mx = max(1, int(w * 0.02))
        my = max(1, int(h * 0.02))

        img = img.crop((mx, my, w - mx, h - my))

        hist = img.histogram()
        total = sum(hist)

        dark = sum(hist[:200])
        medium = sum(hist[:225])

        dark_ratio = (dark / total) * 100
        medium_ratio = (medium / total) * 100

        probably_empty = (
            dark_ratio < 0.10
            and medium_ratio < 0.50
        )

        status = "LEER" if probably_empty else "Inhalt"

        print(
            f"{number:>5}   {dark_ratio:>6.3f}%   {status}",
            file=sys.stderr
        )

        if probably_empty:
            empty_pages.append(number)

print(",".join(map(str, empty_pages)))
PY
)"

    if [[ -z "$EMPTY_LIST" ]]; then
        echo
        echo "=========================================="
        echo "Keine leeren Seiten erkannt."
        echo "Original bleibt unverändert."
        echo "=========================================="

        rm -rf "$workdir"
        continue
    fi

    echo
    echo "Leere Seiten erkannt: $EMPTY_LIST"
    echo

    echo "[2/3] PDF in Seiten zerlegen ..."

    if ! pdfseparate \
        "$input" \
        "${splitdir}/page-%d.pdf"
    then
        echo "FEHLER beim Zerlegen der PDF."
        rm -rf "$workdir"
        continue
    fi

    declare -A EMPTY

    IFS=',' read -ra EMPTY_PAGES <<< "$EMPTY_LIST"

    for p in "${EMPTY_PAGES[@]}"; do
        EMPTY["$p"]=1
    done

    KEEP_FILES=()

    shopt -s nullglob
    pages=( "${splitdir}"/page-*.pdf )
    shopt -u nullglob

    mapfile -t pages < <(
        printf '%s\n' "${pages[@]}" | sort -V
    )

    page_number=1

    for page in "${pages[@]}"; do
        if [[ -n "${EMPTY[$page_number]:-}" ]]; then
            echo "  Seite $page_number -> entfernt"
        else
            echo "  Seite $page_number -> behalten"
            KEEP_FILES+=( "$page" )
        fi

        ((page_number++))
    done

    if (( ${#KEEP_FILES[@]} == 0 )); then
        echo
        echo "FEHLER: Alle Seiten wurden als leer erkannt."
        echo "Original bleibt erhalten."
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[3/3] Bereinigte PDF erstellen ..."

    if ! pdfunite \
        "${KEEP_FILES[@]}" \
        "$output"
    then
        echo "FEHLER beim Erstellen der bereinigten PDF."
        rm -f "$output"
        rm -rf "$workdir"
        continue
    fi

    if ! qpdf --check "$output" >/dev/null 2>&1; then
        echo
        echo "FEHLER: Bereinigte PDF ist nicht valide."
        echo "Original bleibt erhalten."
        rm -f "$output"
        rm -rf "$workdir"
        continue
    fi

    if ! gio trash "$input"; then
        echo
        echo "WARNUNG:"
        echo "Bereinigte PDF wurde erstellt,"
        echo "aber Original konnte nicht in den Papierkorb verschoben werden."
        echo
        echo "$output"

        rm -rf "$workdir"
        continue
    fi

    echo
    echo "=========================================="
    echo "FERTIG"
    echo "=========================================="
    echo "Entfernte Seiten : $EMPTY_LIST"
    echo "Neue Datei       : $output"
    echo "Original         : Papierkorb"
    echo "=========================================="

    rm -rf "$workdir"

done

echo
echo "Taste drücken zum Schließen."
read -n 1
