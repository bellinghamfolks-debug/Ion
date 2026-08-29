#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/DiagnosticLogger.swift"
text = path.read_text(encoding="utf-8")

old_signature = '''        let signature = "\\(progress.stage.rawValue)|\\(progress.current)|\\(progress.total)|\\(byteBucket)|\\(progress.succeeded)|\\(progress.failed)|\\(progress.detail ?? \"\")"
'''
new_signature = '''        let signature = "\\(progress.stage.rawValue)|\\(progress.current)|\\(progress.total)|\\(byteBucket)|\\(progress.succeeded)|\\(progress.failed)|\\(progress.skipped ?? 0)|\\(progress.detail ?? \"\")"
'''
if old_signature in text:
    text = text.replace(old_signature, new_signature, 1)
elif "progress.skipped ?? 0" not in text:
    raise SystemExit("R12 accounting diagnostics: progress signature anchor not found")

old_record = '''        record("PROGRESS stage=\\(progress.stage.rawValue) current=\\(progress.current) total=\\(progress.total) transferred=\\(progress.transferredBytes) totalBytes=\\(progress.totalBytes) succeeded=\\(progress.succeeded) failed=\\(progress.failed) detail=\\(progress.detail ?? \"\")")
'''
new_record = '''        record("PROGRESS stage=\\(progress.stage.rawValue) current=\\(progress.current) total=\\(progress.total) transferred=\\(progress.transferredBytes) totalBytes=\\(progress.totalBytes) succeeded=\\(progress.succeeded) failed=\\(progress.failed) skipped=\\(progress.skipped ?? 0) detail=\\(progress.detail ?? \"\")")
'''
if old_record in text:
    text = text.replace(old_record, new_record, 1)
elif "skipped=\\(progress.skipped ?? 0)" not in text:
    raise SystemExit("R12 accounting diagnostics: progress record anchor not found")

path.write_text(text, encoding="utf-8")
final = path.read_text(encoding="utf-8")
for marker in ("progress.skipped ?? 0", "skipped=\\(progress.skipped ?? 0)"):
    if marker not in final:
        raise SystemExit(f"R12 accounting diagnostics missing {marker}")
print("BASIR_DIAGNOSTICS=R12_EXACT_PAGE_ACCOUNTING")
