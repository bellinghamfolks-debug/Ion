#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
path = root / "BasirConvert/Services/ProxyClient.swift"
text = path.read_text(encoding="utf-8")

old = '''                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages,
                          accountingExact == true,
                          numberingExact == true else {
                        throw BasirError.invalidResponse("The quality manifest source-page identity or numbering is inconsistent.")
                    }
'''
new = '''                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages else {
                        throw BasirError.invalidResponse("The quality manifest source-page accounting is inconsistent.")
                    }
                    let requiresExactSourceIdentity = options.operation == .convert && options.outputMode != .simple
                    if requiresExactSourceIdentity {
                        guard accountingExact == true, numberingExact == true else {
                            throw BasirError.invalidResponse("The quality manifest source-page identity or numbering is inconsistent.")
                        }
                    }
'''
if old in text:
    text = text.replace(old, new, 1)
elif "let requiresExactSourceIdentity" not in text:
    raise SystemExit("R12 exact gate refinement anchor not found")

path.write_text(text, encoding="utf-8")
final = path.read_text(encoding="utf-8")
for marker in (
    "let requiresExactSourceIdentity = options.operation == .convert && options.outputMode != .simple",
    'qualityMetrics["source_page_accounting_exact"]',
    'qualityMetrics["source_page_numbering_exact"]',
):
    if marker not in final:
        raise SystemExit(f"R12 exact gate refinement missing {marker}")
print("BASIR_EXACT_GATE=FAITHFUL_CONVERSION_ONLY")
