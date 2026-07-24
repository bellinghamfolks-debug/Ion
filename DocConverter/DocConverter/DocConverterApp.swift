import SwiftUI
import Observation
import UniformTypeIdentifiers
import CryptoKit
import Security
import PDFKit
import Vision
import QuickLook
import VisionKit
import UserNotifications
import Translation

@main
struct PDFToWordAccessibilityApp: App {
    // Owned here so a PDF opened from another app (onOpenURL) reaches the model.
    @State private var vm = AppViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .onOpenURL { url in vm.acceptIncoming(url) }
        }
    }
}

// MARK: - Server config

enum Server {
    /// The shared EnglishNova/Ion backend that runs the conversion in the
    /// background (no per-user API key needed). Used for the "off" and
    /// "encrypted at rest" privacy levels — NOT for strict end-to-end, which
    /// never contacts the server.
    static let baseURL = URL(string: "https://ion-production-da28.up.railway.app")!

    /// A stable per-device id so each device sees only its own jobs.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "device.id") { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "device.id")
        return new
    }
}

// MARK: - Privacy levels

enum EncryptionLevel: String, CaseIterable, Identifiable {
    case off        // server processes; stored in plaintext
    case atRest     // client-held-key encryption at rest (server processes in RAM)
    case e2e        // strict end-to-end: converted entirely ON DEVICE, never uploaded

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .off:    return "بدون تشفير"
        case .atRest: return "تشفير عند الحفظ (موصى به)"
        case .e2e:    return "تشفير تامّ على جهازك"
        }
    }

    var subtitleAr: String {
        switch self {
        case .off:
            return "يُعالَج الملف على الخادم ويُحفَظ كنصّ ظاهر. الأسرع، والأقلّ خصوصية."
        case .atRest:
            return "يُشفَّر الملف ونتائجه بمفتاح لا يملكه إلا جهازك، فلا يقرؤها الخادم ولا قاعدة البيانات عند الحفظ. تُعالَج على الخادم لحظيًّا في الذاكرة فقط، والصفحات الممسوحة تُقرأ عبر خدمة Google."
        case .e2e:
            return "يجري التحويل بالكامل داخل جهازك (قراءة النص + تعرّف ضوئي عربي من Apple)، ولا يُرفَع الملف ولا أيّ جزء منه إلى أيّ خادم أو إلى Google. الأعلى خصوصية، للملفات الحسّاسة — ولا يعمل في الخلفية."
        }
    }

    var badgeAr: String {
        switch self {
        case .off:    return "🔓 بدون تشفير"
        case .atRest: return "🔒 تشفير عند الحفظ"
        case .e2e:    return "🛡️ تشفير تامّ على جهازك"
        }
    }
}

// MARK: - Client-held-key encryption (for the "at rest" level)
//
// The device holds a 256-bit master key in the Keychain. For each job we derive
// a per-job key from (masterKey, jobId) via HKDF, so any past job's key can be
// recomputed for history/resume WITHOUT storing it. AES-GCM uses CryptoKit's
// "combined" layout (nonce||ciphertext||tag), byte-for-byte compatible with the
// Node server.
enum CryptoBox {
    private static let account = "docconverter.master.key.v1"

    static func masterKey() -> SymmetricKey {
        if let data = load(), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        save(key.withUnsafeBytes { Data($0) })
        return key
    }

    static func jobKey(_ jobId: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey(),
            salt: Data(jobId.utf8),
            info: Data("DocConverter-DEK-v1".utf8),
            outputByteCount: 32)
    }

    static func keyBase64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw Err.seal }
        return combined
    }
    static func open(_ blob: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: blob), using: key)
    }
    enum Err: Error { case seal }

    private static func save(_ data: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    private static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }
}

// MARK: - Models

enum JobStatus: String, Codable {
    case processing, done, partial, failed
    case keyRequired = "key_required"

    var titleAr: String {
        switch self {
        case .processing: return "قيد المعالجة"
        case .done: return "اكتمل"
        case .partial: return "اكتمل جزئيًا (توجد صفحات فشلت)"
        case .failed: return "فشل"
        case .keyRequired: return "بانتظار مفتاح التشفير"
        }
    }
}

struct JobDetail: Codable {
    let jobId: String
    let filename: String
    let status: JobStatus
    let totalPages: Int
    let donePages: Int
    let failedPages: Int
    let resultText: String?
    let error: String?
    let encrypted: Bool?
}

struct JobSummary: Codable, Identifiable {
    let jobId: String
    let filename: String
    let status: JobStatus
    let totalPages: Int
    let donePages: Int
    var id: String { jobId }
}

// MARK: - Conversion choices

enum GoogleModel: String, CaseIterable, Identifiable {
    case flashLite = "gemini-3.5-flash-lite"
    case flash = "gemini-3.6-flash"
    case pro = "gemini-3.1-pro-preview"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .flashLite: return "جيميني 3.5 لايت (أسرع وأوفر)"
        case .flash: return "جيميني 3.6 (أعلى دقة)"
        case .pro: return "جيميني 3.1 برو (الأقوى)"
        }
    }
}

