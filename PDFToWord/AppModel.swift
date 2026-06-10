import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedPDF: URL?
    @Published var selectedPageCount: Int?
    @Published var records: [ConversionJobRecord] = []
    @Published var currentRecord: ConversionJobRecord?
    @Published var progress = ConversionProgress(status: .queued, currentPage: 0, totalPages: 0, message: "")
    @Published var isConverting = false
    @Published var isPreparingFile = false
    @Published var alertMessage: String?
    @Published var keyStatusMessage: String?
    @Published var isTestingKey = false
    @Published var verifiedModels: [String] = []

    private let engine = ConversionEngine()
    private let store = JobStore.shared
    private let gemini = GeminiClient()
    private var conversionTask: Task<Void, Never>?

    init() {
        refreshRecords()
        DiagnosticsLog.shared.record("session", "App launched.")
    }

    var hasAPIKey: Bool {
        do {
            return !(try KeychainStore.shared.readAPIKey() ?? "").isEmpty
        } catch {
            // Avoid publishing state while SwiftUI is evaluating this property.
            // Action methods still surface the concrete Keychain error to the user.
            return false
        }
    }

    /// Builds a complete diagnostics report and writes it to a temporary file
    /// for sharing. `extra` carries Settings-only fields (model, thinking).
    func writeDiagnostics(extra: [String: String]) async -> URL? {
        var header = extra
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        header["App version"] = "\(short) (build \(build))"
        header["Gemini key"] = hasAPIKey ? "present" : "absent"
        header["Stored records"] = "\(records.count)"
        header["Selected file"] = selectedPDF?.lastPathComponent ?? "none"
        header["Selected pages"] = selectedPageCount.map(String.init) ?? "?"
        let text = await DiagnosticsLog.shared.export(header: header)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDFToWord-Diagnostics.txt")
        do {
            try Data(text.utf8).write(to: url, options: [.atomic])
            return url
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }

    func clearDiagnostics() {
        Task { await DiagnosticsLog.shared.clear() }
    }

    func selectPDF(_ url: URL) {
        guard !isPreparingFile else { return }
        DiagnosticsLog.shared.record("file", "selectPDF tapped | source:\(url.lastPathComponent)")
        isPreparingFile = true
        alertMessage = nil
        // Materializing an iCloud / provider file (and reading it) can block,
        // so do it off the main actor and keep the UI responsive with a
        // "preparing" state instead of appearing frozen.
        Task {
            let outcome: Result<(URL, Int), Error> = await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    // Copy the picked file into our sandbox now, while access
                    // is granted. iCloud/provider files may not be on disk yet,
                    // so a direct PDFDocument(url:) can fail silently. A
                    // coordinated read downloads/materializes the file, and the
                    // local copy stays readable for the whole conversion.
                    let localURL = try Self.importToSandbox(url)
                    let extractor = try PDFPageExtractor(url: localURL)
                    guard extractor.pageCount > 0 else { throw ConversionEngineError.emptyDocument }
                    return .success((localURL, extractor.pageCount))
                } catch {
                    return .failure(error)
                }
            }.value

            isPreparingFile = false
            switch outcome {
            case .success(let (localURL, count)):
                selectedPDF = localURL
                selectedPageCount = count
                currentRecord = nil
                let bytes = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int) ?? nil
                DiagnosticsLog.shared.record("file", "selected OK | name:\(localURL.lastPathComponent) | pages:\(count) | size:\((bytes ?? 0) / 1024)KB")
            case .failure(let error):
                selectedPDF = nil
                selectedPageCount = nil
                alertMessage = error.localizedDescription
                DiagnosticsLog.shared.record("file✗", "select failed | \(error.localizedDescription)")
            }
        }
    }

    /// Copies a picked PDF into the app's caches via a coordinated read so
    /// iCloud/provider files are materialized and stay readable independent of
    /// the security-scoped URL's lifetime. Returns the local copy's URL.
    nonisolated private static func importToSandbox(_ url: URL) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedPDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep only the most recent import to avoid unbounded cache growth.
        if let existing = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in existing { try? FileManager.default.removeItem(at: file) }
        }
        // Keep the original file name so the produced Word document is named
        // after the source (not an opaque UUID). The directory is cleared
        // above, so there is no collision to disambiguate.
        let baseName = url.deletingPathExtension().lastPathComponent
        let safeBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString
            : baseName
        let destination = directory.appendingPathComponent(safeBaseName).appendingPathExtension("pdf")

        var coordinationError: NSError?
        var readData: Data?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            do { readData = try Data(contentsOf: readURL, options: [.mappedIfSafe]) }
            catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let data = readData, !data.isEmpty else { throw PDFExtractionError.cannotOpen }
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func startConversion(options: ConversionOptions) {
        guard !isConverting, let selectedPDF else {
            DiagnosticsLog.shared.record("convert", "startConversion ignored | isConverting:\(isConverting) | hasFile:\(selectedPDF != nil)")
            return
        }
        guard let key = storedAPIKey(), !key.isEmpty else {
            alertMessage = L10n.text("أضف مفتاح Gemini API من الإعدادات أولًا.")
            DiagnosticsLog.shared.record("convert✗", "no API key saved")
            return
        }
        DiagnosticsLog.shared.record("convert", "startConversion | file:\(selectedPDF.lastPathComponent) | model:\(options.model) | thinking:\(options.thinkingLevel)")

        progress = .init(status: .queued, currentPage: 0, totalPages: selectedPageCount ?? 0, message: L10n.text("بدء التحويل"))
        currentRecord = nil
        isConverting = true
        alertMessage = nil
        conversionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isConverting = false
                self.conversionTask = nil
            }
            do {
                let record = try await self.engine.convertNew(
                    sourceURL: selectedPDF,
                    apiKey: key,
                    options: options
                ) { update in
                    await MainActor.run { self.progress = update }
                }
                self.currentRecord = record
                self.refreshRecords()
            } catch is CancellationError {
                self.refreshRecords()
            } catch {
                self.alertMessage = error.localizedDescription
                self.refreshRecords()
            }
        }
    }

    func resume(_ record: ConversionJobRecord, options: ConversionOptions) {
        guard !isConverting else { return }
        guard let key = storedAPIKey(), !key.isEmpty else {
            alertMessage = L10n.text("أضف مفتاح Gemini API من الإعدادات أولًا.")
            return
        }

        currentRecord = record
        progress = .init(
            status: record.status,
            currentPage: record.completedPages,
            totalPages: record.totalPages,
            message: record.optionsSnapshot == nil
                ? L10n.text("استئناف مهمة قديمة بالإعدادات الحالية")
                : L10n.text("استئناف التحويل بإعداداته المحفوظة")
        )
        isConverting = true
        alertMessage = nil
        conversionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isConverting = false
                self.conversionTask = nil
            }
            do {
                let updated = try await self.engine.resume(
                    record: record,
                    apiKey: key,
                    options: options
                ) { update in
                    await MainActor.run { self.progress = update }
                }
                self.currentRecord = updated
                self.refreshRecords()
            } catch is CancellationError {
                self.refreshRecords()
            } catch {
                self.alertMessage = error.localizedDescription
                self.refreshRecords()
            }
        }
    }

    func cancelConversion() {
        conversionTask?.cancel()
    }

    @discardableResult
    func saveAPIKey(_ key: String) -> Bool {
        do {
            try KeychainStore.shared.saveAPIKey(key)
            keyStatusMessage = L10n.text("حُفظ المفتاح داخل Keychain على هذا الجهاز. اختبره مع النموذج المحدد قبل أول تحويل.")
            verifiedModels = []
            objectWillChange.send()
            return true
        } catch {
            keyStatusMessage = error.localizedDescription
            return false
        }
    }

    func deleteAPIKey() {
        do {
            try KeychainStore.shared.deleteAPIKey()
            keyStatusMessage = L10n.text("حُذف المفتاح من الجهاز.")
            verifiedModels = []
            objectWillChange.send()
        } catch {
            keyStatusMessage = error.localizedDescription
        }
    }

    func testAPIKey(_ enteredKey: String, model: String) {
        let typed = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? (storedAPIKey() ?? "") : typed
        guard !key.isEmpty else {
            keyStatusMessage = L10n.text("أدخل المفتاح أو احفظه أولًا.")
            return
        }

        isTestingKey = true
        keyStatusMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isTestingKey = false }
            do {
                let models = try await self.gemini.validateKey(key, model: model)
                self.verifiedModels = models.map(\.shortName)
                if typed.isEmpty {
                    self.keyStatusMessage = L10n.format("نجح المفتاح المحفوظ والنموذج %@ في طلب إخراج منظم فعلي. عُثر على %d نموذجًا يدعم توليد المحتوى.", model, models.count)
                } else {
                    self.keyStatusMessage = L10n.format("نجح المفتاح المُدخل والنموذج %@ في طلب إخراج منظم فعلي. احفظ المفتاح قبل بدء التحويل.", model)
                }
            } catch {
                self.verifiedModels = []
                self.keyStatusMessage = error.localizedDescription
            }
        }
    }

    func refreshRecords() {
        Task { [weak self] in
            guard let self else { return }
            self.records = await self.store.loadAll()
        }
    }

    func deleteRecord(_ record: ConversionJobRecord) {
        Task { [weak self] in
            guard let self else { return }
            do {
                if let outputPath = record.outputPath {
                    let outputURL = URL(fileURLWithPath: outputPath)
                    if self.isSafeOutputURL(outputURL), FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                }
                try await self.store.delete(record)
                if self.currentRecord?.id == record.id { self.currentRecord = nil }
                self.refreshRecords()
            } catch {
                self.alertMessage = error.localizedDescription
            }
        }
    }

    func outputURL(for record: ConversionJobRecord) -> URL? {
        guard let path = record.outputPath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard isSafeOutputURL(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let expectedBytes = record.outputByteCount {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let actualBytes = (attributes[.size] as? NSNumber)?.int64Value,
                  actualBytes == expectedBytes else { return nil }
        }
        return url
    }

    private func storedAPIKey() -> String? {
        do {
            return try KeychainStore.shared.readAPIKey()
        } catch {
            keyStatusMessage = error.localizedDescription
            return nil
        }
    }

    private func isSafeOutputURL(_ url: URL) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let root = documents.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate.hasPrefix(root + "/") && url.pathExtension.lowercased() == "docx"
    }
}

