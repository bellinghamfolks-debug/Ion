#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
overlay = Path(__file__).resolve().parent
compat = overlay / "enforce_r11_r12_compat.py"
refine = overlay / "refine_r12_exact_gate.py"
boundaries = overlay / "fix_r13_docx_page_boundaries.py"
if not compat.is_file():
    raise SystemExit("R11/R12 compatibility guard is missing")
if not refine.is_file():
    raise SystemExit("R12 exact-source gate refinement is missing")
if not boundaries.is_file():
    raise SystemExit("R13 DOCX page-boundary validator fix is missing")
subprocess.run([sys.executable, str(compat), str(root)], check=True)
subprocess.run([sys.executable, str(refine), str(root)], check=True)
subprocess.run([sys.executable, str(boundaries), str(root)], check=True)
print("BASIR_QUALITY_GUARD=R11_R12_EXACT_SOURCE_COMPAT_SECTION_AWARE")
