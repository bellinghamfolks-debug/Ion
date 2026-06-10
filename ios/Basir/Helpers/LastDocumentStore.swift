// LastDocumentStore.swift
// Holds a bounded copy of the most recently converted document so the user can
// ask grounded follow-up questions without letting one huge file exhaust memory.

import SwiftUI

@MainActor
final class LastDocumentStore: ObservableObject {
    static let shared = LastDocumentStore()
    static let maximumCharacters = 2_000_000

    private init() {}

    @Published private(set) var text: String?
    @Published private(set) var sourceName: String?
    @Published private(set) var wasTruncated = false

    var hasDocument: Bool { !(text ?? "").isEmpty }

    func set(text: String, sourceName: String) {
        let trimmedName = String(sourceName.prefix(1_000))
        if text.count > Self.maximumCharacters {
            self.text = String(text.prefix(Self.maximumCharacters))
            wasTruncated = true
        } else {
            self.text = text
            wasTruncated = false
        }
        self.sourceName = trimmedName
    }

    func clear() {
        text = nil
        sourceName = nil
        wasTruncated = false
    }
}
