#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
compat = Path(__file__).with_name("enforce_r11_r12_compat.py")
if not compat.is_file():
    raise SystemExit("R11/R12 compatibility guard is missing")
subprocess.run([sys.executable, str(compat), str(root)], check=True)
print("BASIR_QUALITY_GUARD=R11_R12_SEMANTIC_COMPAT")
