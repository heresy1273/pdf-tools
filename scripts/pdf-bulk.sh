#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:-}"
shift || true

NAMEHELPER="$SCRIPT_DIR/pdf-name.py"
DESKEW="$SCRIPT_DIR/pdf-deskew-opencv.py"

for cmd in pdfseparate qpdf gio python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "FEHLER: $cmd fehlt."
        read -n 1
        exit 1
    }
done

if [[ "$MODE" == "ocr-de-split" ]]; then
    for cmd in pdftoppm img2pdf ocrmypdf; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "FEHLER: $cmd fehlt."
            read -n 1
            exit 1
        }
    done
fi

split_pdf() {
    local source="$1"
    local original="$2"
    local workdir="$3"
    local timestamp="$4"
    shift 4

    local tags=( "$@" )
    local splitdir="${workdir}/split"

    mkdir -p "$splitdir"

    if ! pdfseparate "$source" "${splitdir}/page-%d.pdf"; then
        echo "FEHLER beim Vereinzeln."
        return 1
    fi

    shopt -s nullglob
    local pages=( "${splitdir}"/page-*.pdf )
    shopt -u nullglob

    if (( ${#pages[@]} == 0 )); then
        echo "FEHLER: Keine Seiten erzeugt."
        return 1
    fi

    mapfile -t pages < <(printf '%s\n' "${pages[@]}" | sort -V)

    local destinations=()
    local i=1
    local destination

    for page in "${pages[@]}"; do

        if (( ${#tags[@]} > 0 )); then
            destination="$(
                "$NAMEHELPER" "$original" \
                    --add "${tags[@]}" \
                    --split \
                    --index "$i" \
                    --timestamp "$timestamp"
            )"
        else
            destination="$(
                "$NAMEHELPER" "$original" \
                    --split \
                    --index "$i" \
                    --timestamp "$timestamp"
            )"
        fi

        if [[ -e "$destination" ]]; then
            echo "FEHLER: Zieldatei existiert bereits:"
            echo "$destination"
            return 1
        fi

        destinations+=( "$destination" )
        ((i++))
    done

    i=0

    for page in "${pages[@]}"; do
        destination="${destinations[$i]}"

        if ! mv -- "$page" "$destination"; then
            echo "FEHLER beim Erstellen von:"
            echo "$destination"
            return 1
        fi

        printf "  [%03d] %s\n" "$((i + 1))" "$(basename "$destination")"
        ((i++))
    done

    echo
    echo "$i Einzelseiten erstellt."

    if ! gio trash "$original"; then
        echo "WARNUNG: Original konnte nicht in den Papierkorb verschoben werden."
        return 2
    fi

    echo "Original in den Papierkorb verschoben."
    return 0
}

for input in "$@"; do

    [[ -f "$input" ]] || {
        echo "FEHLER: Datei nicht gefunden: $input"
        continue
    }

    timestamp="$(date +%Y%m%d_%H%M%S)"
    WORKDIR="$(mktemp -d)"

    echo
    echo "=========================================="

    case "$MODE" in

        split)
            echo "PDF VEREINZELN"
            echo "=========================================="
            echo "Eingabe: $input"
            echo

            split_pdf \
                "$input" \
                "$input" \
                "$WORKDIR" \
                "$timestamp"

            status=$?
            ;;

        ocr-de-split)
            echo "OCR DEUTSCH + AUSRICHTEN + VEREINZELN"
            echo "=========================================="
            echo "Eingabe: $input"

            normalized="${WORKDIR}/normalized.pdf"
            ocrpdf="${WORKDIR}/ocr.pdf"

            echo
            echo "[1/5] Seiten auf max. 3508 px rasterisieren ..."

            if ! pdftoppm -scale-to 3508 -jpeg "$input" "${WORKDIR}/page"; then
                rm -rf "$WORKDIR"
                continue
            fi

            echo
            echo "[2/5] OpenCV-Deskew ..."

            echo
            echo "Rasterbilder validieren ..."

            if ! python3 - "$WORKDIR" <<'PYVALID'
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
                rm -rf "$WORKDIR"
                continue
            fi

            if ! python3 "$DESKEW" "$WORKDIR"; then
                rm -rf "$WORKDIR"
                continue
            fi

            echo
            echo "[3/5] PDF neu aufbauen ..."

            if ! img2pdf --imgsize 300dpi "${WORKDIR}"/fixed-*.jpg -o "$normalized"; then
                rm -rf "$WORKDIR"
                continue
            fi

            echo
            echo "[4/5] OCR Deutsch ..."

            if ! ocrmypdf \
                -l deu \
                --force-ocr \
                --output-type pdf \
                "$normalized" \
                "$ocrpdf"
            then
                rm -rf "$WORKDIR"
                continue
            fi

            if ! qpdf --check "$ocrpdf" >/dev/null 2>&1; then
                echo "FEHLER: OCR-Ergebnis nicht valide."
                rm -rf "$WORKDIR"
                continue
            fi

            echo
            echo "[5/5] Vereinzeln ..."

            split_pdf \
                "$ocrpdf" \
                "$input" \
                "$WORKDIR" \
                "$timestamp" \
                OCR DSK

            status=$?
            ;;

        *)
            echo "FEHLER: Unbekannter Modus: $MODE"
            status=1
            ;;
    esac

    echo
    if [[ "$status" -eq 0 ]]; then
        echo "FERTIG"
    elif [[ "$status" -eq 2 ]]; then
        echo "FERTIG – Original blieb erhalten."
    else
        echo "FEHLER – Original bleibt erhalten."
    fi

    rm -rf "$WORKDIR"
done

echo
echo "Taste drücken zum Schließen."
read -n 1
