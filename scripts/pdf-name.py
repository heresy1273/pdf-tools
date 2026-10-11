#!/usr/bin/env python3

import argparse
import re
from datetime import datetime
from pathlib import Path


TAG_ORDER = ("OCR", "DSK", "EPR", "DEC", "ODL", "ODR", "CMP")

TIMESTAMP_RE = re.compile(r"^\d{8}_\d{6}$")
PAGE_RE = re.compile(r"^\d{3,}$")


def parse_name(path: Path):
    """
    Zerlegt unsere eigene Dateinomenklatur.

    Beispiel:
      Rechnung_OCR_DSK_EPR_20260902_210000_SPL_003.pdf

    Ergebnis:
      base       = Rechnung
      tags       = {OCR, DSK, EPR}
      split      = True
      page_index = 003
    """

    stem = path.stem

    split = False
    page_index = None

    # SPL_001 am Ende erkennen
    m = re.search(r"_SPL_(\d{3,})$", stem)
    if m:
        split = True
        page_index = m.group(1)
        stem = stem[:m.start()]

    # SPL ohne Seitennummer
    elif stem.endswith("_SPL"):
        split = True
        stem = stem[:-4]

    # Alten Zeitstempel am Ende entfernen
    m = re.search(r"_(\d{8}_\d{6})$", stem)
    if m:
        stem = stem[:m.start()]

    # Bekannte Status-Tags nur am Ende des Basisnamens abziehen.
    tags = set()

    changed = True
    while changed:
        changed = False

        for tag in TAG_ORDER:
            suffix = "_" + tag

            if stem.endswith(suffix):
                tags.add(tag)
                stem = stem[:-len(suffix)]
                changed = True
                break

    return stem, tags, split, page_index


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("file")

    parser.add_argument(
        "--add",
        nargs="*",
        default=[],
        choices=["OCR", "DSK", "EPR", "DEC", "ODL", "ODR", "CMP"]
    )

    parser.add_argument(
        "--split",
        action="store_true"
    )

    parser.add_argument(
        "--index",
        type=int
    )

    parser.add_argument(
        "--timestamp"
    )

    args = parser.parse_args()

    path = Path(args.file)

    base, tags, was_split, old_index = parse_name(path)

    tags.update(args.add)

    split = was_split or args.split

    if args.timestamp:
        timestamp = args.timestamp
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    parts = [base]

    # Immer kanonische Reihenfolge
    for tag in TAG_ORDER:
        if tag in tags:
            parts.append(tag)

    parts.append(timestamp)

    if split:
        parts.append("SPL")

        if args.index is not None:
            parts.append(f"{args.index:03d}")

        elif old_index is not None:
            parts.append(old_index)

    filename = "_".join(parts) + path.suffix.lower()

    print(str(path.parent / filename))


if __name__ == "__main__":
    main()
