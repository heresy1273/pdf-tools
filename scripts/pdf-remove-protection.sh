#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

STORE_FILE="$HOME/.config/pdf-remove-protection/passwords.txt"
NAMEHELPER="$SCRIPT_DIR/pdf-name.py"

mkdir -p "$(dirname "$STORE_FILE")"
touch "$STORE_FILE"
chmod 600 "$STORE_FILE"

SUCCESS=()
WARNINGS=()
FAILED=()

for INPUT in "$@"; do

    [[ -f "$INPUT" ]] || {
        FAILED+=( "$(basename "$INPUT") – Datei nicht gefunden" )
        continue
    }

    BASENAME="$(basename "$INPUT" .pdf)"
    timestamp="$(date +%Y%m%d_%H%M%S)"
    OUTPUT="$("$NAMEHELPER" "$INPUT" --add DEC --timestamp "$timestamp")"

    while [[ "$OUTPUT" == "$INPUT" || -e "$OUTPUT" ]]; do
        sleep 1
        timestamp="$(date +%Y%m%d_%H%M%S)"
        OUTPUT="$("$NAMEHELPER" "$INPUT" --add DEC --timestamp "$timestamp")"
    done

    ERROR_LOG="$(mktemp)"
    FOUND=0

    try_password() {
        local pw="$1"
        rm -f "$OUTPUT"
        qpdf \
            --password="$pw" \
            --decrypt \
            "$INPUT" \
            "$OUTPUT" \
            2>"$ERROR_LOG"
    }

    # Gespeicherte Passwörter testen
    if [[ -s "$STORE_FILE" ]]; then
        while IFS='|' read -r saved_name pass; do
            [[ -z "$pass" ]] && continue

            if try_password "$pass"; then
                FOUND=1
                break
            fi
        done < "$STORE_FILE"
    fi

    # Passwort abfragen
    if [[ "$FOUND" -eq 0 ]]; then
        PASSWORD="$(
            zenity \
                --password \
                --title="PDF-Passwort für '$BASENAME'"
        )"

        if [[ -z "${PASSWORD:-}" ]]; then
            FAILED+=( "$BASENAME – abgebrochen" )
            rm -f "$OUTPUT" "$ERROR_LOG"
            continue
        fi

        if try_password "$PASSWORD"; then
            FOUND=1

            if ! grep -Fq "|${PASSWORD}" "$STORE_FILE" 2>/dev/null; then
                echo "${BASENAME}|${PASSWORD}" >> "$STORE_FILE"
            fi
        fi
    fi

    if [[ "$FOUND" -ne 1 ]]; then
        ERROR_MSG="$(cat "$ERROR_LOG")"
        FAILED+=( "$BASENAME – Entschlüsselung fehlgeschlagen: $ERROR_MSG" )
        rm -f "$OUTPUT" "$ERROR_LOG"
        continue
    fi

    if ! qpdf --check "$OUTPUT" >/dev/null 2>&1; then
        FAILED+=( "$BASENAME – Ergebnis-PDF nicht valide" )
        rm -f "$OUTPUT" "$ERROR_LOG"
        continue
    fi

    if gio trash "$INPUT"; then
        SUCCESS+=( "$(basename "$OUTPUT")" )
    else
        WARNINGS+=( "$(basename "$OUTPUT") – Original blieb erhalten" )
    fi

    rm -f "$ERROR_LOG"
done

MESSAGE=""

if (( ${#SUCCESS[@]} > 0 )); then
    MESSAGE+="Erfolgreich entschlüsselt:\n"
    for x in "${SUCCESS[@]}"; do
        MESSAGE+="• $x\n"
    done
fi

if (( ${#WARNINGS[@]} > 0 )); then
    MESSAGE+="\nWarnungen:\n"
    for x in "${WARNINGS[@]}"; do
        MESSAGE+="• $x\n"
    done
fi

if (( ${#FAILED[@]} > 0 )); then
    MESSAGE+="\nFehler:\n"
    for x in "${FAILED[@]}"; do
        MESSAGE+="• $x\n"
    done
fi

if (( ${#FAILED[@]} > 0 )); then
    zenity --warning --width=650 --text="$MESSAGE"
else
    zenity --info --width=650 --text="$MESSAGE"
fi
