import CryptoKit
import Foundation

actor JobStore {
    static let shared = JobStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    let rootURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("ApplicationSupport", isDirectory: true)
        rootURL = base.appendingPathComponent("PDFToWord", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? (rootURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }

    func createWorkspace(
        sourceURL: URL,
        pageCount: Int,
        options: ConversionOptions
    ) throws -> ConversionJobRecord {
        let id = UUID()
        let workspace = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let pages = workspace.appendingPathComponent("pages", isDirectory: true)

        do {
            try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
            try (workspace as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)

            let sourceCopy = workspace.appendingPathComponent("source.pdf")
            let staging = workspace.appendingPathComponent("source.staging")
            try fileManager.copyItem(at: sourceURL, to: staging)
            try (staging as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            try fileManager.moveItem(at: staging, to: sourceCopy)
            let fingerprint = try Self.sha256(of: sourceCopy)

            let record = ConversionJobRecord(
                id: id,
                sourceName: sourceURL.deletingPathExtension().lastPathComponent,
                createdAt: Date(),
                updatedAt: Date(),
                totalPages: pageCount,
                completedPages: 0,
                status: .queued,
                outputPath: nil,
                workspacePath: workspace.path,
                errorMessage: nil,
                formatVersion: 4,
                sourceSHA256: fingerprint,
                optionsSnapshot: options,
                fallbackPages: [],
                warnings: [],
                outputSHA256: nil,
                outputByteCount: nil,
                minimumQualityScore: nil,
                handwrittenPages: []
            )
            try save(record)
            return record
        } catch {
            try? fileManager.removeItem(at: workspace)
            throw error
        }
    }

    /// Saves a manifest atomically and keeps the last known-good manifest as a recovery copy.
    func save(_ record: ConversionJobRecord) throws {
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        let url = workspace.appendingPathComponent("job.json")
        let backup = workspace.appendingPathComponent("job.previous.json")

        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
            try (backup as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        }

        do {
            try encoder.encode(record).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            if !fileManager.fileExists(atPath: url.path), fileManager.fileExists(atPath: backup.path) {
                try? fileManager.copyItem(at: backup, to: url)
            }
            throw error
        }
    }

    func clearAnalyses(for record: ConversionJobRecord) throws {
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        let pages = workspace.appendingPathComponent("pages", isDirectory: true)
        if fileManager.fileExists(atPath: pages.path) {
            try fileManager.removeItem(at: pages)
        }
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        try (pages as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }

    func saveAnalysis(_ analysis: PageAnalysis, in record: ConversionJobRecord) throws {
        guard (1...record.totalPages).contains(analysis.pageNumber) else {
            throw JobStoreError.invalidPageNumber(analysis.pageNumber)
        }
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        let pages = workspace.appendingPathComponent("pages", isDirectory: true)
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        let url = pages.appendingPathComponent("page-\(analysis.pageNumber).json")
        try encoder.encode(analysis).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func loadAnalyses(for record: ConversionJobRecord) throws -> [PageAnalysis] {
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        let pagesURL = workspace.appendingPathComponent("pages", isDirectory: true)
        guard fileManager.fileExists(atPath: pagesURL.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: pagesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }

        var seen = Set<Int>()
        var analyses: [PageAnalysis] = []
        for file in files {
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let data = try Data(contentsOf: file)
                let analysis = try decoder.decode(PageAnalysis.self, from: data)
                guard (1...record.totalPages).contains(analysis.pageNumber) else {
                    throw JobStoreError.invalidPageNumber(analysis.pageNumber)
                }
                let expectedName = "page-\(analysis.pageNumber).json"
                guard file.lastPathComponent == expectedName else {
                    throw JobStoreError.filePageMismatch(file.lastPathComponent, analysis.pageNumber)
                }
                guard seen.insert(analysis.pageNumber).inserted else {
                    throw JobStoreError.duplicatePage(analysis.pageNumber)
                }
                analyses.append(analysis)
            } catch let error as JobStoreError {
                throw error
            } catch {
                throw JobStoreError.corruptAnalysis(file.lastPathComponent)
            }
        }
        return analyses.sorted { $0.pageNumber < $1.pageNumber }
    }

    func verifySourceIntegrity(for record: ConversionJobRecord) throws -> URL {
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        let source = workspace.appendingPathComponent("source.pdf")
        guard fileManager.fileExists(atPath: source.path) else { throw JobStoreError.sourceMissing }
        if let expected = record.sourceSHA256, !expected.isEmpty {
            let current = try Self.sha256(of: source)
            guard current == expected else { throw JobStoreError.sourceChanged }
        }
        return source
    }

    func fingerprint(of url: URL) throws -> String {
        try Self.sha256(of: url)
    }

    func byteCount(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw JobStoreError.outputMissing }
        return Int64(values.fileSize ?? 0)
    }

    func loadAll() -> [ConversionJobRecord] {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders.compactMap { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return loadRecordRecoveringIfNeeded(from: folder)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ record: ConversionJobRecord) throws {
        let workspace = URL(fileURLWithPath: record.workspacePath, isDirectory: true)
        try validateWorkspace(workspace)
        guard workspace.standardizedFileURL.path != rootURL.standardizedFileURL.path else {
            throw JobStoreError.invalidWorkspace
        }
        if fileManager.fileExists(atPath: workspace.path) {
            try fileManager.removeItem(at: workspace)
        }
    }

    private func loadRecordRecoveringIfNeeded(from folder: URL) -> ConversionJobRecord? {
        let manifest = folder.appendingPathComponent("job.json")
        let backup = folder.appendingPathComponent("job.previous.json")

        if let record = decodeRecord(at: manifest), recordBelongsToFolder(record, folder: folder) {
            return record
        }
        guard var recovered = decodeRecord(at: backup), recordBelongsToFolder(recovered, folder: folder) else {
            return nil
        }

        var warnings = Set(recovered.warnings ?? [])
        warnings.insert(L10n.text("استُعيد سجل المهمة من النسخة الاحتياطية بعد تعذر قراءة آخر سجل محفوظ."))
        recovered.warnings = warnings.sorted()
        recovered.status = .failed
        recovered.errorMessage = L10n.text("توقف الحفظ السابق قبل اكتماله. استُعيدت آخر حالة سليمة ويمكن استئناف المهمة.")
        recovered.updatedAt = Date()
        try? encoder.encode(recovered).write(to: manifest, options: [.atomic, .completeFileProtection])
        return recovered
    }

    private func decodeRecord(at url: URL) -> ConversionJobRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ConversionJobRecord.self, from: data)
    }

    private func recordBelongsToFolder(_ record: ConversionJobRecord, folder: URL) -> Bool {
        let expected = folder.standardizedFileURL.path
        let actual = URL(fileURLWithPath: record.workspacePath, isDirectory: true).standardizedFileURL.path
        return expected == actual
    }

    private func validateWorkspace(_ workspace: URL) throws {
        let standardizedRoot = rootURL.standardizedFileURL.path
        let standardizedWorkspace = workspace.standardizedFileURL.path
        guard standardizedWorkspace == standardizedRoot || standardizedWorkspace.hasPrefix(standardizedRoot + "/") else {
            throw JobStoreError.invalidWorkspace
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum JobStoreError: LocalizedError {
    case invalidWorkspace
    case sourceMissing
    case sourceChanged
    case outputMissing
    case invalidPageNumber(Int)
    case duplicatePage(Int)
    case corruptAnalysis(String)
    case filePageMismatch(String, Int)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace:
            return L10n.text("مسار مساحة العمل غير صالح.")
        case .sourceMissing:
            return L10n.text("النسخة المحلية من ملف PDF غير موجودة.")
        case .sourceChanged:
            return L10n.text("فشل فحص سلامة نسخة PDF المحلية؛ قد يكون الملف تالفًا أو تغير محتواه.")
        case .outputMissing:
            return L10n.text("ملف Word الناتج غير موجود أو ليس ملفًا عاديًا.")
        case .invalidPageNumber(let page):
            return L10n.format("عُثر على نتيجة محفوظة برقم صفحة غير صالح: %d.", page)
        case .duplicatePage(let page):
            return L10n.format("عُثر على نتيجتين محفوظتين للصفحة %d.", page)
        case .corruptAnalysis(let name):
            return L10n.format("ملف نتيجة الصفحة %@ تالف ولا يمكن استئناف التحويل بأمان.", name)
        case .filePageMismatch(let name, let page):
            return L10n.format("اسم ملف النتيجة %@ لا يطابق رقم الصفحة المحفوظ داخله (%d).", name, page)
        }
    }
}