enum ConversionMode: String, CaseIterable, Identifiable {
    case accessible, layout
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .accessible: return "نص مُيسّر للقراءة"
        case .layout: return "بتنسيق المستند الأصلي"
        }
    }
    var hintAr: String {
        switch self {
        case .accessible: return "نص مرتّب ومتسلسل، الأنسب لقارئ الشاشة والقراءة الصوتية."
        case .layout: return "يعيد بناء شكل المستند الأصلي: الخطوط والجداول والصور ومواضعها."
        }
    }
}

enum MathMode: String, CaseIterable, Identifiable {
    case off, words, latex
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .off: return "بدون"
        case .words: return "نُطق بالكلمات"
        case .latex: return "LaTeX"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case docx, rtf, txt
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .docx: return "وورد (DOCX)"
        case .rtf: return "RTF"
        case .txt: return "نص عادي"
        }
    }
}

struct ConversionOptions {
    var faithful = true
    var describeImages = true
    var math: MathMode = .off
    var detectHeadings = true
    var preserveTables = true
    var pageNumbers = true

    var dictionary: [String: Any] {
        [
            "faithful": faithful,
            "describeImages": describeImages,
            "math": math == .off ? "" : math.rawValue,
            "detectHeadings": detectHeadings,
            "preserveTables": preserveTables,
            "pageNumbers": pageNumbers,
        ]
    }
}

// MARK: - Document builders (used by the on-device / E2E path)

/// Minimal RTF — escapes braces/backslashes, encodes non-ASCII as \uN, \par per line.
func makeRTF(_ text: String) -> String {
    let body = text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "{", with: "\\{")
        .replacingOccurrences(of: "}", with: "\\}")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            line.unicodeScalars.map { $0.value > 127 ? "\\u\($0.value)?" : String($0) }.joined()
        }
        .joined(separator: "\\par\n")
    return "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Arial;}}\\f0\\fs28 \(body)}"
}

/// CRC-32 (used by the store-only ZIP writer for on-device .docx).
enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

/// A tiny store-only (no compression) ZIP writer — enough to package a .docx
/// entirely on-device, so strict E2E never needs the server to build the file.
enum ZipStore {
    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data(), central = Data()
        var offset: UInt32 = 0
        for f in files {
            let name = Array(f.name.utf8)
            let crc = CRC32.checksum(f.data)
            let size = UInt32(f.data.count)
            let localOffset = offset

            var lh = Data()
            lh.append(le32(0x04034b50)); lh.append(le16(20)); lh.append(le16(0)); lh.append(le16(0))
            lh.append(le16(0)); lh.append(le16(0))                      // mod time/date
            lh.append(le32(crc)); lh.append(le32(size)); lh.append(le32(size))
            lh.append(le16(UInt16(name.count))); lh.append(le16(0))     // name len, extra len
            lh.append(Data(name))
            out.append(lh); out.append(f.data)
            offset += UInt32(lh.count) + size

            var cd = Data()
            cd.append(le32(0x02014b50)); cd.append(le16(20)); cd.append(le16(20))
            cd.append(le16(0)); cd.append(le16(0)); cd.append(le16(0)); cd.append(le16(0))
            cd.append(le32(crc)); cd.append(le32(size)); cd.append(le32(size))
            cd.append(le16(UInt16(name.count))); cd.append(le16(0)); cd.append(le16(0))
            cd.append(le16(0)); cd.append(le16(0)); cd.append(le32(0))
            cd.append(le32(localOffset))
            cd.append(Data(name))
            central.append(cd)
        }
        let centralOffset = offset
        out.append(central)
        var eocd = Data()
        eocd.append(le32(0x06054b50)); eocd.append(le16(0)); eocd.append(le16(0))
        eocd.append(le16(UInt16(files.count))); eocd.append(le16(UInt16(files.count)))
        eocd.append(le32(UInt32(central.count))); eocd.append(le32(centralOffset)); eocd.append(le16(0))
        out.append(eocd)
        return out
    }
}

/// Builds a real .docx from assembled text (paragraphs + "## " headings), RTL
/// aware for Arabic. Tables are kept as text lines (E2E extraction is plain).
enum DocxBuilder {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func sanitize(_ s: String) -> String {
        String(s.unicodeScalars.filter { sc in
            let v = sc.value
            return v == 0x09 || v == 0x0A || (v >= 0x20 && v != 0xFFFE && v != 0xFFFF)
        })
    }

