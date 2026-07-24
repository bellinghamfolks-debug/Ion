#!/usr/bin/env python3
"""Layout-preserving PDF -> DOCX conversion using pdf2docx (PyMuPDF-based).

Usage: python3 pdf2docx_convert.py <input.pdf> <output.docx>

Reconstructs the original layout (text runs with fonts/sizes/colors, tables,
images, positioning) as closely as possible — the "professional" path. Falls
back with a non-zero exit if pdf2docx isn't installed, so the Node server can
degrade to the accessible text pipeline.
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: pdf2docx_convert.py <in.pdf> <out.docx>\n")
        return 2
    inp, out = sys.argv[1], sys.argv[2]
    try:
        from pdf2docx import Converter
    except Exception as e:  # pragma: no cover - environment dependent
        sys.stderr.write(f"pdf2docx unavailable: {e}\n")
        return 3
    try:
        cv = Converter(inp)
        cv.convert(out)  # whole document; keeps layout, tables, images
        cv.close()
    except Exception as e:
        sys.stderr.write(f"conversion failed: {e}\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
