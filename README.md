# PDF Tools

**PDF Tools** is a collection of PDF-processing tools integrated into the
Dolphin file manager through a KDE service menu.

The project was created to make common document-processing tasks available
directly from the file manager without having to manually build long command
lines.

Current version:

**1.2.0**

## Supported systems

The installer currently supports:

- Debian and Debian-based systems using `apt`
- Arch Linux / CachyOS using `pacman`

The actual processing scripts are largely distribution-independent.

The installer detects the available package manager, checks which required
components are already installed, and installs only missing dependencies.

## Dolphin context menu

After installation, PDF files receive a submenu:

**PDF Werkzeuge**

containing:

- Mit PDF Arranger bearbeiten
- OCR Deutsch + ausrichten + vereinzeln
- OCR Deutsch + ausrichten
- OCR English + ausrichten
- OCR Türkisch + ausrichten
- PDF Komprimieren (180dpi)
- PDF vereinzeln
- PDF-Schutz entfernen
- PDFs Zusammenführen
- Ungerade > Links drehen
- Ungerade > Rechts drehen
- Leere Seiten entfernen

Multiple selected PDF files are supported where appropriate.

## Features

### PDF Arranger

Opens the selected PDF files directly in PDF Arranger for manual editing,
page reordering, cropping and other graphical operations.

### OCR

OCR processing is based on:

- OCRmyPDF
- Tesseract
- OpenCV
- Pillow
- Poppler
- img2pdf

Supported OCR languages:

- German (`deu`)
- English (`eng`)
- Turkish (`tur`)

The OCR pipeline intentionally performs normalization before OCR:

    PDF
     |
     v
    Poppler rasterization
     |
     v
    OpenCV deskew
     |
     v
    img2pdf
     |
     v
    OCRmyPDF
     |
     v
    validated PDF

Pages are rasterized with a maximum dimension of approximately 3508 pixels
and reconstructed at 300 dpi.

OCRmyPDF is run using the processing parameters defined by the supplied
scripts, including forced OCR where required.

This means the relevant OCR and deskew configuration is part of the project
itself and does not depend on manually configured per-user settings.

### Deskew

Scanned pages are automatically analyzed with OpenCV.

The deskew helper detects text-line orientation and rotates pages before the
OCR stage.

This was designed especially for scanner-generated PDFs where relying only on
OCRmyPDF's internal deskew operation may produce unreliable page geometry.

### OCR + split

The combined German OCR + split action performs:

    OCR
    +
    deskew
    +
    PDF validation
    +
    split into individual PDF pages

Each generated page receives its own filename and sequence number.

### Split PDF

Splits a PDF into individual one-page PDF files.

Example:

    Document_20261011_143500_SPL_001.pdf
    Document_20261011_143500_SPL_002.pdf
    Document_20261011_143500_SPL_003.pdf

### Remove empty pages

PDF Tools can analyze scanned documents for effectively empty pages.

The analysis uses a low-resolution grayscale representation and ignores a
small outer border to reduce false positives caused by scanner edges.

If no empty page is found, the original PDF remains unchanged.

If processing succeeds, the resulting PDF is validated before the source file
is moved to the trash.

### Merge PDFs

Multiple selected PDFs can be combined into a single document.

Input order is determined by filesystem modification time:

    oldest
      |
      v
    newest

The merge pipeline uses `qpdf` and subsequently performs Ghostscript
compression suitable for scanned books and manuals.

Compression settings:

- color images: 180 dpi
- grayscale images: 180 dpi
- monochrome images: 300 dpi
- font compression enabled
- font subsetting enabled
- duplicate-image detection enabled

The resulting PDF is checked before any source file is moved to the trash.

### Compress PDF

The separate **PDF Komprimieren (180dpi)** action uses the same compression
profile as the merge workflow:

- color: 180 dpi
- grayscale: 180 dpi
- monochrome: 300 dpi

Files already carrying the `CMP` status tag are skipped to avoid unnecessary
repeated lossy recompression.

