#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[1/12] فحص ملفات plist والمشروع"
plutil -lint PDFToWord.xcodeproj/project.pbxproj
plutil -lint PDFToWord/PrivacyInfo.xcprivacy
python3 - <<'PYLOC'
from pathlib import Path
import re
root = Path("PDFToWord")
source = "\n".join(p.read_text(encoding="utf-8") for p in root.rglob("*.swift"))
keys = set(re.findall(r'L10n\.(?:text|format)\(\s*"((?:\\.|[^"\\])*)"', source))
format_keys = set(re.findall(r'L10n\.format\(\s*"((?:\\.|[^"\\])*)"', source))
entry = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";$')
def read_strings(path):
    result = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        match = entry.match(line.strip())
        if match:
            result[match.group(1)] = match.group(2)
    return result
ar = read_strings(root / "ar.lproj" / "Localizable.strings")
en = read_strings(root / "en.lproj" / "Localizable.strings")
assert keys == set(ar), f"Arabic localization mismatch: missing={keys-set(ar)}, extra={set(ar)-keys}"
assert keys == set(en), f"English localization mismatch: missing={keys-set(en)}, extra={set(en)-keys}"
formats = re.compile(r'%(?:\d+\$)?(?:[-+0 #]*)?(?:\d+|\*)?(?:\.(?:\d+|\*))?[hlLzjtq]*[@diuoxXfFeEgGaAcCsSp]')
for key in format_keys:
    expected = formats.findall(key.replace('%%', ''))
    actual = formats.findall(en[key].replace('%%', ''))
    assert expected == actual, f"Format placeholder mismatch for {key!r}: {expected} != {actual}"
assert (root / "ar.lproj" / "InfoPlist.strings").is_file()
assert (root / "en.lproj" / "InfoPlist.strings").is_file()
print(f"Localization coverage verified for {len(keys)} keys")
PYLOC

echo "[2/12] فحص صياغة Swift"
while IFS= read -r file; do
  swiftc -frontend -parse "$file"
done < <(find PDFToWord -name '*.swift' | sort)

echo "[3/12] Type-check لطبقة Gemini والنماذج"
swiftc -typecheck \
  PDFToWord/Utilities/Localization.swift \
  PDFToWord/Models/ConversionModels.swift \
  PDFToWord/Utilities/XML.swift \
  PDFToWord/Services/GeminiClient.swift

echo "[4/12] Type-check لمحرك التحويل"
if [[ "$(uname -s)" == "Linux" ]]; then
cat > "$TMP/EngineStubs.swift" <<'SWIFT'
import Foundation

extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
enum URLFileProtection { static let complete = "complete" }
extension URLResourceKey { static let fileProtectionKey = URLResourceKey("stub.fileProtection") }

final class PDFPageExtractor {
    let pageCount = 1
    init(url: URL) throws {}
    func pageData(at index: Int) throws -> Data { Data([1]) }
    func nativeText(at index: Int) -> String { "" }
    func isProbablyBlank(at index: Int) -> Bool { false }
    func highResolutionPageImage(at index: Int, longEdge: CGFloat = 2800) throws -> Data { Data([137, 80, 78, 71]) }
    func detailTiles(from pageImageData: Data, overlapFraction: CGFloat = 0.08) -> [Data] { [] }
    func localOCRReference(at index: Int, pageImageData: Data?) -> LocalOCRReference { .empty }
}

actor JobStore {
    static let shared = JobStore()
    func createWorkspace(sourceURL: URL, pageCount: Int, options: ConversionOptions) throws -> ConversionJobRecord { fatalError("type-check only") }
    func verifySourceIntegrity(for record: ConversionJobRecord) throws -> URL { URL(fileURLWithPath: "/tmp/source.pdf") }
    func save(_ record: ConversionJobRecord) throws {}
    func loadAnalyses(for record: ConversionJobRecord) throws -> [PageAnalysis] { [] }
    func saveAnalysis(_ analysis: PageAnalysis, in record: ConversionJobRecord) throws {}
    func clearAnalyses(for record: ConversionJobRecord) throws {}
    func fingerprint(of url: URL) throws -> String { "hash" }
    func byteCount(of url: URL) throws -> Int64 { 1 }
}

