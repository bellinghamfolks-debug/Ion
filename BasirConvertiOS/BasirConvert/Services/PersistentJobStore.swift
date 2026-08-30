import Foundation
import Combine

actor PersistentJobStore {
    private let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init() {
        let root = (try? FileAccess.persistentJobsDirectory()) ?? FileManager.default.temporaryDirectory
        storeURL = root.appendingPathComponent("jobs.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [BasirJob] {
        guard let data = try? Data(contentsOf: storeURL),
              var jobs = try? decoder.decode([BasirJob].self, from: data) else { return [] }
        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .paused
            jobs[index].automaticResumePending = true
            jobs[index].progress = ConversionProgress(
                current: jobs[index].progress.current,
                total: jobs[index].progress.total,
                stage: .paused,
                detail: jobs[index].progress.detail,
                succeeded: jobs[index].progress.succeeded,
                failed: jobs[index].progress.failed
            )
        }
        return jobs.filter { FileManager.default.fileExists(atPath: $0.sourcePath) || $0.resultPath != nil }
    }

    func save(_ jobs: [BasirJob]) throws {
        let data = try encoder.encode(jobs)
        try data.write(to: storeURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func removeFiles(for job: BasirJob, keepingResult: Bool = true) {
        let source = job.sourceURL
        let parent = source.deletingLastPathComponent()
        let root = (try? FileAccess.persistentJobsDirectory().standardizedFileURL)
        if parent.standardizedFileURL.deletingLastPathComponent() == root {
            try? FileManager.default.removeItem(at: parent)
        }
        if !keepingResult, let result = job.resultURL { try? FileAccess.deleteOutput(result) }
    }
}

struct OutputRecord: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let byteCount: Int64
    let createdAt: Date
    let sourceName: String?
    let operation: OperationKind?
    let languageCode: String?
    let itemCount: Int?
    let imageCount: Int?

    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var humanReadableSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}

private struct OutputSidecar: Codable {
    let sourceName: String
    let operation: OperationKind
    let languageCode: String
    let itemCount: Int?
    let imageCount: Int?
    let requestID: String
    let sourceChecksum: String?
}

@MainActor
final class OutputLibraryStore: ObservableObject {
    @Published private(set) var items: [OutputRecord] = []
    @Published var errorMessage: String?

    func refresh() {
        do {
            items = try FileAccess.listOutputs().map { url in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
                let sidecar = Self.sidecar(for: url)
                return OutputRecord(
                    id: url.path,
                    url: url,
                    byteCount: Int64(values.fileSize ?? 0),
                    createdAt: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                    sourceName: sidecar?.sourceName,
                    operation: sidecar?.operation,
                    languageCode: sidecar?.languageCode,
                    itemCount: sidecar?.itemCount,
                    imageCount: sidecar?.imageCount
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func writeMetadata(for output: URL, job: BasirJob, imageCount: Int? = nil) {
        let sidecar = OutputSidecar(
            sourceName: job.sourceName,
            operation: job.options.operation,
            languageCode: job.options.targetLanguage?.code ?? "auto",
            itemCount: job.sourceMetadata?.itemCount,
            imageCount: imageCount,
            requestID: job.requestID,
            sourceChecksum: job.sourceMetadata?.checksum
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(sidecar).write(to: FileAccess.sidecarURL(for: output), options: .atomic)
        refresh()
    }

    func rename(_ item: OutputRecord, to name: String) throws -> URL {
        let url = try FileAccess.renameOutput(item.url, to: name)
        refresh()
        return url
    }

    func delete(_ item: OutputRecord) throws {
        try FileAccess.deleteOutput(item.url)
        refresh()
    }

    private static func sidecar(for output: URL) -> OutputSidecar? {
        guard let data = try? Data(contentsOf: FileAccess.sidecarURL(for: output)) else { return nil }
        return try? JSONDecoder().decode(OutputSidecar.self, from: data)
    }
}

