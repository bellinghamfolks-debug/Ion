#!/usr/bin/env python3
"""Rasterize ONE PDF page to a high-resolution JPEG (base64 on stdout).

This mirrors the Basir Android app's PdfPageRasterizer: the page is rendered to
an image and that IMAGE is sent to Gemini — so the model reads the actual pixels
(faithful, verbatim) instead of a garbled/symbolic embedded text layer. Basir's
v3.4 architecture removed structured JSON schemas entirely and relies on a single
natural transcription call over this rendered image.

Usage:  python3 render_page.py <pdf_path> <page_index_0_based>

Prints base64(JPEG) to stdout. Exit 20 = could not render (caller falls back).
"""
import base64
import os
import sys

TARGET_LONG_EDGE = 3072     # px, like Basir
MAX_PIXELS = 16_000_000     # cap total pixels
JPEG_QUALITY = 92           # high quality so small Arabic glyphs stay crisp


def main():
    if len(sys.argv) < 3:
        sys.exit(20)
    path = sys.argv[1]
    try:
        idx = int(sys.argv[2])
    except ValueError:
        sys.exit(20)

    # Silence MuPDF's advisory prints on fd 1 while we work.
    real = os.dup(1)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)

    def emit(jpeg_bytes):
        os.dup2(real, 1)
        os.write(real, base64.b64encode(jpeg_bytes))
        sys.exit(0)

    def unavailable():
        os.dup2(real, 1)
        sys.exit(20)

    try:
        import fitz  # PyMuPDF
    except Exception:
        unavailable()

    try:
        doc = fitz.open(path)
    except Exception:
        unavailable()
    if idx < 0 or idx >= doc.page_count:
        unavailable()

    page = doc.load_page(idx)
    rect = page.rect
    long_edge = max(rect.width, rect.height) or 1.0
    scale = TARGET_LONG_EDGE / long_edge
    scale = max(1.5, min(4.0, scale))
    if (rect.width * scale) * (rect.height * scale) > MAX_PIXELS and rect.width and rect.height:
        scale = (MAX_PIXELS / (rect.width * rect.height)) ** 0.5

    try:
        pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
    except Exception:
        unavailable()
    # Prefer high-quality JPEG; fall back across API variants, then PNG. The Node
    # side detects the real format from the magic bytes.
    img = None
    for attempt in (
        lambda: pix.tobytes(output="jpg", jpg_quality=JPEG_QUALITY),
        lambda: pix.tobytes(output="jpeg"),
        lambda: pix.tobytes(output="png"),
    ):
        try:
            img = attempt()
            if img:
                break
        except Exception:
            continue
    if not img:
        unavailable()
    emit(img)


if __name__ == "__main__":
    main()
