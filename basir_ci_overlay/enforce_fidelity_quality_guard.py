#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def load(rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8")


def save(rel: str, text: str) -> None:
    (root / rel).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# The service and the client both enforce fidelity. The client refuses stale
# revisions, missing quality manifests and every terminal result that the server
# could not classify as fully passed. This is intentionally fail-closed: a file
# is never saved merely because the HTTP transaction succeeded.
rel = "BasirConvert/Services/ProxyClient.swift"
s = load(rel)

if "BASIR_FIDELITY_GUARD_R7" not in s:
    s = replace_once(
        s,
        '        let required = Set(["job_api", "direct_storage_upload", "checksums"])\n',
        '''        let required = Set([
            "job_api", "direct_storage_upload", "checksums",
            "quality_manifest", "source_geometry_tables", "softmask_images"
        ])
        guard Self.serverVersionAtLeast(serverStatus.apiVersion, minimum: "2.5.1") else {
            logger.record("QUALITY rejected stale processing service version=\\(serverStatus.apiVersion) required=2.5.1")
            throw BasirError.invalidResponse("خدمة المعالجة لم تُحدّث بعد إلى محرك الجودة المطلوب. أعد المحاولة بعد اكتمال التحديث.")
        }
''',
        "minimum processing version and capabilities",
    )

    source_size = '        let sourceSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)\n'
    quality_block = '''        let expectedSourcePages: Int = {
            guard sourceURL.pathExtension.lowercased() == "pdf",
                  let metadata = try? DocumentInspector.inspect(sourceURL, includeChecksum: false),
                  let total = metadata.itemCount,
                  total > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: options.pageSelection, total: total).count) ?? total
        }()
        logger.record("QUALITY sourcePages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection)")
'''
    s = replace_once(s, source_size, source_size + quality_block, "source page expectation")

    object_line = '            let object = (try JSONSerialization.jsonObject(with: statusData)) as? [String: Any]\n'
    quality_parse = '''            let qualityStatus = (object?["quality_status"] as? String)?.lowercased()
            let qualityScore = Self.doubleValue(object?["quality_score"])
            let qualityWarnings = (object?["quality_warnings"] as? [String]) ?? []
'''
    s = replace_once(s, object_line, object_line + quality_parse, "quality manifest parsing")

    terminal_line = '            if ["completed", "complete", "done", "succeeded", "partial"].contains(state) {\n'
    terminal_guard = '''            if ["completed", "complete", "done", "succeeded", "partial"].contains(state) {
                guard let terminalQuality = qualityStatus else {
                    logger.record("QUALITY terminal manifest missing")
                    throw BasirError.invalidResponse("تعذر التحقق من جودة المستند الناتج. لم يتم اعتماد الملف.")
                }
                logger.record("QUALITY terminal status=\\(terminalQuality) score=\\(qualityScore ?? -1) warnings=\\(qualityWarnings.joined(separator: ","))")
                guard terminalQuality == "passed" else {
                    throw BasirError.conversionFailed("لم يصل المستند الناتج إلى مستوى الجودة الآمن للاعتماد. لم يتم حفظ نتيجة ناقصة أو مشوهة.")
                }
'''
    s = replace_once(s, terminal_line, terminal_guard, "terminal quality enforcement")

    s = replace_once(
        s,
        '        try verifyAndMove(temporary: temporary, response: downloadResponse, outputURL: outputURL)\n',
        '''        let expectedResultPages = max(0, expectedSourcePages - outcome.skippedBlankItems.count)
        try verifyAndMove(
            temporary: temporary,
            response: downloadResponse,
            outputURL: outputURL,
            expectedPages: expectedResultPages
        )
''',
        "quality-aware result validation call",
    )

    s = replace_once(
        s,
        '    private func verifyAndMove(temporary: URL, response: HTTPURLResponse, outputURL: URL) throws {\n',
        '''    private func verifyAndMove(
        temporary: URL,
        response: HTTPURLResponse,
        outputURL: URL,
        expectedPages: Int
    ) throws {
''',
        "quality-aware validation signature",
    )
    s = replace_once(
        s,
        '            try DocxBuilder.validate(url: temporary)\n',
        '            try DocxBuilder.validate(url: temporary, expectedPages: expectedPages)\n',
        "expected page validation",
    )

    integer_helper = '''    private static func integer(_ value: Any?) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
'''
    numeric_helpers = '''    private static func integer(_ value: Any?) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let text = value as? String { return Double(text) }
        return nil
    }
'''
    s = replace_once(s, integer_helper, numeric_helpers, "quality score parser")

    marker = '    private static func validateHTTP(_ response: HTTPURLResponse, data: Data) throws {\n'
    helper = '''    private static func serverVersionAtLeast(_ actual: String, minimum: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.split(separator: "-", maxSplits: 1).first.map(String.init)?
                .split(separator: ".")
                .prefix(3)
                .map { Int($0) ?? 0 } ?? []
        }
        var lhs = parts(actual)
        var rhs = parts(minimum)
        while lhs.count < 3 { lhs.append(0) }
        while rhs.count < 3 { rhs.append(0) }
        for index in 0..<3 {
            if lhs[index] != rhs[index] { return lhs[index] > rhs[index] }
        }
        return true
    }

    // BASIR_FIDELITY_GUARD_R7
'''
    s = replace_once(s, marker, helper + marker, "version helper")

save(rel, s)

# Build gates make the guard non-optional. If a future source refresh drops any
# part, Codemagic must fail instead of publishing a client that silently accepts
# an unverifiable result.
checks = {
    "BasirConvert/Services/ProxyClient.swift": [
        "BASIR_FIDELITY_GUARD_R7",
        "serverVersionAtLeast(serverStatus.apiVersion, minimum: \"2.5.1\")",
        '"quality_manifest", "source_geometry_tables", "softmask_images"',
        "quality_status",
        "quality_score",
        "quality_warnings",
        'guard terminalQuality == "passed"',
        "expectedSourcePages",
        "expectedPages: expectedResultPages",
        "DocxBuilder.validate(url: temporary, expectedPages: expectedPages)",
    ],
    "BasirConvert/Services/DocxBuilder.swift": [
        "expectedPages: Int = 0",
        'w:type=\\\"page\\\"',
        "literal HTML line-break marker",
    ],
}
for path, needles in checks.items():
    text = load(path)
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"fidelity gate failed: {needle!r} missing from {path}")

print("BASIR_QUALITY_GUARD=SERVER_2_5_1_PASSED_MANIFEST_AND_SOURCE_PAGE_VALIDATION_R7")