import UIKit

/// Captures a precise, shareable diagnostic timeline of everything the app
/// does — environment, file selection, every Gemini request/response with
/// timings and verbatim errors, per-page outcomes, and conversion totals.
/// The Gemini API key is never recorded (only its presence/length).
actor DiagnosticsLog {
    static let shared = DiagnosticsLog()

    struct Entry: Sendable {
        let time: Date
        let category: String
        let message: String
    }

    private var entries: [Entry] = []
    private let maxEntries = 8000
    private let sessionStart = Date()

    /// Fire-and-forget logging usable from any context (no await needed).
    nonisolated func record(_ category: String, _ message: String) {
        Task { await self.append(category: category, message: message) }
    }

    private func append(category: String, message: String) {
        entries.append(Entry(time: Date(), category: category, message: message))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    func clear() {
        entries.removeAll()
        entries.append(Entry(time: Date(), category: "session", message: "Diagnostics cleared."))
    }

    func entryCount() -> Int { entries.count }

    /// Builds the full report. `header` carries main-actor-only environment
    /// (app version, model/thinking, key presence) gathered by the caller.
    func export(header: [String: String]) -> String {
        let now = Date()
        let stamp = ISO8601DateFormatter()
        let line = DateFormatter()
        line.locale = Locale(identifier: "en_US_POSIX")
        line.dateFormat = "HH:mm:ss.SSS"

        var out = "# PDFToWord Diagnostics\n"
        out += "Generated: \(stamp.string(from: now))\n"
        out += "Session uptime: \(String(format: "%.1f", now.timeIntervalSince(sessionStart)))s\n"
        out += "Entries: \(entries.count)\n\n"

        out += "## Environment\n"
        for key in header.keys.sorted() { out += "- \(key): \(header[key] ?? "")\n" }
        out += "- iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "- Device: \(Self.deviceModelIdentifier())\n"
        out += "- Active processors: \(ProcessInfo.processInfo.activeProcessorCount)\n"
        out += "- Physical memory: \(ProcessInfo.processInfo.physicalMemory / (1024*1024)) MB\n"
        out += "- Low power mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)\n\n"

        out += "## Timeline\n"
        if entries.isEmpty {
            out += "(empty — perform a conversion, then save again)\n"
        } else {
            let base = entries.first!.time
            for e in entries {
                let delta = e.time.timeIntervalSince(base)
                out += "[\(line.string(from: e.time))] (+\(String(format: "%7.3f", delta))s) [\(e.category)] \(e.message)\n"
            }
        }
        return out
    }

    nonisolated static func deviceModelIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.compactMap { ($0.value as? Int8).map { Character(UnicodeScalar(UInt8(bitPattern: $0))) } }
            .filter { $0 != "\0" }
        return String(id)
    }
}
