#!/bin/bash
set -Eeuo pipefail

# ============================================================
# PDF Tools Installer
#
# Supported:
#   - Debian / Debian-based distributions using apt
#   - Arch Linux
#   - CachyOS
#
# Principles:
#   - Run as normal desktop user
#   - Install only missing functional dependencies
#   - No Arch partial upgrades
#   - Handle OCRmyPDF/AUR separately
#   - Do not activate Dolphin integration before healthcheck
#   - Preserve existing PDF Tools installation as backup
#   - Produce an installation log
#   - Give actionable diagnostics on known failure cases
# ============================================================

if (( EUID == 0 )); then
    echo
    echo "FEHLER:"
    echo "PDF Tools darf nicht direkt als root gestartet werden."
    echo
    echo "Als normaler Benutzer starten:"
    echo "  ./install.sh"
    echo
    echo "sudo wird vom Installer nur für Systempakete verwendet."
    exit 1
fi

PACKAGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$PACKAGE_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "FEHLER: VERSION-Datei fehlt:"
    echo "  $VERSION_FILE"
    exit 1
fi

VERSION="$(<"$VERSION_FILE")"

INSTALL_DIR="$HOME/Scripts/pdf-tools"
SERVICE_DIR="$HOME/.local/share/kio/servicemenus"
SERVICE_FILE="$SERVICE_DIR/ocr-pdf.desktop"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pdf-tools"
mkdir -p "$STATE_DIR"

LOGFILE="$STATE_DIR/install-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "$LOGFILE") 2>&1

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

have_python_module() {
    python3 - "$1" <<'PY' >/dev/null 2>&1
import importlib
import sys
importlib.import_module(sys.argv[1])
PY
}

have_tess_lang() {
    have_cmd tesseract || return 1
    tesseract --list-langs 2>/dev/null | grep -qx "$1"
}

print_ok() {
    printf "  OK      %-24s\n" "$1"
}

print_missing() {
    printf "  FEHLT   %-24s -> %s\n" "$1" "$2"
}

fatal() {
    echo
    echo "=================================================="
    echo " PDF TOOLS INSTALLATION ABGEBROCHEN"
    echo "=================================================="
    echo
    printf '%s\n' "$@"
    echo
    echo "Installationslog:"
    echo "  $LOGFILE"
    exit 1
}