enum JobStoreError: Error { case outputMissing }
final class DOCXBuilder {
    func build(analyses: [PageAnalysis], extractor: PDFPageExtractor, options: ConversionOptions, outputURL: URL, title: String) throws {}
}
enum DOCXPackageValidator { static func validate(url: URL) throws {} }
SWIFT
swiftc -typecheck   PDFToWord/Utilities/Localization.swift   PDFToWord/Models/ConversionModels.swift   PDFToWord/Utilities/XML.swift   PDFToWord/Services/GeminiClient.swift   "$TMP/EngineStubs.swift"   PDFToWord/Services/ConversionEngine.swift
else
  echo "سيغطي xcodebuild محرك التحويل على macOS."
fi

echo "[5/12] بناء وتشغيل اختبار Word الغني"
if [[ "$(uname -s)" == "Linux" ]]; then
cat > "$TMP/UIKit.swift" <<'SWIFT'
import Foundation
public final class UIImage {
    public var size: CGSize
    public init?(data: Data) { self.size = CGSize(width: 1200, height: 700) }
}
SWIFT
swiftc -emit-library -emit-module -module-name UIKit "$TMP/UIKit.swift" \
  -emit-module-path "$TMP/UIKit.swiftmodule" -o "$TMP/libUIKit.so"
cat > "$TMP/BuilderStubs.swift" <<'SWIFT'
import Foundation
final class PDFPageExtractor {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    func pageSize(at index: Int) -> CGSize { CGSize(width: 595, height: 842) }
    func cropImage(pageIndex: Int, normalizedBox: [Double], maxRenderWidth: CGFloat = 3200) -> Data? { png }
    func highResolutionPageImage(at index: Int, longEdge: CGFloat = 2800) throws -> Data { png }
}
SWIFT
cat > "$TMP/RichBuilderHarness.swift" <<'SWIFT'
import Foundation

