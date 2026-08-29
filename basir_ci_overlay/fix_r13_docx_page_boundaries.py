#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/DocxBuilder.swift"
if not path.is_file():
    raise SystemExit("R13 DOCX boundary fix: DocxBuilder.swift is missing")

text = path.read_text(encoding="utf-8")

# Idempotent fast path. A previous overlay/build may already have installed the
# section-aware validator.
if (
    'let explicitPages = occurrences(of: "<w:br w:type=\\"page\\"/>", in: xml) + 1' in text
    and 'let sectionPages = occurrences(of: "<w:sectPr", in: xml)' in text
    and 'let preservedPages = max(explicitPages, sectionPages)' in text
):
    print("BASIR_DOCX_BOUNDARY_VALIDATION=PAGE_BREAKS_OR_SECTIONS")
    raise SystemExit(0)

# Do not depend on the entire validator block being byte-for-byte identical.
# R10/R11/R12 reconstruct the Swift source before this overlay runs, and those
# overlays may legitimately change indentation or the surrounding error text.
# Instead locate the semantic page-break counter and patch only the three
# expressions that matter.
lines = text.splitlines(keepends=True)
candidates: list[tuple[int, str, str]] = []
for index, line in enumerate(lines):
    if (
        "occurrences(of:" in line
        and 'w:type=\\"page\\"' in line
        and "in: xml" in line
        and "+ 1" in line
    ):
        match = re.search(r"^(?P<indent>\s*)let\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=", line)
        if not match:
            continue
        nearby = "".join(lines[max(0, index - 10):index])
        if re.search(r"if\s+expectedPages\s*>\s*0\s*\{", nearby):
            candidates.append((index, match.group("indent"), match.group("name")))

if len(candidates) != 1:
    diagnostic = []
    for index, line in enumerate(lines):
        if "expectedPages" in line or "w:type" in line or "page bound" in line.lower():
            diagnostic.append(f"L{index + 1}: {line.rstrip()}")
        if len(diagnostic) >= 18:
            break
    details = "\n".join(diagnostic) if diagnostic else "<no relevant validator lines found>"
    raise SystemExit(
        "R13 DOCX boundary fix: expected exactly one semantic page-break counter "
        f"inside expectedPages validation, found {len(candidates)}.\n{details}"
    )

index, indent, old_name = candidates[0]
newline = "\r\n" if lines[index].endswith("\r\n") else "\n"
lines[index:index + 1] = [
    f'{indent}let explicitPages = occurrences(of: "<w:br w:type=\\"page\\"/>", in: xml) + 1{newline}',
    f'{indent}let sectionPages = occurrences(of: "<w:sectPr", in: xml){newline}',
    f'{indent}let preservedPages = max(explicitPages, sectionPages){newline}',
]

# The insertion adds two lines, so search forward by semantics rather than by
# fixed offsets. Keep the edit confined to the expectedPages validator.
condition_changed = False
message_changed = False
for j in range(index + 3, min(len(lines), index + 30)):
    if not condition_changed and re.search(
        rf"\bif\s+{re.escape(old_name)}\s*<\s*expectedPages\s*\{{", lines[j]
    ):
        lines[j] = re.sub(
            rf"\bif\s+{re.escape(old_name)}\s*<\s*expectedPages\s*\{{",
            "if preservedPages < expectedPages {",
            lines[j],
            count=1,
        )
        condition_changed = True
        continue

    if condition_changed and not message_changed and f"\\({old_name})" in lines[j]:
        lines[j] = lines[j].replace(f"\\({old_name})", "\\(preservedPages)", 1)
        lines[j] = lines[j].replace(
            " page boundaries were preserved.",
            " source page boundaries were preserved.",
            1,
        )
        message_changed = True

    if condition_changed and message_changed:
        break

if not condition_changed:
    raise SystemExit(
        f"R13 DOCX boundary fix: found page counter '{old_name}' but not its expectedPages guard"
    )
if not message_changed:
    raise SystemExit(
        f"R13 DOCX boundary fix: found page counter '{old_name}' but not its validation error message"
    )

path.write_text("".join(lines), encoding="utf-8")
final = path.read_text(encoding="utf-8")
required = (
    'let explicitPages = occurrences(of: "<w:br w:type=\\"page\\"/>", in: xml) + 1',
    'let sectionPages = occurrences(of: "<w:sectPr", in: xml)',
    'let preservedPages = max(explicitPages, sectionPages)',
    "if preservedPages < expectedPages {",
    "\\(preservedPages)",
)
missing = [marker for marker in required if marker not in final]
if missing:
    raise SystemExit("R13 DOCX boundary fix missing: " + ", ".join(missing))

print("BASIR_DOCX_BOUNDARY_VALIDATION=PAGE_BREAKS_OR_SECTIONS")
