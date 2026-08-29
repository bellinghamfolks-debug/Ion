#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/DiagnosticLogger.swift"
text = path.read_text(encoding="utf-8")
text = text.replace("\\\\", "\\")
text = text.replace('\\"', '"')
path.write_text(text, encoding="utf-8")

if "\\\\(" in text:
    raise SystemExit("DiagnosticLogger still contains double-escaped Swift interpolation")
if '#\\"' in text or '\\"#' in text:
    raise SystemExit("DiagnosticLogger still contains escaped raw-string delimiters")
if 'record("SESSION START sourceType=\\(sourceType' not in text:
    raise SystemExit("DiagnosticLogger Swift interpolation normalization failed")

accounting = Path(__file__).resolve().parent / "enhance_r12_accounting_diagnostics.py"
subprocess.run([sys.executable, str(accounting), str(root)], check=True)

print("BASIR_DIAGNOSTIC_SWIFT_ESCAPES=OK")
