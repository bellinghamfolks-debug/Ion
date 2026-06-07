// ShareInbox.swift
// Receives content handed off by the Share Extension (BasirShare).
//
// The extension writes the shared file into the App Group container
// "group.com.basir.shared" and opens basir://share/<task>?file=<name>.
// BasirApp forwards that URL here; we read the file back out of the
// shared container and publish it so ContentView can present it.

import SwiftUI

@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()
    private init() {}

    /// Must match the group in Basir.entitlements / BasirShare.entitlements
    /// and the identifier used in ShareViewController.persistAndOpen.
    static let appGroup = "group.com.basir.shared"

    struct Incoming: Identifiable, Equatable {
        let id = UUID()
        let task: String          // "describe_image" | "convert" | "ask"
        let data: Data
        let fileExtension: String
    }

    @Published var pending: Incoming?

    /// Parse basir://share/<task>?file=<name> and load the shared file
    /// out of the App Group container. No-op for any other URL.
    func handle(_ url: URL) {
        guard url.scheme == "basir", url.host == "share" else { return }

        let task = url.lastPathComponent.isEmpty ? "ask" : url.lastPathComponent
        guard
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let name = comps.queryItems?.first(where: { $0.name == "file" })?.value,
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroup),
            let data = try? Data(contentsOf: container.appendingPathComponent(name))
        else { return }

        pending = Incoming(
            task: task,
            data: data,
            fileExtension: (name as NSString).pathExtension.lowercased()
        )
    }
}
