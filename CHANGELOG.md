# Changelog

All notable changes to PDF Tools are documented in this file.

## [1.2.0] - 2026-10-11

### Added

- Debian and Arch/CachyOS installer logic.
- Dependency detection before package installation.
- OCR dependency health checks.
- Tesseract language checks for German, English and Turkish.
- `PDF Komprimieren (180dpi)` action.
- Alternate odd/even page rotation:
  - odd pages left / even pages right
  - odd pages right / even pages left
- `CMP`, `ODL` and `ODR` filename status tags.
- Portable internal script references using `SCRIPT_DIR`.
- Public-project documentation.
- Local password-file documentation.
- Git ignore rules for secrets and local files.

### Changed

- Internal helper paths no longer contain hard-coded user home directories.
- All custom Dolphin processing actions use a consistent execution model.
- Installation now checks existing dependencies and installs only missing
  components.
- Installer performs a complete dependency health check before activating the
  Dolphin service menu.

### Safety

- Original PDFs are retained until generated output has successfully passed
  validation.
- Local PDF passwords remain outside the project directory.
- No passwords or other credentials are distributed with the project.

## [1.0.0]

### Added

- Initial portable PDF Tools package.
- Dolphin/KDE service menu.
- OCR German, English and Turkish.
- OpenCV deskew.
- OCR + split workflow.
- PDF splitting.
- Empty-page removal.
- PDF protection removal.
- PDF merging sorted by file modification time.
- Ghostscript compression for merged scanner documents.
- Filename status-tagging system.

## [1.2.1] - 2026-10-11

### Fixed

- Improved CachyOS and Arch dependency installation.
- Arch package installation now avoids partial upgrades by using a full
  repository/system synchronization transaction when new repository packages
  are required.
- Added specific diagnostics for HTTP 404 mirror failures.
- Added specific diagnostics for invalid or corrupted package signatures.
- Added CachyOS mirror-recovery instructions using `cachyos-rate-mirrors`.
- Added automatic installation of `paru` from the CachyOS repository when
  OCRmyPDF is missing and no AUR helper is installed.
- OCRmyPDF installation now uses `paru` or `yay`, allowing recursive AUR
  dependencies such as `python-fpdf2` to be resolved correctly.
- Added explanation for the AUR PKGBUILD review pager.
- KDE cache warnings originating from unrelated `.desktop` files no longer
  make the PDF Tools installation appear to have failed.
- Added rollback of the previous PDF Tools script installation if copying or
  syntax validation fails.
- Added final service-menu validation and post-install checks.

### Added

- Persistent per-install log under:
  `~/.local/state/pdf-tools/`
- Installer package-integrity checks before dependency installation.
- Clear distribution, package-manager and failure diagnostics.
- Validation that the generated KDE service menu contains no unresolved
  `@INSTALL_DIR@` placeholder.
