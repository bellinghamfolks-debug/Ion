#!/usr/bin/env python3
"""Faithful per-page text extraction using PyMuPDF (fitz).

Why this exists: the JavaScript pdfjs path extracts Arabic text in the wrong
order and drops the spaces between words, producing scrambled output (Arabic
glyphs mixed with latin gibberish). PyMuPDF returns text in proper logical
reading order with correct spacing and far better glyph->Unicode recovery, so
Arabic (and every RTL/bidi document) comes out readable and verbatim — no AI,
so nothing is invented or altered.

Usage:  python3 extract_page.py <pdf_path> <page_index_0_based> [--tables]

Prints the page's text to stdout (UTF-8). With --tables, real tables are
detected and emitted as GitHub-style Markdown pipe tables (| a | b |) in place,
which the Node DOCX builder turns into real Word tables. Exit code is always 0;
a page with no text layer (a scanned image) prints nothing so the caller can
fall back to AI vision.

MuPDF's C layer prints advisory notices to file descriptor 1 (stdout), which
would corrupt the captured result, so we redirect fd 1 to /dev/null for the
whole extraction and write the final text to the original stdout at the end.
"""
import os
import sys


def rows_to_markdown(rows):
    """Turn a table's rows (list of lists of cell strings) into Markdown."""
    cleaned = []
    for r in rows:
        cells = [(c or "").replace("\n", " ").strip() for c in r]
        if any(cells):
            cleaned.append(cells)
    if not cleaned:
        return ""
    cols = max(len(r) for r in cleaned)
    out = []
    header = cleaned[0] + [""] * (cols - len(cleaned[0]))
    out.append("| " + " | ".join(header) + " |")
    out.append("|" + "|".join(["---"] * cols) + "|")
    for r in cleaned[1:]:
        r = r + [""] * (cols - len(r))
        out.append("| " + " | ".join(r) + " |")
    return "\n".join(out)


def main():
    if len(sys.argv) < 3:
        sys.exit(0)
    path = sys.argv[1]
    try:
        page_index = int(sys.argv[2])
    except ValueError:
        sys.exit(0)
    want_tables = "--tables" in sys.argv[3:]

    # Preserve the real stdout, then point fd 1 at /dev/null so MuPDF's advisory
    # prints never mix into our output. We restore it before writing the result.
    real_stdout_fd = os.dup(1)
    devnull_fd = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull_fd, 1)

    def emit(text):
        os.dup2(real_stdout_fd, 1)
        os.write(real_stdout_fd, text.encode("utf-8"))
        sys.exit(0)

    try:
        import fitz  # PyMuPDF
    except Exception:
        # PyMuPDF not installed — let the caller fall back to the JS path.
        emit("")

    try:
        doc = fitz.open(path)
    except Exception:
        emit("")
    if page_index < 0 or page_index >= doc.page_count:
        emit("")
    page = doc.load_page(page_index)

    # Collect tables (with their vertical position) so we can interleave them
    # with the surrounding prose in the correct reading order.
    table_items = []  # (top_y, bbox, markdown)
    if want_tables:
        try:
            finder = page.find_tables()
            for t in finder.tables:
                md = rows_to_markdown(t.extract())
                if md:
                    table_items.append((t.bbox[1], fitz.Rect(t.bbox), md))
        except Exception:
            table_items = []

    def in_a_table(rect):
        for _, bbox, _ in table_items:
            # A block belongs to a table if it is mostly inside the table bbox.
            inter = rect & bbox
            if inter.is_valid and inter.get_area() > 0.5 * rect.get_area():
                return True
        return False

    # Text blocks in reading order. Blocks that fall inside a detected table are
    # skipped (the Markdown table already carries their text).
    pieces = []  # (top_y, text)
    try:
        blocks = page.get_text("blocks")
    except Exception:
        blocks = []
    for b in blocks:
        x0, y0, x1, y1, text = b[0], b[1], b[2], b[3], b[4]
        text = (text or "").strip()
        if not text:
            continue
        try:
            rect = fitz.Rect(x0, y0, x1, y1)
            if table_items and in_a_table(rect):
                continue
        except Exception:
            pass
        pieces.append((y0, text))

    for top_y, _, md in table_items:
        pieces.append((top_y, md))

    pieces.sort(key=lambda p: p[0])
    out = "\n".join(p[1] for p in pieces).strip()
    emit(out)


if __name__ == "__main__":
    main()
