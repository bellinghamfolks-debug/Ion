#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy_path = root / "BasirConvert/Services/ProxyClient.swift"
proxy = proxy_path.read_text(encoding="utf-8")


def replace_once(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"R11 {label}: expected exactly one match, found {count}")
    return content.replace(old, new, 1)


proxy = replace_once(
    proxy,
    '"nonexpanding_image_alt_text", "resumable_jobs"',
    '"nonexpanding_image_alt_text", "resumable_jobs",\n'
    '            "universal_docx_validation", "lossless_degraded_results"',
    "universal capabilities",
)
proxy = replace_once(proxy, 'minimum: "2.7.0"', 'minimum: "2.8.0"', "service minimum")
proxy = replace_once(proxy, "required=2.7.0", "required=2.8.0", "minimum diagnostic")
proxy = replace_once(
    proxy,
    '                guard terminalQuality == "passed", failedItems.isEmpty else {',
    '                guard terminalQuality == "passed" else {',
    "lossless fallback acceptance",
)

old_page_guard = '''                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages,
                          Self.integer(qualityMetrics["rendered_pages"]) == expectedResultPages else {
                        throw BasirError.invalidResponse("The quality manifest page geometry is inconsistent.")
                    }
'''
new_page_guard = '''                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages else {
                        throw BasirError.invalidResponse("The quality manifest source-page accounting is inconsistent.")
                    }
'''
proxy = replace_once(proxy, old_page_guard, new_page_guard, "source-page contract")

artifact_guard = '''                let artifactBytes = Self.integer(qualityMetrics["artifact_bytes"]) ?? 0
                let artifactMembers = Self.integer(qualityMetrics["artifact_members"]) ?? 0
                let artifactText = Self.integer(qualityMetrics["artifact_text_characters"]) ?? 0
                let artifactTables = Self.integer(qualityMetrics["artifact_tables"]) ?? 0
                let artifactDrawings = Self.integer(qualityMetrics["artifact_drawings"]) ?? 0
                let artifactMissingAlt = Self.integer(qualityMetrics["artifact_missing_alt_text"]) ?? -1
                guard artifactBytes > 0, artifactMembers >= 3, artifactMissingAlt == 0,
                      artifactText > 0 || artifactTables > 0 || artifactDrawings > 0 else {
                    throw BasirError.invalidResponse("The quality manifest Word-package integrity is inconsistent.")
                }
'''
proxy = replace_once(
    proxy,
    '                if expectedSourcePages > 0 {\n',
    artifact_guard + '                if expectedSourcePages > 0 {\n',
    "universal artifact manifest",
)
proxy = proxy.replace(
    "// BASIR_RELIABILITY_GUARD_R8: server 2.7.0 + adaptive repair + fail-closed manifest",
    "// BASIR_RELIABILITY_GUARD_R11: server 2.8.0 + universal artifact integrity + lossless degraded layout",
    1,
)

proxy_path.write_text(proxy, encoding="utf-8")

checks = (
    "BASIR_RELIABILITY_GUARD_R11",
    'minimum: "2.8.0"',
    '"universal_docx_validation"',
    '"lossless_degraded_results"',
    'guard terminalQuality == "passed"',
    'qualityMetrics["artifact_missing_alt_text"]',
    'qualityMetrics["source_pages"]',
)
final = proxy_path.read_text(encoding="utf-8")
for marker in checks:
    if marker not in final:
        raise SystemExit(f"R11 reliability gate missing {marker!r}")
if "failedItems.isEmpty" in final:
    raise SystemExit("R11 still rejects verified full-page fallback results")
if 'qualityMetrics["rendered_pages"] == expectedResultPages' in final:
    raise SystemExit("R11 still treats renderer-dependent pagination as content loss")

print("BASIR_UNIVERSAL_RELIABILITY=LOSSLESS_DEGRADED_LAYOUT_R11")