    static func build(_ text: String) -> Data {
        let paras = sanitize(text).split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let isHeading = line.hasPrefix("## ")
            let content = isHeading ? String(line.dropFirst(3)) : line
            let rpr = "<w:rPr><w:rtl/>" + (isHeading ? "<w:b/><w:sz w:val=\"32\"/>" : "") + "</w:rPr>"
            return "<w:p><w:pPr><w:bidi/></w:pPr><w:r>\(rpr)<w:t xml:space=\"preserve\">\(esc(content))</w:t></w:r></w:p>"
        }.joined()

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(paras)<w:sectPr/></w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """
        return ZipStore.archive([
            (name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            (name: "_rels/.rels", data: Data(rels.utf8)),
            (name: "word/document.xml", data: Data(document.utf8)),
        ])
    }
}

// MARK: - On-device converter (strict end-to-end)

/// Converts a PDF entirely on the device: embedded text via PDFKit, and Apple's
/// on-device OCR (Vision, Arabic + English) for scanned pages. Nothing leaves
/// the device.
enum LocalConverter {
    /// Returns the assembled document text. `progress` is called (done,total).
    static func extractText(pdfData: Data, pageNumbers: Bool,
                            progress: @escaping (Int, Int) -> Void) async -> String {
        guard let doc = PDFDocument(data: pdfData) else { return "" }
        let n = doc.pageCount
        var out: [String] = []
        for i in 0..<n {
            var text = ""
            if let page = doc.page(at: i) {
                text = page.string ?? ""
                // The embedded text layer is often EMPTY (scanned) or GARBLED
                // (symbolic fonts with no ToUnicode map — Arabic comes out as
                // latin gibberish). In both cases render the page and read it
                // with Apple's on-device OCR (Vision), which reads the actual
                // pixels: faithful, private, and never fabricates like an LLM.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 15
                    || looksGarbled(text) {
                    text = await ocr(page: page)
                }
            }
            out.append(pageNumbers ? "## صفحة \(i + 1)\n\(text)" : text)
            progress(i + 1, n)
        }
        return out.joined(separator: "\n\n")
    }

    /// Detect an unreliable/garbled text layer (mirrors the server's
    /// extract_page.py): many replacement / private-use glyphs, or a very low
    /// ratio of real letters/digits (a page mostly of odd symbols).
    static func looksGarbled(_ s: String) -> Bool {
        let scalars = s.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let n = scalars.count
        guard n >= 20 else { return false }
        var bad = 0, alnum = 0
        for u in scalars {
            if u.value == 0xFFFD || (0xE000...0xF8FF).contains(u.value) { bad += 1 }
            if CharacterSet.alphanumerics.contains(u) { alnum += 1 }
        }
        if Double(bad) / Double(n) > 0.02 { return true }
        if Double(alnum) / Double(n) < 0.5 { return true }
        return false
    }

    private static func ocr(page: PDFPage) async -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = obs.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ar-SA", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { cont.resume(returning: "") }
        }
    }
}

// MARK: - Local (on-device) history for E2E conversions

struct LocalJob: Codable, Identifiable {
    let id: String
    let filename: String
    let createdAt: Date
    let relativePath: String   // inside Documents/e2e
    let format: String
}

enum LocalStore {
    private static let key = "e2e.history.v1"
    private static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("e2e", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func list() -> [LocalJob] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let jobs = try? JSONDecoder().decode([LocalJob].self, from: data) else { return [] }
        return jobs.sorted { $0.createdAt > $1.createdAt }
    }

    static func url(for job: LocalJob) -> URL { dir.appendingPathComponent(job.relativePath) }

    /// Persist an output file locally and record it in history. Returns its URL.
    static func save(filename: String, format: OutputFormat, data: Data) -> (job: LocalJob, url: URL)? {
        let id = UUID().uuidString
        let base = (filename as NSString).deletingPathExtension
        let safe = base.isEmpty ? "document" : base
        let rel = "\(id).\(format.rawValue)"
        let fileURL = dir.appendingPathComponent(rel)
        do { try data.write(to: fileURL, options: .atomic) } catch { return nil }
        let job = LocalJob(id: id, filename: "\(safe).\(format.rawValue)",
                           createdAt: Date(), relativePath: rel, format: format.rawValue)
        var all = list(); all.append(job)
        if let enc = try? JSONEncoder().encode(all) { UserDefaults.standard.set(enc, forKey: key) }
        return (job, fileURL)
    }

    static func delete(_ job: LocalJob) {
        try? FileManager.default.removeItem(at: url(for: job))
        let all = list().filter { $0.id != job.id }
        if let enc = try? JSONEncoder().encode(all) { UserDefaults.standard.set(enc, forKey: key) }
    }
}

// MARK: - API client (server: off / at-rest levels)

struct ConvertAPI {
    private var session: URLSession { .shared }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: Server.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue(Server.deviceID, forHTTPHeaderField: "X-Device-Id")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    func createJob(pdf: Data, filename: String, model: String, mode: String,
                   options: [String: Any], encrypt: Bool) async throws -> String {
        var r = request("convert/jobs", method: "POST")
        var body: [String: Any] = [
            "filename": filename, "model": model, "mode": mode, "options": options,
        ]
        if encrypt {
            let jobId = UUID().uuidString.lowercased()
            let key = CryptoBox.jobKey(jobId)
            let cipher = try CryptoBox.seal(pdf, key: key)
            body["id"] = jobId
            body["encrypted"] = true
            body["key"] = CryptoBox.keyBase64(key)
            body["pdfBase64"] = cipher.base64EncodedString()
        } else {
            body["pdfBase64"] = pdf.base64EncodedString()
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: r)
        try Self.check(resp, data)
        struct Created: Decodable { let jobId: String }
        return try JSONDecoder().decode(Created.self, from: data).jobId
    }

    func status(_ jobId: String) async throws -> JobDetail {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)"))
        try Self.check(resp, data)
        return try JSONDecoder().decode(JobDetail.self, from: data)
    }

    func list() async throws -> [JobSummary] {
        let (data, resp) = try await session.data(for: request("convert/jobs"))
        try Self.check(resp, data)
        struct Wrap: Decodable { let jobs: [JobSummary] }
        return try JSONDecoder().decode(Wrap.self, from: data).jobs
    }

    func resume(_ jobId: String, encrypted: Bool) async throws {
        var r = request("convert/jobs/\(jobId)/resume", method: "POST")
        if encrypted {
            r.httpBody = try JSONSerialization.data(withJSONObject: ["key": CryptoBox.keyBase64(CryptoBox.jobKey(jobId))])
        }
        let (data, resp) = try await session.data(for: r)
        try Self.check(resp, data)
    }

    func delete(_ jobId: String) async throws {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)", method: "DELETE"))
        try Self.check(resp, data)
    }

    func downloadResult(_ detail: JobDetail, format: OutputFormat) async throws -> URL {
        let base = (detail.filename as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base.isEmpty ? "document" : base).\(format.rawValue)")
        if detail.encrypted == true {
            let key = CryptoBox.jobKey(detail.jobId)
            switch format {
            case .docx:
                let (data, resp) = try await session.data(for: request("convert/jobs/\(detail.jobId)/result.docx.enc"))
                try Self.check(resp, data)
                try CryptoBox.open(data, key: key).write(to: url, options: .atomic)
            case .txt:
                try Data(Self.decryptedText(detail).utf8).write(to: url, options: .atomic)
            case .rtf:
                try Data(makeRTF(Self.decryptedText(detail)).utf8).write(to: url, options: .atomic)
            }
            return url
        }
        let (data, resp) = try await session.data(for: request("convert/jobs/\(detail.jobId)/result.\(format.rawValue)"))
        try Self.check(resp, data)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func decryptedText(_ detail: JobDetail) -> String {
        guard detail.encrypted == true, let rt = detail.resultText, !rt.isEmpty,
              let blob = Data(base64Encoded: rt) else { return detail.resultText ?? "" }
        let key = CryptoBox.jobKey(detail.jobId)
        guard let plain = try? CryptoBox.open(blob, key: key) else { return "" }
        return String(data: plain, encoding: .utf8) ?? ""
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw NSError(domain: "Convert", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "خطأ من الخادم (\(http.statusCode)) \(msg)"])
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class AppViewModel {
    // Settings (persisted).
    var selectedModel: GoogleModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "model") }
    }
    var privacy: EncryptionLevel {
        didSet { UserDefaults.standard.set(privacy.rawValue, forKey: "privacy.level") }
    }
    var outputFormat: OutputFormat {
        didSet { UserDefaults.standard.set(outputFormat.rawValue, forKey: "output.format") }
    }
    var mode: ConversionMode = .accessible
    var options = ConversionOptions()

    // Runtime state.
    var selectedPDFURL: URL?
    var current: JobDetail?
    var resultURL: URL?
    var history: [JobSummary] = []
    var localHistory: [LocalJob] = []
    var isUploading = false
    var statusMessage = "جاهز للبدء. اختر ملف PDF لتحويله."

    // Page-range selection.
    var pageCount = 0
    var pageRangeEnabled = false
    var startPage = 1
    var endPage = 1

    // Batch progress.
    var batchTotal = 0
    var batchDone = 0

    private let api = ConvertAPI()
    private var pollTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        selectedModel = GoogleModel(rawValue: d.string(forKey: "model") ?? "") ?? .flashLite
        privacy = EncryptionLevel(rawValue: d.string(forKey: "privacy.level") ?? "") ?? .atRest
        outputFormat = OutputFormat(rawValue: d.string(forKey: "output.format") ?? "") ?? .docx
        localHistory = LocalStore.list()
    }

    func announce(_ message: String) {
        statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Set the active PDF and read its page count (for the page-range control).
    func selectPDF(_ url: URL) {
        selectedPDFURL = url
        resultURL = nil
        current = nil
        var count = 0
        let needsStop = url.startAccessingSecurityScopedResource()
        if let doc = PDFDocument(url: url) { count = doc.pageCount }
        if needsStop { url.stopAccessingSecurityScopedResource() }
        pageCount = count
        startPage = 1
        endPage = max(1, count)
        pageRangeEnabled = false
        announce(count > 0 ? "تم اختيار ملف من \(count) صفحة. اضغط ابدأ التحويل." : "تم اختيار الملف.")
    }

    /// A PDF opened from another app (share sheet / Files "Open in…").
    func acceptIncoming(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).pdf")
        do {
            let data = try Data(contentsOf: url)
            try data.write(to: dst, options: .atomic)
            selectPDF(dst)
        } catch { announce("تعذّر فتح الملف الوارد: \(error.localizedDescription)") }
    }

    /// Read the selected PDF, applying the chosen page range if enabled.
    private func pdfDataForConversion() throws -> Data {
        guard let url = selectedPDFURL else { throw NSError(domain: "PDF", code: 1) }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard pageRangeEnabled, pageCount > 1,
              let src = PDFDocument(data: data) else { return data }
        let out = PDFDocument()
        let lo = max(1, min(startPage, endPage))
        let hi = min(pageCount, max(startPage, endPage))
        var idx = 0
        for p in (lo - 1)...(hi - 1) {
            if let page = src.page(at: p) { out.insert(page, at: idx); idx += 1 }
        }
        return out.dataRepresentation() ?? data
    }

    func startConversion() async {
        guard selectedPDFURL != nil else { announce("اختر ملف PDF أولًا."); return }
        isUploading = true
        defer { isUploading = false }
        do {
            let data = try pdfDataForConversion()
            let filename = selectedPDFURL!.lastPathComponent
            resultURL = nil
            current = nil

            if privacy == .e2e {
                await convertOnDevice(data: data, filename: filename)
            } else {
                announce(privacy == .atRest ? "جارٍ رفع الملف مشفّرًا…" : "جارٍ رفع الملف…")
                let jobId = try await api.createJob(
                    pdf: data, filename: filename,
                    model: selectedModel.rawValue, mode: mode.rawValue,
                    options: options.dictionary, encrypt: privacy == .atRest)
                announce("بدأ التحويل على الخادم. يمكنك إغلاق التطبيق؛ ستجد الملف في السجل.")
                startPolling(jobId)
            }
        } catch {
            announce("تعذّر بدء التحويل: \(error.localizedDescription)")
        }
    }

    // MARK: Batch

    /// Convert several PDFs one after another (server modes fire independent
    /// jobs that appear in history; E2E converts each on-device in turn).
    func startBatch(_ urls: [URL]) async {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        batchTotal = pdfs.count; batchDone = 0
        for url in pdfs {
            let needsStop = url.startAccessingSecurityScopedResource()
            let filename = url.lastPathComponent
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if privacy == .e2e {
                    await convertOnDevice(data: data, filename: filename)
                } else {
                    _ = try await api.createJob(
                        pdf: data, filename: filename,
                        model: selectedModel.rawValue, mode: mode.rawValue,
                        options: options.dictionary, encrypt: privacy == .atRest)
                }
            } catch { /* skip this file, continue the batch */ }
            batchDone += 1
            statusMessage = "الدفعة: \(batchDone) من \(batchTotal)"
        }
        await refreshHistory()
        notifyDone("اكتملت الدفعة (\(batchTotal) ملف)")
        announce("اكتملت الدفعة: \(batchTotal) ملف. تجدها في السجل.")
        batchTotal = 0; batchDone = 0
    }

    // MARK: Notifications (local)

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyDone(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "مُحوّل المستندات"
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: Translation source

    /// The plain text of the current result (decrypted for at-rest / read from
    /// the local file), used as the translation source.
    func currentPlainText() -> String {
        if let d = current, d.encrypted == true { return ConvertAPI.decryptedText(d) }
        if let d = current, let rt = d.resultText { return rt }
        if let url = resultURL, let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return ""
    }

    /// Save a translated document as a new local file and preview it.
    func saveTranslated(_ text: String, langCode: String) {
        let base = (selectedPDFURL?.lastPathComponent as NSString?)?.deletingPathExtension ?? "document"
        let out: Data
        switch outputFormat {
        case .docx: out = DocxBuilder.build(text)
        case .rtf:  out = Data(makeRTF(text).utf8)
        case .txt:  out = Data(text.utf8)
        }
        if let saved = LocalStore.save(filename: "\(base)-\(langCode).\(outputFormat.rawValue)", format: outputFormat, data: out) {
            resultURL = saved.url
            localHistory = LocalStore.list()
            announce("✅ الترجمة جاهزة — يمكنك معاينتها أو حفظها.")
        }
    }

    /// Strict end-to-end: convert fully on-device and save the output locally.
    private func convertOnDevice(data: Data, filename: String) async {
        announce("تحويل آمن على الجهاز… لا يُرفع أي شيء.")
        let pageNumbers = options.pageNumbers
        let text = await LocalConverter.extractText(pdfData: data, pageNumbers: pageNumbers) { done, total in
            Task { @MainActor in
                self.statusMessage = "المعالجة على الجهاز: \(done) من \(total) صفحة."
            }
        }
        let fmt = outputFormat
        let out: Data
        switch fmt {
        case .docx: out = DocxBuilder.build(text)
        case .rtf:  out = Data(makeRTF(text).utf8)
        case .txt:  out = Data(text.utf8)
        }
        if let saved = LocalStore.save(filename: filename, format: fmt, data: out) {
            resultURL = saved.url
            localHistory = LocalStore.list()
            notifyDone("اكتمل تحويل: \(filename)")
            announce("✅ الملف جاهز على جهازك — يمكنك معاينته داخل التطبيق أو حفظه ومشاركته.")
        } else {
            announce("تعذّر حفظ الملف الناتج على الجهاز.")
        }
    }

    func startPolling(_ jobId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let detail = try await api.status(jobId)
                    current = detail
                    switch detail.status {
                    case .processing:
                        statusMessage = "قيد المعالجة: \(detail.donePages) من \(detail.totalPages) صفحة."
                    case .keyRequired:
                        statusMessage = "استئناف آمن للمعالجة…"
                        try? await api.resume(detail.jobId, encrypted: true)
                    case .done:
                        announce("اكتمل التحويل. جارٍ تجهيز الملف.")
                        await fetchResult(detail); await refreshHistory()
                        notifyDone("اكتمل تحويل: \(detail.filename)"); return
                    case .partial:
                        announce("اكتمل جزئيًا: نجحت \(detail.donePages) وفشلت \(detail.failedPages) صفحة.")
                        await fetchResult(detail); await refreshHistory()
                        notifyDone("اكتمل تحويل \(detail.filename) جزئيًا"); return
                    case .failed:
                        announce("فشل التحويل: \(detail.error ?? "خطأ غير معروف")"); return
                    }
                } catch { /* transient — keep polling */ }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func fetchResult(_ detail: JobDetail) async {
        do {
            resultURL = try await api.downloadResult(detail, format: outputFormat)
            announce("✅ الملف جاهز — يمكنك معاينته داخل التطبيق أو حفظه ومشاركته.")
        } catch {
            announce("تعذّر تنزيل الملف الناتج: \(error.localizedDescription)")
        }
    }

    func openJob(_ summary: JobSummary) async {
        do {
            let detail = try await api.status(summary.jobId)
            current = detail
            if detail.status == .done || detail.status == .partial { await fetchResult(detail) }
            if detail.status == .processing || detail.status == .keyRequired { startPolling(detail.jobId) }
        } catch { announce("تعذّر فتح المهمة: \(error.localizedDescription)") }
    }

    func openLocal(_ job: LocalJob) { resultURL = LocalStore.url(for: job) }

    func resumeCurrent() async {
        guard let job = current else { return }
        do {
            try await api.resume(job.jobId, encrypted: job.encrypted == true)
            announce("جارٍ إعادة محاولة الصفحات الفاشلة…")
            startPolling(job.jobId)
        } catch { announce("تعذّرت إعادة المحاولة: \(error.localizedDescription)") }
    }

    func refreshHistory() async {
        localHistory = LocalStore.list()
        do { history = try await api.list() } catch { }
    }

    func delete(_ summary: JobSummary) async {
        try? await api.delete(summary.jobId)
        await refreshHistory()
    }

    func deleteLocal(_ job: LocalJob) {
        LocalStore.delete(job)
        localHistory = LocalStore.list()
    }
}

// MARK: - Main View

struct ContentView: View {
    @Bindable var vm: AppViewModel
    @State private var showingFilePicker = false
    @State private var showingBatchPicker = false
    @State private var showingScanner = false
    @State private var showingShareSheet = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingPreview = false
    @State private var showingTranslate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    privacyChip

                    VStack(alignment: .leading, spacing: 6) {
                        Text("نمط التحويل").font(.headline)
                        Picker("نمط التحويل", selection: $vm.mode) {
                            ForEach(ConversionMode.allCases) { Text($0.titleAr).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityValue(vm.mode.titleAr)
                        Text(vm.privacy == .e2e ? "على الجهاز: يُستخرج النص والتعرّف الضوئي محليًا." : vm.mode.hintAr)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text(vm.statusMessage)
                        .font(.title3).fontWeight(.bold).multilineTextAlignment(.center)
                        .padding()
                        .accessibilityLabel("حالة التطبيق: \(vm.statusMessage)")

                    if let job = vm.current, job.status == .processing {
                        ProgressView(value: Double(job.donePages), total: Double(max(job.totalPages, 1)))
                            .accessibilityLabel("التقدم: \(job.donePages) من \(job.totalPages) صفحة")
                    }

                    controls
                }
                .padding()
            }
            .navigationTitle("مُحوّل المستندات")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await vm.refreshHistory() }; showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("سجل التحويلات السابقة")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("الإعدادات")
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(onPick: { urls in if let u = urls.first { vm.selectPDF(u) } })
            }
            .sheet(isPresented: $showingBatchPicker) {
                DocumentPickerView(allowsMultiple: true, onPick: { urls in Task { await vm.startBatch(urls) } })
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { url in vm.selectPDF(url) }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = vm.resultURL { ShareSheetView(activityItems: [url]) }
            }
            .sheet(isPresented: $showingPreview) {
                if let url = vm.resultURL { QuickLookView(url: url) { showingPreview = false } }
            }
            .sheet(isPresented: $showingTranslate) {
                TranslateView(vm: vm)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView(vm: vm, openShare: { showingShareSheet = true })
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(vm: vm)
            }
            .task { await vm.refreshHistory(); vm.requestNotificationPermission() }
        }
    }

    private var privacyChip: some View {
        Button { showingSettings = true } label: {
            HStack {
                Text(vm.privacy.badgeAr).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.left").font(.footnote)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("مستوى الخصوصية: \(vm.privacy.titleAr). اضغط للتغيير من الإعدادات.")
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 16) {
            bigButton(vm.selectedPDFURL == nil ? "اختيار ملف PDF" : "تغيير الملف: \(vm.selectedPDFURL!.lastPathComponent)",
                      icon: "doc.text.viewfinder", color: .blue) { showingFilePicker = true }

            bigButton("مسح بالكاميرا", icon: "camera", color: .teal) { showingScanner = true }
            bigButton("تحويل عدّة ملفات (دفعة)", icon: "square.stack.3d.up", color: .purple) { showingBatchPicker = true }

            if vm.pageCount > 1 { pageRangeSection }

            if vm.selectedPDFURL != nil {
                bigButton(vm.isUploading ? "جارٍ التحويل…" : "ابدأ التحويل",
                          icon: "arrow.up.doc", color: vm.isUploading ? .gray : .green,
                          loading: vm.isUploading) {
                    Task { await vm.startConversion() }
                }
                .disabled(vm.isUploading)
            }

            if vm.batchTotal > 0 {
                Text("الدفعة: \(vm.batchDone) من \(vm.batchTotal)")
                    .font(.headline).foregroundStyle(.secondary)
            }

            if vm.current?.status == .partial {
                bigButton("إعادة محاولة الصفحات التي لم تكتمل", icon: "arrow.clockwise", color: .orange) {
                    Task { await vm.resumeCurrent() }
                }
            }

            if vm.resultURL != nil {
                readyBanner
                bigButton("معاينة الملف داخل التطبيق", icon: "eye", color: .indigo) {
                    showingPreview = true
                }
                bigButton("ترجمة المستند", icon: "character.book.closed", color: .pink) {
                    showingTranslate = true
                }
                bigButton("مشاركة وحفظ الملف", icon: "square.and.arrow.up", color: .orange) {
                    showingShareSheet = true
                }
            }
        }
    }

    private var pageRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("تحويل نطاق صفحات محدّد", isOn: $vm.pageRangeEnabled).font(.headline)
            if vm.pageRangeEnabled {
                HStack {
                    Stepper("من صفحة \(vm.startPage)", value: $vm.startPage, in: 1...vm.pageCount)
                }
                HStack {
                    Stepper("إلى صفحة \(vm.endPage)", value: $vm.endPage, in: vm.startPage...vm.pageCount)
                }
                Text("سيُحوّل من الصفحة \(vm.startPage) إلى \(vm.endPage) من أصل \(vm.pageCount).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var readyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title2)
            Text("اكتمل التحويل — الملف جاهز").fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("اكتمل التحويل، الملف جاهز للمعاينة أو المشاركة")
    }

    private func bigButton(_ title: String, icon: String, color: Color,
                           loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if loading { ProgressView().tint(.white) } else { Image(systemName: icon) }
                Text(title)
            }
            .frame(maxWidth: .infinity).padding()
            .background(color).foregroundStyle(.white).font(.title2)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("الخصوصية والتشفير") {
                    Picker("مستوى الخصوصية", selection: $vm.privacy) {
                        ForEach(EncryptionLevel.allCases) { Text($0.titleAr).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Text(vm.privacy.subtitleAr)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("الذكاء الاصطناعي (للخادم فقط)") {
                    Picker("النموذج", selection: $vm.selectedModel) {
                        ForEach(GoogleModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    if vm.privacy == .e2e {
                        Text("غير مستخدم في وضع طرف-لطرف: القراءة تتم بمحرّك Apple على الجهاز.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("صيغة الملف الناتج") {
                    Picker("الصيغة", selection: $vm.outputFormat) {
                        ForEach(OutputFormat.allCases) { Text($0.titleAr).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if vm.privacy != .e2e {
                    Section("خيارات النص المُيسّر") {
                        Toggle("دقّة حرفية (بلا تعديل من الذكاء)", isOn: $vm.options.faithful)
                        Toggle("اكتشاف العناوين وتنسيقها", isOn: $vm.options.detectHeadings)
                        Toggle("وصف مفصّل للصور المُضمَّنة", isOn: $vm.options.describeImages)
                        Toggle("تحويل الجداول إلى جداول حقيقية", isOn: $vm.options.preserveTables)
                        Toggle("ترقيم الصفحات", isOn: $vm.options.pageNumbers)
                        Picker("صياغة المعادلات الرياضية", selection: $vm.options.math) {
                            ForEach(MathMode.allCases) { Text($0.titleAr).tag($0) }
                        }
                    }
                } else {
                    Section("خيارات التحويل") {
                        Toggle("ترقيم الصفحات", isOn: $vm.options.pageNumbers)
                        Text("في الوضع الصارم يُستخرج النص كما هو من الجهاز؛ خيارات الذكاء غير متاحة لأنها تتطلب الخادم.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("المفتاح محفوظ على هذا الجهاز فقط (Keychain) ولا يُنسخ سحابيًا. إن فقدت الجهاز يتعذّر فك الملفات القديمة.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تم") { dismiss() } } }
        }
    }
}

// MARK: - History (server + on-device)

struct HistoryView: View {
    @Bindable var vm: AppViewModel
    var openShare: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !vm.localHistory.isEmpty {
                    Section("على الجهاز (طرف-لطرف)") {
                        ForEach(vm.localHistory) { job in
                            Button {
                                vm.openLocal(job); dismiss(); openShare()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.filename).font(.headline).lineLimit(1)
                                    Text("🛡️ مشفّر على الجهاز").font(.caption).foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(job.filename)، مشفّر على الجهاز")
                            }
                            .swipeActions {
                                Button("حذف", role: .destructive) { vm.deleteLocal(job) }
                            }
                        }
                    }
                }

                Section("على الخادم") {
                    if vm.history.isEmpty {
                        Text("لا توجد تحويلات على الخادم.").foregroundStyle(.secondary)
                    }
                    ForEach(vm.history) { job in
                        Button {
                            Task { await vm.openJob(job); dismiss(); if vm.resultURL != nil { openShare() } }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.filename).font(.headline).lineLimit(1)
                                Text("\(job.status.titleAr) — \(job.donePages)/\(job.totalPages) صفحة")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(job.filename)، \(job.status.titleAr)، \(job.donePages) من \(job.totalPages) صفحة")
                        }
                        .swipeActions {
                            Button("حذف", role: .destructive) { Task { await vm.delete(job) } }
                        }
                    }
                }
            }
            .navigationTitle("سجل التحويلات")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
            .refreshable { await vm.refreshHistory() }
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    var allowsMultiple: Bool = false
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultiple
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { return }
            parent.onPick(urls)
            UIAccessibility.post(notification: .announcement, argument: "تم اختيار الملف. اضغط بدء التحويل.")
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            UIAccessibility.post(notification: .announcement, argument: "تم إلغاء اختيار الملف.")
        }
    }
}

// MARK: - Camera document scanner (VisionKit)

/// Scans paper with the camera and builds a PDF from the captured pages, then
/// hands its file URL back so it flows through the normal conversion pipeline.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanned: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let doc = PDFDocument()
            for i in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: i)) { doc.insert(page, at: i) }
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("scan-\(UUID().uuidString).pdf")
            if let data = doc.dataRepresentation(), (try? data.write(to: url, options: .atomic)) != nil {
                parent.onScanned(url)
            }
            controller.dismiss(animated: true)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Translation (on-device, Apple Translation framework)

/// Translates the current document text ON DEVICE (nothing is uploaded) and
/// saves the result as a new file. The user picks a target language.
struct TranslateView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var target = "en"
    @State private var config: TranslationSession.Configuration?
    @State private var working = false
    @State private var note = ""

    private let languages: [(code: String, name: String)] = [
        ("en", "الإنجليزية"), ("ar", "العربية"), ("fr", "الفرنسية"),
        ("es", "الإسبانية"), ("de", "الألمانية"), ("tr", "التركية"), ("ur", "الأردية"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("اللغة الهدف") {
                    Picker("اللغة", selection: $target) {
                        ForEach(languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                }
                Section {
                    Button(working ? "جارٍ الترجمة…" : "ترجمة المستند") {
                        note = "جارٍ الترجمة على جهازك…"
                        working = true
                        config = TranslationSession.Configuration(
                            target: Locale.Language(identifier: target))
                    }
                    .disabled(working)
                }
                if !note.isEmpty {
                    Section { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("ترجمة المستند")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } } }
            .translationTask(config) { session in
                do {
                    let source = vm.currentPlainText()
                    let response = try await session.translate(source)
                    vm.saveTranslated(response.targetText, langCode: target)
                    working = false
                    dismiss()
                } catch {
                    working = false
                    note = "تعذّرت الترجمة: قد تحتاج تنزيل حزمة اللغة من إعدادات النظام."
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - In-app preview (QuickLook)

/// Previews the converted file (docx/rtf/txt/pdf) INSIDE the app, so the user
/// can read a sample before saving or sharing — no external app needed.
/// Wraps the preview in a navigation bar with an explicit close ("تم") button,
/// because QLPreviewController shows no dismiss control on its own inside a sheet.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "تم", style: .done, target: context.coordinator, action: #selector(Coordinator.close))
        let nav = UINavigationController(rootViewController: controller)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onClose: onClose) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let onClose: () -> Void
        init(url: URL, onClose: @escaping () -> Void) { self.url = url; self.onClose = onClose }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
        @objc func close() { onClose() }
    }
}
