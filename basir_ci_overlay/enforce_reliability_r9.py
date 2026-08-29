#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy = (root / "BasirConvert/Services/ProxyClient.swift").read_text(encoding="utf-8")
view_model = (root / "BasirConvert/ViewModels/AppViewModel.swift").read_text(encoding="utf-8")
required_proxy = [
    "BASIR_RELIABILITY_GUARD_R9",
    "pdf_structural_geometry",
    "geometry_validated_native_tables",
    "resumable_jobs",
    "Idempotency-Key",
    "preferred_model",
]
missing = [marker for marker in required_proxy if marker not in proxy]
if missing:
    raise SystemExit("R9 semantic compatibility gate missing: " + ", ".join(missing))
if "requestID: snapshot.requestID" not in view_model:
    raise SystemExit("R9 semantic compatibility gate missing stable requestID forwarding")
print("BASIR_RELIABILITY_GUARD=R9_SATISFIED_BY_R11_R12_SEMANTIC_COMPAT")
