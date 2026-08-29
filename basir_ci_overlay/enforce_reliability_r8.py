#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy = (root / "BasirConvert/Services/ProxyClient.swift").read_text(encoding="utf-8")
required = [
    "BASIR_RELIABILITY_GUARD_R8",
    'minimum: "2.8.0"',
    "adaptive_fidelity_repair",
    "quality_metrics",
    'guard terminalQuality == "passed"',
]
missing = [marker for marker in required if marker not in proxy]
if missing:
    raise SystemExit("R8 semantic compatibility gate missing: " + ", ".join(missing))
print("BASIR_RELIABILITY_GUARD=R8_SATISFIED_BY_R11_R12_SEMANTIC_COMPAT")
