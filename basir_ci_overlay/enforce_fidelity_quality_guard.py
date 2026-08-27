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


# Quality policy is enforced in the app as well as on the service. This prevents
# a stale Cloud Run revision from silently accepting work after the app has been
# upgraded for a newer fidelity engine.
rel = "BasirConvert/Services/ProxyClient.swift"
s = load(rel)

if "BASIR_FIDELITY_GUARD_R6" not in s:
    s = replace_once(
        s,
        '        let required = Set(["job_api", "direct_storage_upload", "checksums"])\n',
        '''        let required = Set(["job_api", "direct_storage_upload", "checksums"])
        guard Self.serverVersionAtLeast(serverStatus.apiVersion, minimum: "2.4.0") else {
            logger.record("QUALITY rejected stale processing service version=\\(serverStatus.apiVersion) required=2.4.0")
            throw BasirError.invalidResponse("خدمة المعالجة لم تُحدّث بعد إلى محرك الجودة المطلوب. أعد المحاولة بعد اكتمال التحديث.")
        }
''',
        "minimum processing version",
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
        '''            try DocxBuilder.validate(url: temporary, expectedPages: expectedPages)
''',
        "expected page validation",
    )

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

    // BASIR_FIDELITY_GUARD_R6
'''
    s = replace_once(s, marker, helper + marker, "version helper")

save(rel, s)

# Build gates make the guard non-optional. If a future source refresh drops it,
# Codemagic must fail instead of publishing a client that can use a stale engine.
checks = {
    "BasirConvert/Services/ProxyClient.swift": [
        "BASIR_FIDELITY_GUARD_R6",
        "serverVersionAtLeast(serverStatus.apiVersion, minimum: \"2.4.0\")",
        "expectedSourcePages",
        "expectedPages: expectedResultPages",
        "DocxBuilder.validate(url: temporary, expectedPages: expectedPages)",
    ],
}
for path, needles in checks.items():
    text = load(path)
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"fidelity gate failed: {needle!r} missing from {path}")

print("BASIR_QUALITY_GUARD=SERVER_2_4_AND_SOURCE_PAGE_VALIDATION_R6")
