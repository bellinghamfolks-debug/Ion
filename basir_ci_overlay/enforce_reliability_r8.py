#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy = (root / "BasirConvert/Services/ProxyClient.swift").read_text(encoding="utf-8")

required = [
    "BASIR_RELIABILITY_GUARD_R8",
    "adaptive_fidelity_repair",
    "quality_metrics",
    'guard terminalQuality == "passed"',
]
missing = [marker for marker in required if marker not in proxy]
if missing:
    raise SystemExit("R8 semantic compatibility gate missing: " + ", ".join(missing))

# R8 originally required the literal source string `minimum: "2.8.0"`.
# That made every legitimate server-minimum upgrade fail CI even though a newer
# minimum is semantically stronger. Parse the declared minimum instead and
# require it to be at least the R8 contract floor.
match = re.search(r'minimum:\s*"(\d+)\.(\d+)\.(\d+)"', proxy)
if not match:
    raise SystemExit("R8 semantic compatibility gate missing server minimum declaration")
minimum = tuple(int(value) for value in match.groups())
required_floor = (2, 8, 0)
if minimum < required_floor:
    rendered = ".".join(str(value) for value in minimum)
    raise SystemExit(
        f"R8 semantic compatibility gate requires server minimum >= 2.8.0; found {rendered}"
    )

print(
    "BASIR_RELIABILITY_GUARD=R8_SATISFIED_BY_NEWER_SEMANTIC_COMPAT "
    + "server_minimum="
    + ".".join(str(value) for value in minimum)
)
