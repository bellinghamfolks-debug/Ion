#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy = (root / "BasirConvert/Services/ProxyClient.swift").read_text(encoding="utf-8")
required = [
    "BASIR_RELIABILITY_GUARD_R11",
    'minimum: "2.9.0"',
    "universal_docx_validation",
    "lossless_degraded_results",
    'guard terminalQuality == "passed"',
    'qualityMetrics["artifact_missing_alt_text"]',
    'qualityMetrics["source_pages"]',
    'qualityMetrics["source_page_accounting_exact"]',
    'qualityMetrics["source_page_numbering_exact"]',
    'qualityMetrics["fallback_page_numbers"]',
    "user_model_selection",
    "executed_model_reporting",
]
missing = [marker for marker in required if marker not in proxy]
if missing:
    raise SystemExit("R11 semantic compatibility gate missing: " + ", ".join(missing))
print("BASIR_UNIVERSAL_RELIABILITY=R11_PLUS_2_9_EXACT_ACCOUNTING")
