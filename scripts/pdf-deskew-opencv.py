#!/usr/bin/env python3

import sys
import glob
import os
import cv2
import numpy as np

workdir = sys.argv[1]

files = sorted(
    glob.glob(os.path.join(workdir, "page-*.jpg")),
    key=lambda p: int(os.path.basename(p).split("-")[-1].split(".")[0])
)

if not files:
    print("FEHLER: Keine gerenderten Seiten gefunden.", file=sys.stderr)
    sys.exit(1)

for page_no, path in enumerate(files, start=1):

    img = cv2.imread(path)
    if img is None:
        print(f"FEHLER: Kann Seite {page_no} nicht lesen.", file=sys.stderr)
        sys.exit(1)

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Scannerhintergrund / sehr helle Pixel ignorieren
    _, bw = cv2.threshold(
        gray,
        210,
        255,
        cv2.THRESH_BINARY_INV
    )

    bw = cv2.morphologyEx(
        bw,
        cv2.MORPH_OPEN,
        cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    )

    points = cv2.findNonZero(bw)

    angle = 0.0
    reliable = False

    if points is not None:

        x, y, w, h = cv2.boundingRect(points)

        pad = 10
        x = max(0, x - pad)
        y = max(0, y - pad)
        w = min(gray.shape[1] - x, w + 2 * pad)
        h = min(gray.shape[0] - y, h + 2 * pad)

        roi = gray[y:y+h, x:x+w]

        text = cv2.adaptiveThreshold(
            roi,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,
            31,
            15
        )

        kernel = cv2.getStructuringElement(
            cv2.MORPH_RECT,
            (35, 3)
        )

        text_lines = cv2.dilate(
            text,
            kernel,
            iterations=1
        )

        contours, _ = cv2.findContours(
            text_lines,
            cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE
        )

        angles = []

        for c in contours:

            x2, y2, w2, h2 = cv2.boundingRect(c)

            if w2 < 80 or h2 < 5:
                continue

            if w2 / max(h2, 1) < 2.5:
                continue

            pts = c.reshape(-1, 2).astype(np.float32)

            rect = cv2.minAreaRect(pts)
            (_, _), (rw, rh), a = rect

            if rw < rh:
                a += 90

            while a > 45:
                a -= 90

            while a < -45:
                a += 90

            if abs(a) <= 20:
                angles.append(a)

        if angles:
            angles = np.array(angles)

            median = np.median(angles)
            good = angles[np.abs(angles - median) <= 3.0]

            if len(good):
                angle = float(np.median(good))
                reliable = True

    # Kleine Restneigungen ignorieren
    if abs(angle) < 0.5:
        angle = 0.0

    if reliable and angle != 0.0:

        h, w = img.shape[:2]
        cx, cy = w / 2, h / 2

        M = cv2.getRotationMatrix2D(
            (cx, cy),
            angle,
            1.0
        )

        cos = abs(M[0, 0])
        sin = abs(M[0, 1])

        new_w = int((h * sin) + (w * cos))
        new_h = int((h * cos) + (w * sin))

        M[0, 2] += (new_w / 2) - cx
        M[1, 2] += (new_h / 2) - cy

        result = cv2.warpAffine(
            img,
            M,
            (new_w, new_h),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(255, 255, 255)
        )

    else:
        result = img

    out = os.path.join(
        workdir,
        f"fixed-{page_no:03d}.jpg"
    )

    if not cv2.imwrite(
        out,
        result,
        [cv2.IMWRITE_JPEG_QUALITY, 95]
    ):
        print(f"FEHLER beim Schreiben von Seite {page_no}", file=sys.stderr)
        sys.exit(1)

    if reliable:
        print(f"Seite {page_no:>3}: Winkel {angle:+6.2f}°")
    else:
        print(f"Seite {page_no:>3}: kein zuverlässiger Winkel -> unverändert")

