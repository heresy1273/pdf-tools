#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LANGUAGE="${1:-}"
shift || true

case "$LANGUAGE" in
    deu) LABEL="Deutsch" ;;
    eng) LABEL="English" ;;
    tur) LABEL="Türkisch" ;;
    *)
        echo "FEHLER: Unbekannte Sprache: $LANGUAGE"
        read -n 1
        exit 1
        ;;
esac

DESKEW="$SCRIPT_DIR/pdf-deskew-opencv.py"
NAMEHELPER="$SCRIPT_DIR/pdf-name.py"

for cmd in pdftoppm img2pdf ocrmypdf qpdf gio python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "FEHLER: Benötigtes Programm fehlt: $cmd"
        read -n 1
        exit 1
    fi
done

for input in "$@"; do

    if [[ ! -f "$input" ]]; then
        echo "FEHLER: Datei nicht gefunden: $input"
        continue
    fi

    timestamp="$(date +%Y%m%d_%H%M%S)"
    output="$("$NAMEHELPER" "$input" --add OCR DSK --timestamp "$timestamp")"

    # Niemals Eingabe überschreiben oder bestehenden Namen kollidieren lassen.
    while [[ "$output" == "$input" || -e "$output" ]]; do
        sleep 1
        timestamp="$(date +%Y%m%d_%H%M%S)"
        output="$("$NAMEHELPER" "$input" --add OCR DSK --timestamp "$timestamp")"
    done

    workdir="$(mktemp -d)"
    normalized="${workdir}/deskewed.pdf"

    echo
    echo "=========================================="
    echo "OCR $LABEL + OpenCV-Ausrichtung"
    echo "=========================================="
    echo "Eingabe : $input"
    echo "Ausgabe : $output"
    echo

    echo "[1/5] Seiten auf max. 3508 px rasterisieren ..."

    if ! pdftoppm -scale-to 3508 -jpeg "$input" "${workdir}/page"; then
        echo "FEHLER bei pdftoppm."
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[2/5] Schräglage erkennen und korrigieren ..."

    echo
    echo "Rasterbilder validieren ..."

    if ! python3 - "$workdir" <<'PYVALID'
import sys, glob
from PIL import Image

files = sorted(glob.glob(sys.argv[1] + "/page-*.jpg"))
if not files:
    raise SystemExit("Keine Rasterbilder erzeugt.")

for f in files:
    try:
        with Image.open(f) as img:
            img.verify()
        with Image.open(f) as img:
            w, h = img.size
        if w < 100 or h < 100:
            raise SystemExit(f"Ungültige Bildgröße: {f}: {w}x{h}")
        if w > 5000 or h > 5000:
            raise SystemExit(f"Unplausibel große Bildgröße: {f}: {w}x{h}")
    except Exception as e:
        raise SystemExit(f"Rasterbild fehlerhaft: {f}: {e}")
PYVALID
    then
        echo "FEHLER: Rasterisierung lieferte ungültige Bilder."
        rm -rf "$workdir"
        continue
    fi

    if ! python3 "$DESKEW" "$workdir"; then
        echo "FEHLER bei OpenCV-Deskew."
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[3/5] PDF neu aufbauen ..."

    if ! img2pdf --imgsize 300dpi "${workdir}"/fixed-*.jpg -o "$normalized"; then
        echo "FEHLER beim Neuaufbau der PDF."
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[4/5] OCR $LABEL ..."

    if ! ocrmypdf \
        -l "$LANGUAGE" \
        --force-ocr \
        --output-type pdf \
        "$normalized" \
        "$output"
    then
        echo "FEHLER bei OCR."
        rm -f "$output"
        rm -rf "$workdir"
        continue
    fi

    echo
    echo "[5/5] Ergebnis prüfen ..."

    if [[ ! -s "$output" ]] || ! qpdf --check "$output" >/dev/null 2>&1; then
        echo "FEHLER: Ergebnis-PDF ist nicht valide."
        rm -f "$output"
        rm -rf "$workdir"
        continue
    fi

    if gio trash "$input"; then
        echo
        echo "FERTIG"
        echo "Neue Datei : $output"
        echo "Original   : Papierkorb"
    else
        echo
        echo "WARNUNG: Ergebnis ist fertig, Original blieb erhalten."
    fi

    rm -rf "$workdir"
done

echo
echo "Taste drücken zum Schließen."
read -n 1