@main
struct RichBuilderHarness {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--expect-invalid" {
            do {
                try DOCXPackageValidator.validate(url: URL(fileURLWithPath: CommandLine.arguments[2]))
                print("INVALID_ACCEPTED")
            } catch {
                print("REJECTED")
            }
            return
        }
        let options = ConversionOptions(
            model: "gemini-3.5-flash", thinkingLevel: "high",
            describeImages: true, embedImages: true,
            includeDecorativeImages: true, showImageDescriptions: true,
            preserveHeadersAndFooters: true, preservePageBreaks: true,
            preservePageSizeAndOrientation: true, addPageNumbers: true,
            bodyFontArabic: "Arial", bodyFontLatin: "Arial",
            bodyFontSize: 12, headingFontSize: 24, pageMarginPoints: 36,
            concurrency: 1, retryCount: 1, useNativeTextFallback: false,
            strictCompletenessCheck: true, minimumCoverageRatio: 0.95,
            promptAddendum: ""
        )
        let blocks: [DocumentBlock] = [
            DocumentBlock(type: .header, text: "HEADER-T06-L مختبر التحويل HEADER-T06-R"),
            DocumentBlock(
                type: .heading1, text: "عنوان كبير",
                runs: [TextRun(text: "عنوان كبير", bold: true, fontSize: 24, direction: .rtl)],
                bookmark: "REF_A", keepWithNext: true
            ),
            DocumentBlock(
                type: .paragraph, text: "رابط اختبار",
                runs: [
                    TextRun(text: "رابط اختبار", underline: true, direction: .rtl, linkURL: "https://example.org/test"),
                    TextRun(text: "", footnoteReferenceID: 1)
                ]
            ),
            DocumentBlock(
                type: .numbered, text: "بند روماني",
                runs: [TextRun(text: "بند روماني", direction: .rtl)],
                direction: .rtl, listLevel: 2, listStyle: .upperRoman, listStart: 4
            ),
            DocumentBlock(
                type: .table, tableRowCount: 2, tableColumnCount: 3,
                tableCells: [
                    TableCell(row: 0, column: 0, columnSpan: 3, text: "رأس", runs: [TextRun(text: "رأس", bold: true, direction: .rtl)], isHeader: true),
                    TableCell(row: 1, column: 0, text: "A"),
                    TableCell(row: 1, column: 1, columnSpan: 2, text: "B")
                ],
                repeatHeaderRows: 1
            ),
            DocumentBlock(type: .image, boundingBox: [0.1, 0.1, 0.5, 0.3], altText: "مخطط اختبار تفصيلي"),
            DocumentBlock(type: .footnote, text: "FOOTNOTE-T13-01 حاشية مرجعية", footnoteID: 1),
            DocumentBlock(type: .footer, text: "FOOTER-T06-AR")
        ]
        let page = PageAnalysis(
            pageNumber: 1, detectedLanguage: "ar", direction: .rtl,
            blocks: blocks, source: .geminiConsensus,
            qualityScore: 0.99, agreementScore: 0.99,
            verificationPasses: 3, readingOrderConfidence: 0.99
        )
        let encoded = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(PageAnalysis.self, from: encoded)
        guard decoded.blocks.count == blocks.count,
              decoded.blocks[2].runs.first?.linkURL == "https://example.org/test",
              decoded.blocks[4].tableCells.first?.columnSpan == 3,
              decoded.blocks[6].footnoteID == 1 else {
            throw NSError(domain: "RichBuilderHarness", code: 2)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try DOCXBuilder().build(
            analyses: [page], extractor: PDFPageExtractor(), options: options,
            outputURL: output, title: "PDFToWord rich test"
        )
        try DOCXPackageValidator.validate(url: output)
    }
}
SWIFT
swiftc -I "$TMP" -L "$TMP" -lUIKit \
  PDFToWord/Utilities/Localization.swift \
  PDFToWord/Models/ConversionModels.swift \
  PDFToWord/Utilities/XML.swift \
  PDFToWord/Services/ZipArchiveWriter.swift \
  "$TMP/BuilderStubs.swift" \
  PDFToWord/Services/DOCXBuilder.swift \
  "$TMP/RichBuilderHarness.swift" \
  -o "$TMP/rich-builder-check"
LD_LIBRARY_PATH="$TMP" "$TMP/rich-builder-check" "$TMP/rich-check.docx"
python3 Tools/validate_docx.py "$TMP/rich-check.docx"
python3 - "$TMP/rich-check.docx" <<'PYRICH'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as archive:
    names = set(archive.namelist())
    document = archive.read("word/document.xml").decode("utf-8")
    relationships = archive.read("word/_rels/document.xml.rels").decode("utf-8")
    required = ["<w:gridSpan", "<w:numPr", "<w:hyperlink", "<w:footnoteReference", "<w:bookmarkStart", "<w:tblHeader"]
    missing = [item for item in required if item not in document]
    assert not missing, f"Rich OOXML elements missing: {missing}"
    assert "word/footnotes.xml" in names
    assert any(name.startswith("word/header") for name in names)
    assert any(name.startswith("word/footer") for name in names)
    assert 'TargetMode="External"' in relationships
    assert any(name.startswith("word/media/") for name in names)
PYRICH
python3 - "$TMP/rich-check.docx" "$TMP/broken-missing.docx" "$TMP/broken-image.docx" "$TMP/broken-external.docx" <<'PYBROKEN'
import sys, zipfile
source, missing, image, external = sys.argv[1:]
with zipfile.ZipFile(source) as original:
    entries = {name: original.read(name) for name in original.namelist()}
with zipfile.ZipFile(missing, "w", compression=zipfile.ZIP_STORED) as output:
    for name, payload in entries.items():
        if name != "word/numbering.xml": output.writestr(name, payload)
