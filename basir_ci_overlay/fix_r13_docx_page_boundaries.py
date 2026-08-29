#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/DocxBuilder.swift"
if not path.is_file():
    raise SystemExit("R13 DOCX boundary fix: DocxBuilder.swift is missing")

text = path.read_text(encoding="utf-8")
old = '''        if expectedPages > 0 {
            let pages = occurrences(of: "<w:br w:type=\"page\"/>", in: xml) + 1
            if pages < expectedPages {
                throw BasirError.conversionFailed("Only \\(pages) of \\(expectedPages) page boundaries were preserved.")
            }
        }
'''
new = '''        if expectedPages > 0 {
            // Basir preserves exact source-page identity primarily with one Word
            // section per retained source page so each footer can carry the real
            // source page number. Counting only explicit <w:br type="page"> tags
            // falsely rejects valid files that use section boundaries instead.
            let explicitPages = occurrences(of: "<w:br w:type=\"page\"/>", in: xml) + 1
            let sectionPages = occurrences(of: "<w:sectPr", in: xml)
            let preservedPages = max(explicitPages, sectionPages)
            if preservedPages < expectedPages {
                throw BasirError.conversionFailed(
                    "Only \\(preservedPages) of \\(expectedPages) source page boundaries were preserved."
                )
            }
        }
'''

if old in text:
    text = text.replace(old, new, 1)
elif "let sectionPages = occurrences(of: \"<w:sectPr\"" not in text:
    raise SystemExit("R13 DOCX boundary fix: expected validator block was not found")

path.write_text(text, encoding="utf-8")
final = path.read_text(encoding="utf-8")
for marker in (
    'let explicitPages = occurrences(of: "<w:br w:type=\\"page\\"/>", in: xml) + 1',
    'let sectionPages = occurrences(of: "<w:sectPr", in: xml)',
    'let preservedPages = max(explicitPages, sectionPages)',
):
    if marker not in final:
        raise SystemExit(f"R13 DOCX boundary fix missing {marker}")

print("BASIR_DOCX_BOUNDARY_VALIDATION=PAGE_BREAKS_OR_SECTIONS")
