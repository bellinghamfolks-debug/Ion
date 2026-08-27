#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/ProxyClient.swift"
text = path.read_text(encoding="utf-8")

if "BASIR_RELIABILITY_GUARD_R8" not in text:
    old_required = '            "quality_manifest", "source_geometry_tables", "softmask_images"\n'
    new_required = '            "quality_manifest", "source_geometry_tables", "softmask_images",\n            "adaptive_fidelity_repair"\n'
    if text.count(old_required) != 1:
        raise SystemExit(f"R8 capability patch expected one match, found {text.count(old_required)}")
    text = text.replace(old_required, new_required, 1)

    old_version = 'serverVersionAtLeast(serverStatus.apiVersion, minimum: "2.5.1")'
    if old_version not in text:
        raise SystemExit("R8 minimum-version guard from R7 was not found")
    text = text.replace(old_version, 'serverVersionAtLeast(serverStatus.apiVersion, minimum: "2.6.0")')
    text = text.replace('required=2.5.1', 'required=2.6.0')

    parse_anchor = '''            let qualityWarnings = (object?["quality_warnings"] as? [String]) ?? []
'''
    parse_replacement = '''            let qualityWarnings = (object?["quality_warnings"] as? [String]) ?? []
            let qualityMetrics = (object?["quality_metrics"] as? [String: Any]) ?? [:]
'''
    if text.count(parse_anchor) != 1:
        raise SystemExit(f"R8 quality-metrics parser expected one match, found {text.count(parse_anchor)}")
    text = text.replace(parse_anchor, parse_replacement, 1)

    log_anchor = '''                logger.record("QUALITY terminal status=\\(terminalQuality) score=\\(qualityScore ?? -1) warnings=\\(qualityWarnings.joined(separator: ","))")
'''
    log_replacement = '''                let qualityMetricKeys = qualityMetrics.keys.sorted().joined(separator: ",")
                logger.record("QUALITY terminal status=\\(terminalQuality) score=\\(qualityScore ?? -1) warnings=\\(qualityWarnings.joined(separator: ",")) metrics=\\(qualityMetricKeys)")
'''
    if text.count(log_anchor) != 1:
        raise SystemExit(f"R8 terminal quality log expected one match, found {text.count(log_anchor)}")
    text = text.replace(log_anchor, log_replacement, 1)

    marker_anchor = '    // BASIR_FIDELITY_GUARD_R7\n'
    if text.count(marker_anchor) != 1:
        raise SystemExit("R8 could not find R7 marker")
    text = text.replace(
        marker_anchor,
        marker_anchor + '    // BASIR_RELIABILITY_GUARD_R8: server 2.6.0 + adaptive repair + fail-closed manifest\n',
        1,
    )

path.write_text(text, encoding="utf-8")

checks = [
    "BASIR_RELIABILITY_GUARD_R8",
    'minimum: "2.6.0"',
    '"adaptive_fidelity_repair"',
    'quality_metrics',
    'qualityMetricKeys',
    'guard terminalQuality == "passed"',
    'expectedPages: expectedResultPages',
]
final = path.read_text(encoding="utf-8")
for needle in checks:
    if needle not in final:
        raise SystemExit(f"R8 reliability gate failed: {needle!r} missing")
if 'minimum: "2.5.1"' in final:
    raise SystemExit("R8 stale 2.5.1 minimum remains")

print("BASIR_RELIABILITY_GUARD=SERVER_2_6_0_ADAPTIVE_FAIL_CLOSED_R8")