with zipfile.ZipFile(image, "w", compression=zipfile.ZIP_STORED) as output:
    for name, payload in entries.items():
        if name.startswith("word/media/"): payload = b"not-a-real-png"
        output.writestr(name, payload)
with zipfile.ZipFile(external, "w", compression=zipfile.ZIP_STORED) as output:
    for name, payload in entries.items():
        if name == "word/_rels/document.xml.rels":
            payload = payload.replace(b"https://example.org/test", b"file:///etc/passwd")
        output.writestr(name, payload)
PYBROKEN
[[ "$(LD_LIBRARY_PATH="$TMP" "$TMP/rich-builder-check" --expect-invalid "$TMP/broken-missing.docx")" == "REJECTED" ]]
[[ "$(LD_LIBRARY_PATH="$TMP" "$TMP/rich-builder-check" --expect-invalid "$TMP/broken-image.docx")" == "REJECTED" ]]
[[ "$(LD_LIBRARY_PATH="$TMP" "$TMP/rich-builder-check" --expect-invalid "$TMP/broken-external.docx")" == "REJECTED" ]]
else
  echo "سيغطي xcodebuild كاتب Word على macOS."
fi

echo "[6/12] اختبار العلاقات والصور السلبية في DOCX"
if [[ "$(uname -s)" == "Linux" ]]; then
  test -s "$TMP/rich-check.docx"
  test -s "$TMP/broken-missing.docx"
  test -s "$TMP/broken-image.docx"
  test -s "$TMP/broken-external.docx"
fi

echo "[7/12] اختبار ترميز نموذج المستند الغني"
if [[ "$(uname -s)" == "Linux" ]]; then
  # تم إجراء round-trip لـ PageAnalysis وTextRun وTableCell داخل RichBuilderHarness.
  test -s "$TMP/rich-check.docx"
fi

echo "[8/12] فحص أداة تقييم المعيار العلمي"
python3 -m py_compile Tools/evaluate_scientific_benchmark.py
set +e
python3 Tools/evaluate_scientific_benchmark.py "$TMP/rich-check.docx" --json "$TMP/benchmark-report.json" >/dev/null
BENCHMARK_EXIT=$?
set -e
if [[ "$BENCHMARK_EXIT" -ne 0 && "$BENCHMARK_EXIT" -ne 1 ]]; then
  echo "تعطلت أداة تقييم المعيار العلمي." >&2
  exit 1
fi
test -s "$TMP/benchmark-report.json"

echo "[9/12] فحص أسرار وأنماط خطرة"
if grep -RInE 'AIza[0-9A-Za-z_-]{20,}|try!|fatalError\(' PDFToWord --include='*.swift'; then
  echo "عُثر على سر محتمل أو نمط Swift خطر." >&2
  exit 1
fi

echo "[10/12] فحص رقم الإصدار"
grep -q 'MARKETING_VERSION = 2.0.0;' PDFToWord.xcodeproj/project.pbxproj
grep -q 'CURRENT_PROJECT_VERSION = 6;' PDFToWord.xcodeproj/project.pbxproj
grep -q '^2.0.0$' VERSION

echo "[11/12] فحص ملفات التوثيق الأساسية"
test -s README.md
test -s TEST_PLAN.md
test -s CHANGELOG.md
test -s HARDENING_REPORT.md
test -s FINAL_RELIABILITY_REPORT.md
test -s ACCURACY_PROTOCOL.md
test -s BENCHMARK_HARDENING.md
test -s BENCHMARK_TEST_PROTOCOL.md
test -x Tools/evaluate_scientific_benchmark.py

if command -v xcodebuild >/dev/null 2>&1; then
  echo "[12/12] بناء Target لمحاكي iOS دون توقيع"
  xcodebuild \
    -project PDFToWord.xcodeproj \
    -target PDFToWord \
    -configuration Debug \
    -sdk iphonesimulator \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$TMP/build" \
    build
else
  echo "[12/12] xcodebuild غير موجود؛ تم تجاوز بناء iOS في هذه البيئة."
fi

echo "اكتملت الفحوص الممكنة في هذه البيئة بنجاح."