### Alternate page rotation

Two operations are available for duplex/book scanning workflows:

#### Ungerade > Links drehen

- odd pages: 90 degrees left
- even pages: 90 degrees right

#### Ungerade > Rechts drehen

- odd pages: 90 degrees right
- even pages: 90 degrees left

Rotation is performed through PDF page metadata using `qpdf` and does not
rerender page contents.

## Removing PDF protection

The **PDF-Schutz entfernen** action uses `qpdf` to create an unprotected copy
of a PDF when the correct password is known.

No passwords are included in this repository.

### Optional local password file

Users may create a local password list:

    mkdir -p ~/.config/pdf-remove-protection
    nano ~/.config/pdf-remove-protection/passwords.txt

Store one password per line:

    password1
    password2
    old-document-password

Recommended permissions:

    chmod 600 ~/.config/pdf-remove-protection/passwords.txt

The file is stored only in the local user profile:

    ~/.config/pdf-remove-protection/passwords.txt

It is **not** copied into the PDF Tools installation directory and must never
be committed to Git.

The processing logic is:

1. Try passwords from the local password file.
2. If none works, request a password interactively.
3. Process the PDF with `qpdf`.
4. Validate the generated PDF.
5. Only after successful validation move the original PDF to the trash.

The password file itself is intentionally excluded from this repository.

## Filename status tags

PDF Tools records completed processing stages in filenames.

Current tags:

| Tag | Meaning |
|---|---|
| `OCR` | OCR performed |
| `DSK` | Deskew performed |
| `EPR` | Empty pages removed |
| `DEC` | PDF protection removed |
| `SPL` | PDF split into individual pages |
| `CMP` | PDF compressed |
| `ODL` | Odd pages rotated left |
| `ODR` | Odd pages rotated right |

Tags are not duplicated.

Processing timestamps are updated when a transformation creates a new file.

Example:

    Document_OCR_DSK_EPR_20261011_143500.pdf

A split document may look like:

    Document_OCR_DSK_20261011_143500_SPL_001.pdf

## Safety model

PDF Tools follows a conservative source-file policy.

For automated transformations:

1. Create the output.
2. Validate the resulting PDF.
3. Only after successful validation move the original file to the desktop
   environment's trash.

A failed processing operation therefore does not intentionally delete the
source PDF.

Where applicable, output validation is performed using `qpdf`.

The project does not ship:

- passwords
- API keys
- authentication tokens
- private keys
- machine-specific configuration
- user-specific home-directory paths

## Dependencies

The complete toolchain includes:

- Bash
- Python 3
- OpenCV for Python
- Pillow
- Poppler
- img2pdf
- OCRmyPDF
- qpdf
- Ghostscript
- GLib / `gio`
- Zenity
- Tesseract OCR
- German Tesseract language data
- English Tesseract language data
- Turkish Tesseract language data
- PDF Arranger
- Konsole
- Dolphin / KDE KIO components

The installer checks existing commands, Python modules and Tesseract language
data before installing missing dependencies.

## Installation

Clone or copy the project and run:

    ./install.sh

Run the installer as your normal desktop user, **not as root**.

Administrative privileges are requested through `sudo` only when system
packages must be installed.

The installer detects either:

    apt

or:

    pacman

and uses the corresponding dependency mapping.

Existing components are retained and are not unnecessarily reinstalled.

## Arch Linux / CachyOS

System packages are installed through `pacman`.

If OCRmyPDF is not already installed and requires an AUR installation, the
installer can use an available AUR helper such as:

    yay

or:

    paru

If neither is available, installation stops instead of silently creating an
incomplete PDF Tools environment.

## Installation locations

Scripts:

    ~/Scripts/pdf-tools/

Dolphin/KIO service menu:

    ~/.local/share/kio/servicemenus/ocr-pdf.desktop

Internal helper references use paths relative to the script directory rather
than hard-coded usernames or `/home/...` paths.

## KDE service-menu permissions

