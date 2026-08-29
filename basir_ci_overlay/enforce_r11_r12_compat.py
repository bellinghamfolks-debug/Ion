#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy_path = root / "BasirConvert/Services/ProxyClient.swift"
proxy = proxy_path.read_text(encoding="utf-8")

capabilities = [
    "job_api", "direct_storage_upload", "checksums",
    "quality_manifest", "source_geometry_tables", "softmask_images",
    "adaptive_fidelity_repair", "pdf_structural_geometry",
    "geometry_validated_native_tables", "source_page_layout",
    "nonexpanding_image_alt_text", "resumable_jobs",
    "universal_docx_validation", "lossless_degraded_results",
    "user_model_selection", "executed_model_reporting",
]

required_pattern = r'(?m)^        let required = Set\(\[[^\n]*\]\)\n'
required_match = re.search(required_pattern, proxy)
if not required_match:
    raise SystemExit("R11/R12 required-capabilities set not found")
required_line = "        let required = Set([" + ", ".join(f'\"{value}\"' for value in capabilities) + "])\n"
proxy = proxy[:required_match.start()] + required_line + proxy[required_match.end():]

required_guard = '''        guard required.isSubset(of: serverStatus.capabilities) else {
            throw BasirError.invalidResponse("The server needs an update before it can accept this file.")
        }
'''
if required_guard not in proxy:
    raise SystemExit("R11/R12 capability guard not found")
version_guard = '''        guard Self.serverVersionAtLeast(serverStatus.apiVersion, minimum: "2.8.0") else {
            logger.record("QUALITY rejected stale processing service version=\\(serverStatus.apiVersion) required=2.8.0")
            throw BasirError.invalidResponse("خدمة المعالجة لم تُحدّث بعد إلى محرك الجودة المطلوب. أعد المحاولة بعد اكتمال التحديث.")
        }
'''
if 'minimum: "2.8.0"' not in proxy:
    proxy = proxy.replace(required_guard, required_guard + version_guard, 1)

source_size = '        let sourceSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)\n'
quality_source = '''        let expectedSourcePages: Int = {
            guard sourceURL.pathExtension.lowercased() == "pdf",
                  let metadata = try? DocumentInspector.inspect(sourceURL, includeChecksum: false),
                  let total = metadata.itemCount, total > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: options.pageSelection, total: total).count) ?? total
        }()
        logger.record("QUALITY sourcePages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection)")
'''
if "let expectedSourcePages:" not in proxy:
    if source_size not in proxy:
        raise SystemExit("R11/R12 source-size anchor not found")
    proxy = proxy.replace(source_size, source_size + quality_source, 1)

state_anchor = '        var completed = false\n        var lastServerProgress: ConversionProgress?\n'
state_replacement = '''        var completed = false
        var validatedExpectedTables = 0
        var validatedExpectedImages = 0
        var lastServerProgress: ConversionProgress?
'''
if "validatedExpectedTables" not in proxy:
    if state_anchor not in proxy:
        raise SystemExit("R11/R12 poll-state anchor not found")
    proxy = proxy.replace(state_anchor, state_replacement, 1)

object_anchor = '            let object = (try JSONSerialization.jsonObject(with: statusData)) as? [String: Any]\n'
quality_parse = '''            let qualityStatus = (object?["quality_status"] as? String)?.lowercased()
            let qualityScore = Self.doubleValue(object?["quality_score"])
            let qualityWarnings = (object?["quality_warnings"] as? [String]) ?? []
            let qualityMetrics = (object?["quality_metrics"] as? [String: Any]) ?? [:]
'''
if "let qualityMetrics =" not in proxy:
    if object_anchor not in proxy:
        raise SystemExit("R11/R12 status-object anchor not found")
    proxy = proxy.replace(object_anchor, object_anchor + quality_parse, 1)

terminal_anchor = '            if ["completed", "complete", "done", "succeeded", "partial"].contains(state) {\n'
terminal_replacement = '''            if ["completed", "complete", "done", "succeeded", "partial"].contains(state) {
                guard let terminalQuality = qualityStatus else {
                    logger.record("QUALITY terminal manifest missing")
                    throw BasirError.invalidResponse("تعذر التحقق من جودة المستند الناتج. لم يتم اعتماد الملف.")
                }
                let qualityMetricKeys = qualityMetrics.keys.sorted().joined(separator: ",")
                logger.record("QUALITY terminal status=\\(terminalQuality) score=\\(qualityScore ?? -1) warnings=\\(qualityWarnings.joined(separator: ",")) metrics=\\(qualityMetricKeys)")
                guard terminalQuality == "passed" else {
                    throw BasirError.conversionFailed("لم يصل المستند الناتج إلى مستوى الجودة الآمن للاعتماد. لم يتم حفظ نتيجة ناقصة أو مشوهة.")
                }
                if expectedSourcePages > 0 {
                    let expectedResultPages = max(0, expectedSourcePages - skippedItems.count)
                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages else {
                        throw BasirError.invalidResponse("The quality manifest source-page accounting is inconsistent.")
                    }
                    let expectedTables = Self.integer(qualityMetrics["expected_native_tables"]) ?? 0
                    let sourceUniqueImages = Self.integer(qualityMetrics["source_unique_images"]) ?? 0
                    validatedExpectedTables = max(0, expectedTables)
                    validatedExpectedImages = max(0, sourceUniqueImages)
                }
                let artifactBytes = Self.integer(qualityMetrics["artifact_bytes"]) ?? 0
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
if "QUALITY terminal manifest missing" not in proxy:
    if terminal_anchor not in proxy:
        raise SystemExit("R11/R12 terminal-state anchor not found")
    proxy = proxy.replace(terminal_anchor, terminal_replacement, 1)

verify_call = '        try verifyAndMove(temporary: temporary, response: downloadResponse, outputURL: outputURL)\n'
verify_call_replacement = '''        let expectedResultPages = max(0, expectedSourcePages - outcome.skippedBlankItems.count)
        try verifyAndMove(
            temporary: temporary, response: downloadResponse, outputURL: outputURL,
            expectedPages: expectedResultPages, expectedTables: validatedExpectedTables,
            expectedImages: validatedExpectedImages
        )
