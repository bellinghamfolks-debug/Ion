// LastDocumentStore.swift
// Holds the text of the most recently converted document so the user can
// ask follow-up questions about it — the iOS counterpart to Android's
// ConversionState.hasUploadedFile() / showDocumentQAScreen().

import SwiftUI

@MainActor
final class LastDocumentStore: ObservableObject {
    static let shared = LastDocumentStore()
    private init() {}

    @Published var text: String?
    @Published var sourceName: String?

    var hasDocument: Bool { !(text ?? "").isEmpty }

    func set(text: String, sourceName: String) {
        self.text = text
        self.sourceName = sourceName
    }
}