On some KDE installations, Dolphin requires the service-menu file to be
executable.

The installer therefore sets:

    chmod 755 ~/.local/share/kio/servicemenus/ocr-pdf.desktop

Otherwise Dolphin may report that the service action cannot be executed.

## Health check

During installation the installer verifies important components, including:

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

It additionally checks:

- Python OpenCV
- Python Pillow
- Tesseract `deu`
- Tesseract `eng`
- Tesseract `tur`

The PDF Tools installation is only completed after the dependency health
check succeeds.

## Uninstall

Run:

    ./uninstall.sh

This removes:

    ~/Scripts/pdf-tools/
    ~/.local/share/kio/servicemenus/ocr-pdf.desktop

System packages installed as dependencies are intentionally left installed.

## Project structure

    PDF-TOOLS/
    ├── install.sh
    ├── uninstall.sh
    ├── README.md
    ├── VERSION
    ├── LICENSE
    ├── CHANGELOG.md
    ├── .gitignore
    ├── kde/
    │   └── ocr-pdf.desktop.in
    └── scripts/
        ├── ocr-pdf.sh
        ├── pdf-alternate-rotate.sh
        ├── pdf-bulk.sh
        ├── pdf-compress-180.sh
        ├── pdf-deskew-opencv.py
        ├── pdf-empty-pages.sh
        ├── pdf-merge.sh
        ├── pdf-name.py
        └── pdf-remove-protection.sh

## License

Released under the MIT License.

See `LICENSE`.

---

## Troubleshooting installation

### CachyOS / Arch: HTTP 404 while downloading packages

Arch-based systems must not be partially upgraded.

When PDF Tools needs additional repository packages, the installer therefore
uses a synchronized system/package transaction.

If Pacman reports errors such as:

    failed retrieving file
    HTTP 404

the selected package mirror and package database may be out of sync.

On CachyOS:

    sudo cachyos-rate-mirrors
    sudo pacman -Syyu

Then run:

    ./install.sh

again.

### Invalid or corrupted package signature

If Pacman reports:

    invalid or corrupted package
    signature ... is invalid

first make sure the system and mirrors are fully synchronized.

On CachyOS:

    sudo cachyos-rate-mirrors
    sudo pacman -Syyu

If the signature failure remains after synchronization, investigate the
Pacman/CachyOS keyring separately rather than disabling signature checking.

PDF Tools does not disable Pacman signature verification.

### OCRmyPDF on CachyOS

OCRmyPDF is installed through the AUR when it is not already available.

PDF Tools checks in this order:

1. Existing `ocrmypdf`
2. Existing `paru`
3. Existing `yay`
4. On CachyOS, install `paru` from the CachyOS repository
5. Install `ocrmypdf` using the detected AUR helper

Using an AUR helper is important because OCRmyPDF can itself depend on other
AUR packages, such as `python-fpdf2`.

During an AUR installation, `paru` or `yay` may display PKGBUILDs using the
`less` pager.

The message may look like:

    Paging with less. Press 'q' to quit or 'h' for help.

Press:

    q

to leave the review view and continue with the installation prompts.

### KDE warnings after installation

`kbuildsycoca6` scans many desktop files belonging to other applications.

Warnings such as:

    KConfigIni: Invalid escape sequence

can therefore originate from unrelated Wine or application `.desktop` files.

PDF Tools reports these as warnings but does not treat them as a failed PDF
Tools installation unless its own service menu fails validation.

### Installation log

Every installer run creates a log under:

    ~/.local/state/pdf-tools/

For example:

    ~/.local/state/pdf-tools/install-20261011-153000.log

When reporting an installation problem, this log is the preferred diagnostic
source.

### Running the installer

Run PDF Tools from a terminal:

    ./install.sh

Do not run it directly as root.

The installer invokes `sudo` itself only for system package operations.

Launching a shell script by double-clicking it in a graphical file manager is
not guaranteed to provide an interactive terminal for password prompts.

---
