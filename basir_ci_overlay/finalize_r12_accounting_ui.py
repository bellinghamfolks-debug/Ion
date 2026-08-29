#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Views/JobView.swift"
text = path.read_text(encoding="utf-8")
text = text.replace(
    "                if partial, !job.failedItems.isEmpty {",
    "                if !job.failedItems.isEmpty {",
    1,
)
if "if partial, !job.failedItems.isEmpty" in text:
    raise SystemExit("R12 fallback UI still hides fallback pages on completed jobs")
if "if !job.failedItems.isEmpty" not in text:
    raise SystemExit("R12 fallback UI marker not found")
path.write_text(text, encoding="utf-8")
print("BASIR_R12_FALLBACK_UI=ALWAYS_VISIBLE")