'''
if "expectedTables: validatedExpectedTables" not in proxy:
    if verify_call not in proxy:
        raise SystemExit("R11/R12 verifyAndMove call anchor not found")
    proxy = proxy.replace(verify_call, verify_call_replacement, 1)

verify_signature = '    private func verifyAndMove(temporary: URL, response: HTTPURLResponse, outputURL: URL) throws {\n'
verify_signature_replacement = '''    private func verifyAndMove(
        temporary: URL, response: HTTPURLResponse, outputURL: URL,
        expectedPages: Int, expectedTables: Int, expectedImages: Int
    ) throws {
'''
if "expectedPages: Int, expectedTables: Int, expectedImages: Int" not in proxy:
    if verify_signature not in proxy:
        raise SystemExit("R11/R12 verifyAndMove signature anchor not found")
    proxy = proxy.replace(verify_signature, verify_signature_replacement, 1)
    proxy = proxy.replace(
        "            try DocxBuilder.validate(url: temporary)\n",
        "            try DocxBuilder.validate(url: temporary, expectedPages: expectedPages, expectedTables: expectedTables, expectedImages: expectedImages)\n",
        1,
    )

integer_helper = '''    private static func integer(_ value: Any?) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
'''
if "private static func doubleValue" not in proxy:
    if integer_helper not in proxy:
        raise SystemExit("R11/R12 numeric helper anchor not found")
    proxy = proxy.replace(
        integer_helper,
        integer_helper + '''
    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let text = value as? String { return Double(text) }
        return nil
    }
''',
        1,
    )

http_marker = '    private static func validateHTTP(_ response: HTTPURLResponse, data: Data) throws {\n'
if "private static func serverVersionAtLeast" not in proxy:
    version_helper = '''    private static func serverVersionAtLeast(_ actual: String, minimum: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.split(separator: "-", maxSplits: 1).first.map(String.init)?
                .split(separator: ".").prefix(3).map { Int($0) ?? 0 } ?? []
        }
        var lhs = parts(actual), rhs = parts(minimum)
        while lhs.count < 3 { lhs.append(0) }
        while rhs.count < 3 { rhs.append(0) }
        for index in 0..<3 {
            if lhs[index] != rhs[index] { return lhs[index] > rhs[index] }
        }
        return true
    }

'''
    if http_marker not in proxy:
        raise SystemExit("R11/R12 HTTP helper anchor not found")
    proxy = proxy.replace(http_marker, version_helper + http_marker, 1)

if "BASIR_RELIABILITY_GUARD_R11" not in proxy:
    if http_marker not in proxy:
        raise SystemExit("R11/R12 marker anchor not found")
    markers = '''    // BASIR_FIDELITY_GUARD_R7
    // BASIR_RELIABILITY_GUARD_R8: adaptive fidelity repair
    // BASIR_RELIABILITY_GUARD_R9: resumable jobs + structural geometry
    // BASIR_RELIABILITY_GUARD_R11: server 2.8.0 + universal artifact integrity + lossless degraded layout
'''
    proxy = proxy.replace(http_marker, markers + http_marker, 1)

proxy_path.write_text(proxy, encoding="utf-8")

checks = [
    "BASIR_FIDELITY_GUARD_R7",
    "BASIR_RELIABILITY_GUARD_R11",
    'minimum: "2.8.0"',
    "adaptive_fidelity_repair",
    "pdf_structural_geometry",
    "geometry_validated_native_tables",
    "resumable_jobs",
    "universal_docx_validation",
    "lossless_degraded_results",
    "user_model_selection",
    "executed_model_reporting",
    "quality_metrics",
    'qualityMetrics["artifact_missing_alt_text"]',
    "Idempotency-Key",
    "preferred_model",
]
final = proxy_path.read_text(encoding="utf-8")
missing = [marker for marker in checks if marker not in final]
if missing:
    raise SystemExit("R11+R12 compatibility gate missing: " + ", ".join(missing))

print("BASIR_RELIABILITY_GUARD=R11_PLUS_R12_SEMANTIC_COMPAT")
