// ShareInbox.swift
// Receives files handed off by the Share Extension without loading an
// arbitrary PDF or image into memory merely to present the hand-off UI.

import SwiftUI

@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()
    private init() {}

    static let appGroup = "group.com.basir.shared"
    private static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tif", "tiff", "webp", "pdf", "txt"
    ]
    private static let maximumSharedFileBytes: Int64 = 256 * 1_024 * 1_024

    struct Incoming: Identifiable, Equatable {
        let id = UUID()
        let task: String
        let fileURL: URL
        let fileExtension: String
    }

    @Published var pending: Incoming?

    func handle(_ url: URL) {
        guard url.scheme == "basir", url.host == "share" else { return }
        purgeStaleFiles()

        let task = url.lastPathComponent.isEmpty ? "ask" : url.lastPathComponent
        guard ["describe_image", "convert", "ask"].contains(task),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let suppliedName = comps.queryItems?.first(where: { $0.name == "file" })?.value,
              !suppliedName.isEmpty,
              (suppliedName as NSString).lastPathComponent == suppliedName,
              suppliedName.hasPrefix("share-"),
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroup)
        else { return }

        let fileURL = container.appendingPathComponent(suppliedName, isDirectory: false)
        let ext = fileURL.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext),
              FileManager.default.fileExists(atPath: fileURL.path),
              let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? 0) <= Self.maximumSharedFileBytes else {
            return
        }

        pending = Incoming(task: task, fileURL: fileURL, fileExtension: ext)
    }

    func clear(_ incoming: Incoming, deleteFile: Bool = true) {
        guard pending?.id == incoming.id else { return }
        pending = nil
        if deleteFile { try? FileManager.default.removeItem(at: incoming.fileURL) }
    }

    private func purgeStaleFiles() {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroup),
              let files = try? FileManager.default.contentsOfDirectory(
                at: container,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.lastPathComponent.hasPrefix("share-") {
            let modified = (try? file.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