on_error() {
    local rc="$?"
    local line="$1"
    local command="$2"

    echo
    echo "=================================================="
    echo " UNERWARTETER INSTALLATIONSFEHLER"
    echo "=================================================="
    echo
    echo "Exit-Code : $rc"
    echo "Zeile     : $line"
    echo "Befehl    : $command"
    echo
    echo "Installationslog:"
    echo "  $LOGFILE"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

echo "=================================================="
echo " PDF TOOLS $VERSION"
echo "=================================================="
echo
echo "Installationslog:"
echo "  $LOGFILE"
echo

# ------------------------------------------------------------
# Installationspaket prüfen
# ------------------------------------------------------------

required_project_files=(
    "$PACKAGE_DIR/scripts/ocr-pdf.sh"
    "$PACKAGE_DIR/scripts/pdf-alternate-rotate.sh"
    "$PACKAGE_DIR/scripts/pdf-bulk.sh"
    "$PACKAGE_DIR/scripts/pdf-compress-180.sh"
    "$PACKAGE_DIR/scripts/pdf-deskew-opencv.py"
    "$PACKAGE_DIR/scripts/pdf-empty-pages.sh"
    "$PACKAGE_DIR/scripts/pdf-merge.sh"
    "$PACKAGE_DIR/scripts/pdf-name.py"
    "$PACKAGE_DIR/scripts/pdf-remove-protection.sh"
    "$PACKAGE_DIR/kde/ocr-pdf.desktop.in"
)

echo "===== INSTALLATIONSPAKET ====="

for f in "${required_project_files[@]}"; do
    if [[ -f "$f" ]]; then
        print_ok "$(basename "$f")"
    else
        fatal \
            "Das Installationspaket ist unvollständig." \
            "Es fehlt:" \
            "  $f"
    fi
done

echo

# ------------------------------------------------------------
# Distribution erkennen
# ------------------------------------------------------------

if [[ ! -r /etc/os-release ]]; then
    fatal "/etc/os-release konnte nicht gelesen werden."
fi

# shellcheck disable=SC1091
. /etc/os-release

DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"
PRETTY="${PRETTY_NAME:-unbekannt}"

if have_cmd apt-get; then
    FAMILY="debian"
elif have_cmd pacman; then
    FAMILY="arch"
else
    fatal \
        "Kein unterstützter Paketmanager gefunden." \
        "" \
        "Unterstützt werden derzeit:" \
        "  Debian / apt" \
        "  Arch Linux / pacman" \
        "  CachyOS / pacman"
fi

IS_CACHYOS=0

if [[ "$DISTRO_ID" == "cachyos" ]] || [[ "$PRETTY" == *"CachyOS"* ]]; then
    IS_CACHYOS=1
fi

echo "===== SYSTEM ====="
echo "Distribution : $PRETTY"
echo "ID           : $DISTRO_ID"
echo "ID_LIKE      : ${DISTRO_LIKE:-n/a}"
echo "Familie      : $FAMILY"
echo "Benutzer     : $USER"
echo

# ------------------------------------------------------------
# Fehlende Repo-Abhängigkeiten ermitteln
# ------------------------------------------------------------

declare -a PACKAGES=()

need_cmd() {
    local command="$1"
    local package="$2"

    if have_cmd "$command"; then
        print_ok "$command"
    else
        print_missing "$command" "$package"
        PACKAGES+=( "$package" )
    fi
}

need_python() {
    local module="$1"
    local package="$2"

    if have_python_module "$module"; then
        print_ok "Python $module"
    else
        print_missing "Python $module" "$package"
        PACKAGES+=( "$package" )
    fi
}

need_lang() {
    local language="$1"
    local package="$2"

    if have_tess_lang "$language"; then
        print_ok "Tesseract $language"
    else
        print_missing "Tesseract $language" "$package"
        PACKAGES+=( "$package" )
    fi
}

echo "===== ABHÄNGIGKEITEN ====="

if [[ "$FAMILY" == "debian" ]]; then

    need_cmd python3       python3
    need_cmd pdftoppm      poppler-utils
    need_cmd pdfseparate   poppler-utils
    need_cmd pdfunite      poppler-utils
    need_cmd img2pdf       img2pdf
    need_cmd ocrmypdf      ocrmypdf
    need_cmd qpdf          qpdf
    need_cmd gs            ghostscript
    need_cmd gio           libglib2.0-bin
    need_cmd zenity        zenity
    need_cmd pdfarranger   pdfarranger
    need_cmd konsole       konsole
    need_cmd dolphin       dolphin
    need_cmd tesseract     tesseract-ocr

    need_python cv2        python3-opencv
    need_python PIL        python3-pil

    need_lang deu          tesseract-ocr-deu
    need_lang eng          tesseract-ocr-eng
    need_lang tur          tesseract-ocr-tur

else

    need_cmd python3       python
    need_cmd pdftoppm      poppler
    need_cmd pdfseparate   poppler
    need_cmd pdfunite      poppler
    need_cmd img2pdf       img2pdf
    need_cmd qpdf          qpdf
    need_cmd gs            ghostscript
    need_cmd gio           glib2
    need_cmd zenity        zenity
    need_cmd pdfarranger   pdfarranger
    need_cmd konsole       konsole
    need_cmd dolphin       dolphin
    need_cmd tesseract     tesseract

    need_python cv2        python-opencv
    need_python PIL        python-pillow

    need_lang deu          tesseract-data-deu
    need_lang eng          tesseract-data-eng
    need_lang tur          tesseract-data-tur
fi

if (( ${#PACKAGES[@]} > 0 )); then
    mapfile -t PACKAGES < <(
        printf '%s\n' "${PACKAGES[@]}" | sort -u
    )
fi

echo

# ------------------------------------------------------------
# Debian
# ------------------------------------------------------------

if [[ "$FAMILY" == "debian" ]]; then

    if (( ${#PACKAGES[@]} == 0 )); then
        echo "Keine Debian-Systempakete nachzuinstallieren."
    else
        echo "===== FEHLENDE DEBIAN-PAKETE ====="
        printf '  %s\n' "${PACKAGES[@]}"
        echo

        echo "Aktualisiere Paketindex ..."

        if ! sudo apt-get update; then
            fatal \
                "apt-get update ist fehlgeschlagen." \
                "" \
                "Bitte Netzwerk und apt-Repositories prüfen."
        fi

        echo
        echo "Installiere nur fehlende Pakete ..."

        if ! sudo apt-get install "${PACKAGES[@]}"; then
            fatal \
                "Mindestens eine Debian-Abhängigkeit konnte nicht installiert werden." \
                "" \
                "Die apt-Ausgabe oberhalb enthält die Ursache."
        fi
    fi
fi

# ------------------------------------------------------------
# Arch / CachyOS
#
# Keine Partial Upgrades.
# Wenn neue Repo-Pakete benötigt werden:
#
# pacman -Syu --needed <Pakete>
#
# ------------------------------------------------------------

if [[ "$FAMILY" == "arch" ]]; then

    if (( ${#PACKAGES[@]} == 0 )); then
        echo "Keine Arch/CachyOS-Systempakete nachzuinstallieren."
    else
        echo "===== FEHLENDE ARCH/CACHYOS-PAKETE ====="
        printf '  %s\n' "${PACKAGES[@]}"
        echo
        echo "Arch-basierte Systeme unterstützen keine Partial Upgrades."
        echo
        echo "Deshalb wird Paketinstallation mit System-Synchronisation"
        echo "kombiniert:"
        echo
        echo "  sudo pacman -Syu --needed ..."
        echo

        PACMAN_LOG="$(mktemp)"

        set +e
        sudo pacman -Syu --needed "${PACKAGES[@]}" 2>&1 | tee "$PACMAN_LOG"
        PACMAN_RC=${PIPESTATUS[0]}
        set -e

        if (( PACMAN_RC != 0 )); then
            echo
            echo "===== PACMAN-FEHLERANALYSE ====="

            if grep -Eqi \
                '404|failed retrieving file|requested URL returned error' \
                "$PACMAN_LOG"
            then
                echo "ERKANNT:"
                echo "Repository-/Mirror-Fehler."
                echo

                if (( IS_CACHYOS == 1 )); then
                    echo "CachyOS wurde erkannt."
                    echo
                    echo "Empfohlene Reparatur:"
                    echo
                    echo "  sudo cachyos-rate-mirrors"
                    echo "  sudo pacman -Syyu"
                    echo
                    echo "Danach ./install.sh erneut starten."
                else
                    echo "Empfohlen:"
                    echo
                    echo "  sudo pacman -Syyu"
                    echo
                    echo "Danach ./install.sh erneut starten."
                fi

            elif grep -Eqi \
                'invalid or corrupted package|signature .* invalid|PGP signature' \
                "$PACMAN_LOG"
            then
                echo "ERKANNT:"
                echo "Paket-/Signaturprüfung fehlgeschlagen."
                echo

                if (( IS_CACHYOS == 1 )); then
                    echo "Bei CachyOS zuerst Mirror und Paketdatenbanken"
                    echo "synchronisieren:"
                    echo
                    echo "  sudo cachyos-rate-mirrors"
                    echo "  sudo pacman -Syyu"
                    echo
                    echo "Danach ./install.sh erneut starten."
                    echo
                    echo "Falls der Signaturfehler bestehen bleibt,"
                    echo "CachyOS-Keyring/Pacman separat prüfen."
                else
                    echo "Zuerst vollständige Systemsynchronisation versuchen:"
                    echo
                    echo "  sudo pacman -Syyu"
                    echo
                    echo "Falls der Fehler bestehen bleibt,"
                    echo "Arch-Keyring/Pacman separat prüfen."
                fi

                echo
                echo "PDF Tools deaktiviert die Signaturprüfung NICHT."

            else
                echo "Pacman konnte die benötigten Pakete nicht installieren."
                echo
                echo "Bitte die vollständige Pacman-Ausgabe oberhalb prüfen."
            fi

            rm -f "$PACMAN_LOG"

            fatal \
                "Arch/CachyOS-Abhängigkeiten konnten nicht vollständig installiert werden." \
                "Die PDF-Tools-Integration wurde noch nicht aktiviert."
        fi

        rm -f "$PACMAN_LOG"
    fi
fi

# ------------------------------------------------------------
# OCRmyPDF auf Arch/CachyOS
# ------------------------------------------------------------

if [[ "$FAMILY" == "arch" ]] && ! have_cmd ocrmypdf; then

    echo
    echo "===== OCRmyPDF ====="
    echo "OCRmyPDF ist noch nicht installiert."
    echo

    AUR_HELPER=""

    if have_cmd paru; then
        AUR_HELPER="paru"
        echo "AUR-Helper gefunden: paru"

    elif have_cmd yay; then
        AUR_HELPER="yay"
        echo "AUR-Helper gefunden: yay"

    elif (( IS_CACHYOS == 1 )); then
        echo "CachyOS erkannt."
        echo "Weder paru noch yay ist vorhanden."
        echo
        echo "CachyOS stellt paru im eigenen Repository bereit."
        echo "Installiere paru ..."

        PARU_LOG="$(mktemp)"

        set +e
        sudo pacman -Syu --needed paru 2>&1 | tee "$PARU_LOG"
        PARU_RC=${PIPESTATUS[0]}
        set -e

        if (( PARU_RC != 0 )); then
            echo
            echo "===== PARU-INSTALLATION FEHLGESCHLAGEN ====="

            if grep -Eqi \
                '404|failed retrieving file|requested URL returned error' \
                "$PARU_LOG"
            then
                echo
                echo "Mirror-/Repositoryfehler erkannt."
                echo
                echo "Bitte ausführen:"
                echo
                echo "  sudo cachyos-rate-mirrors"
                echo "  sudo pacman -Syyu"
                echo
                echo "Danach ./install.sh erneut starten."
            fi

            rm -f "$PARU_LOG"

            fatal \
                "paru konnte aus dem CachyOS-Repository nicht installiert werden."
        fi

        rm -f "$PARU_LOG"

        if ! have_cmd paru; then
            fatal \
                "Pacman meldete keinen Fehler, aber paru wurde anschließend nicht gefunden."
        fi

        AUR_HELPER="paru"

    else
        fatal \
            "OCRmyPDF fehlt auf diesem Arch-System." \
            "" \
            "Zusätzlich wurde weder paru noch yay gefunden." \
            "" \
            "Bitte einen AUR-Helper installieren oder OCRmyPDF manuell" \
            "aus dem AUR installieren." \
            "" \
            "Danach ./install.sh erneut starten."
    fi

    echo
    echo "OCRmyPDF wird über $AUR_HELPER installiert."
    echo
    echo "AUR-HINWEIS:"
    echo "Der Helper kann vor dem Build PKGBUILDs anzeigen."
    echo
    echo "Falls folgende Meldung erscheint:"
    echo
    echo "  Paging with less. Press 'q' to quit or 'h' for help."
    echo
    echo "drücke:"
    echo
    echo "  q"
    echo
    echo "Danach läuft der Installationsdialog weiter."
    echo
    echo "AUR-Abhängigkeiten wie python-fpdf2 werden vom Helper"
    echo "automatisch mit aufgelöst."
    echo

    if ! "$AUR_HELPER" -S --needed ocrmypdf; then
        fatal \
            "OCRmyPDF konnte über $AUR_HELPER nicht installiert werden." \
            "" \
            "Mögliche Ursachen:" \
            "  - AUR-Abhängigkeit nicht baubar" \
            "  - Netzwerkfehler" \
            "  - veralteter Repository-/Systemstand" \
            "  - Abbruch im PKGBUILD-Review" \
            "" \
            "Bitte die AUR-Ausgabe oberhalb prüfen."
    fi
fi

# ------------------------------------------------------------
# Vollständiger Healthcheck
# ------------------------------------------------------------

echo
echo "===== HEALTHCHECK ====="

FAILED=0

required_commands=(
    python3
    pdftoppm
    pdfseparate
    pdfunite
    img2pdf
    ocrmypdf
    qpdf
    gs
    gio
    zenity
    pdfarranger
    konsole
    dolphin
    tesseract
)

for cmd in "${required_commands[@]}"; do
    if have_cmd "$cmd"; then
        printf "  OK      %-24s %s\n" "$cmd" "$(command -v "$cmd")"
    else
        printf "  FEHLT   %-24s\n" "$cmd"
        FAILED=1
    fi
done

if have_python_module cv2; then
    print_ok "Python OpenCV"
else
    echo "  FEHLT   Python OpenCV"
    FAILED=1
fi

if have_python_module PIL; then
    print_ok "Python Pillow"
else
    echo "  FEHLT   Python Pillow"
    FAILED=1
fi

for lang in deu eng tur; do
    if have_tess_lang "$lang"; then
        print_ok "OCR Sprache $lang"
    else
        echo "  FEHLT   OCR Sprache $lang"
        FAILED=1
    fi
done

if (( FAILED != 0 )); then
    fatal \
        "Der Dependency-Healthcheck ist fehlgeschlagen." \
        "Das Dolphin-Service-Menü wird nicht installiert."
fi

echo
echo "OCRmyPDF:"
ocrmypdf --version

echo
echo "Tesseract:"
tesseract --version | head -1

echo
echo "OCR-Sprachen:"
tesseract --list-langs

# ------------------------------------------------------------
# Vorhandene Installation sichern
# ------------------------------------------------------------

echo
echo "===== INSTALLATION ====="

BACKUP=""

if [[ -d "$INSTALL_DIR" ]]; then
    BACKUP="${INSTALL_DIR}.bak-$(date +%Y%m%d-%H%M%S)"

    echo "Vorhandene PDF-Tools sichern:"
    echo "  $BACKUP"

    mv "$INSTALL_DIR" "$BACKUP"
fi

mkdir -p "$INSTALL_DIR"
mkdir -p "$SERVICE_DIR"

# ------------------------------------------------------------
# Scripts installieren
# ------------------------------------------------------------

if ! cp -a "$PACKAGE_DIR/scripts/." "$INSTALL_DIR/"; then
    echo
    echo "Kopieren der Scripts fehlgeschlagen."

    rm -rf "$INSTALL_DIR"

    if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
        echo "Stelle vorherige Installation wieder her ..."
        mv "$BACKUP" "$INSTALL_DIR"
    fi

    fatal "PDF-Tools-Scripts konnten nicht installiert werden."
fi

rm -rf "$INSTALL_DIR/__pycache__"

chmod 755 "$INSTALL_DIR"/*.sh
chmod 755 "$INSTALL_DIR"/*.py

# ------------------------------------------------------------
# Script-Syntax prüfen
# ------------------------------------------------------------

echo
echo "===== SCRIPT-PRÜFUNG ====="

SCRIPT_FAILURE=0

for f in "$INSTALL_DIR"/*.sh; do
    if bash -n "$f"; then
        echo "  OK: $(basename "$f")"
    else
        echo "  FEHLER: $(basename "$f")"
        SCRIPT_FAILURE=1
    fi
done

if python3 -m py_compile \
    "$INSTALL_DIR/pdf-name.py" \
    "$INSTALL_DIR/pdf-deskew-opencv.py"
then
    echo "  OK: pdf-name.py"
    echo "  OK: pdf-deskew-opencv.py"
else
    SCRIPT_FAILURE=1
fi

rm -rf "$INSTALL_DIR/__pycache__"

if (( SCRIPT_FAILURE != 0 )); then
    rm -rf "$INSTALL_DIR"

    if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
        echo "Stelle vorherige Installation wieder her ..."
        mv "$BACKUP" "$INSTALL_DIR"
    fi

    fatal \
        "Die installierten Scripts haben den Syntaxcheck nicht bestanden." \
        "Die vorherige Installation wurde soweit möglich wiederhergestellt."
fi

# ------------------------------------------------------------
# Portabilität prüfen
# ------------------------------------------------------------

if grep -RInE '/home/[A-Za-z0-9._-]+/' "$INSTALL_DIR" >/dev/null 2>&1; then
    fatal \
        "In den Scripts wurde ein fest codierter /home/<user>/ Pfad gefunden." \
        "Dieser Paketstand ist nicht portabel."
fi

# ------------------------------------------------------------
# Dolphin Service Menu erzeugen
# ------------------------------------------------------------

echo
echo "===== DOLPHIN SERVICE-MENÜ ====="

TEMP_SERVICE="$(mktemp)"

sed \
    "s#@INSTALL_DIR@#$INSTALL_DIR#g" \
    "$PACKAGE_DIR/kde/ocr-pdf.desktop.in" \
    > "$TEMP_SERVICE"

if ! grep -q '^Type=Service$' "$TEMP_SERVICE"; then
    rm -f "$TEMP_SERVICE"
    fatal "Service-Menü ungültig: Type=Service fehlt."
fi

if ! grep -q '^MimeType=application/pdf;' "$TEMP_SERVICE"; then
    rm -f "$TEMP_SERVICE"
    fatal "Service-Menü ungültig: PDF-MimeType fehlt."
fi

if grep -q '@INSTALL_DIR@' "$TEMP_SERVICE"; then
    rm -f "$TEMP_SERVICE"
    fatal "Service-Menü enthält weiterhin @INSTALL_DIR@."
fi

mv "$TEMP_SERVICE" "$SERVICE_FILE"
chmod 755 "$SERVICE_FILE"

echo "Service-Menü:"
echo "  $SERVICE_FILE"

# ------------------------------------------------------------
# KDE Cache
# ------------------------------------------------------------

echo
echo "===== KDE CACHE ====="

if have_cmd kbuildsycoca6; then
    KDE_LOG="$(mktemp)"

    set +e
    kbuildsycoca6 2>&1 | tee "$KDE_LOG"
    KDE_RC=${PIPESTATUS[0]}
    set -e

    if (( KDE_RC != 0 )); then
        echo
        echo "WARNUNG:"
        echo "kbuildsycoca6 meldete einen Fehler."
        echo
        echo "PDF Tools wurde installiert."
        echo "Dolphin/KDE muss möglicherweise separat neu geladen werden."

    elif grep -qE 'KConfigIni:|Invalid escape sequence' "$KDE_LOG"; then
        echo
        echo "HINWEIS:"
        echo "KDE meldete Warnungen aus .desktop-Dateien."
        echo
        echo "Diese können von anderen Anwendungen stammen,"
        echo "z.B. von durch Wine erzeugten Desktop-Dateien."
        echo
        echo "Die PDF-Tools-Installation gilt deshalb nicht als fehlgeschlagen."
    fi

    rm -f "$KDE_LOG"

elif have_cmd kbuildsycoca5; then
    if ! kbuildsycoca5; then
        echo
        echo "WARNUNG:"
        echo "kbuildsycoca5 meldete einen Fehler."
        echo "PDF Tools ist installiert; Dolphin ggf. neu starten."
    fi

else
    echo
    echo "WARNUNG:"
    echo "kbuildsycoca wurde nicht gefunden."
    echo "Das Kontextmenü erscheint eventuell erst nach Neustart"
    echo "von Dolphin bzw. der KDE-Sitzung."
fi

# ------------------------------------------------------------
# Nachkontrolle
# ------------------------------------------------------------

echo
echo "===== INSTALLATIONS-NACHKONTROLLE ====="

FINAL_FAILED=0

if [[ -f "$SERVICE_FILE" && -x "$SERVICE_FILE" ]]; then
    print_ok "Service-Menü ausführbar"
else
    echo "  FEHLT   Service-Menü ausführbar"
    FINAL_FAILED=1
fi

installed_scripts=(
    ocr-pdf.sh
    pdf-alternate-rotate.sh
    pdf-bulk.sh
    pdf-compress-180.sh
    pdf-deskew-opencv.py
    pdf-empty-pages.sh
    pdf-merge.sh
    pdf-name.py
    pdf-remove-protection.sh
)

for f in "${installed_scripts[@]}"; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        print_ok "$f"
    else
        echo "  FEHLT   $f"
        FINAL_FAILED=1
    fi
done

if (( FINAL_FAILED != 0 )); then
    fatal "Die Installations-Nachkontrolle ist fehlgeschlagen."
fi

echo
echo "=================================================="
echo " PDF TOOLS $VERSION ERFOLGREICH INSTALLIERT"
echo "=================================================="
echo
echo "System:"
echo "  $PRETTY"
echo
echo "Scripts:"
echo "  $INSTALL_DIR"
echo
echo "Kontextmenü:"
echo "  $SERVICE_FILE"
echo
echo "Installationslog:"
echo "  $LOGFILE"
echo
echo "Falls Dolphin bereits geöffnet ist:"
echo
echo "  pkill dolphin"
echo
echo "Danach Dolphin normal neu starten."
