import CryptoKit
import Foundation
import Combine

@MainActor
final class AudioPackService: ObservableObject {
    @Published private(set) var packs: [AudioPackDescriptor] = []
    @Published private(set) var states: [String: AudioPackState] = [:]
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let apiClient: APIClient
    private let store: FileStore
    private let folder = "AudioPacks"

    init(apiClient: APIClient, store: FileStore) {
        self.apiClient = apiClient
        self.store = store
        self.packs = Self.systemVoicePacks
        for pack in Self.systemVoicePacks { states[pack.id] = .ready(size: 0) }
    }

    func loadLocalState() async {
        for pack in packs where !pack.clips.isEmpty {
            do {
                let complete = try await pack.clips.asyncAllSatisfy { clip in
                    try await store.exists("\(folder)/\(pack.id)/\(clip.relativePath)")
                }
                if complete {
                    let size = try await store.size(ofDirectory: "\(folder)/\(pack.id)")
                    states[pack.id] = .ready(size: size)
                } else {
                    states[pack.id] = .notDownloaded
                }
            } catch {
                states[pack.id] = .notDownloaded
            }
        }
    }

    func refreshIndex() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let index = try await apiClient.get(path: "v1/audio-packs/index", response: AudioPackIndex.self)
            packs = Self.systemVoicePacks + index.packs
            for pack in index.packs where states[pack.id] == nil { states[pack.id] = .notDownloaded }
            await loadLocalState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ pack: AudioPackDescriptor) async {
        guard !pack.clips.isEmpty else {
            states[pack.id] = .ready(size: 0)
            return
        }
        states[pack.id] = .downloading(progress: 0)
        do {
            for (index, clip) in pack.clips.enumerated() {
                guard clip.remoteURL.scheme?.lowercased() == "https" else {
                    throw AudioPackError.insecureURL
                }
                let (data, response) = try await URLSession.shared.data(from: clip.remoteURL)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw AudioPackError.invalidResponse
                }
                guard data.count <= 100 * 1_024 * 1_024 else { throw AudioPackError.clipTooLarge }
                if let expected = clip.sha256, !expected.isEmpty {
                    let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                        throw AudioPackError.checksumMismatch
                    }
                }
                try await store.writeData(data, to: "\(folder)/\(pack.id)/\(clip.relativePath)")
                states[pack.id] = .downloading(progress: Double(index + 1) / Double(pack.clips.count))
            }
            let size = try await store.size(ofDirectory: "\(folder)/\(pack.id)")
            states[pack.id] = .ready(size: size)
        } catch {
            states[pack.id] = .failed(error.localizedDescription)
        }
    }

    func delete(_ pack: AudioPackDescriptor) async {
        guard !pack.clips.isEmpty else { return }
        do {
            try await store.deleteDirectory("\(folder)/\(pack.id)")
            states[pack.id] = .notDownloaded
        } catch {
            states[pack.id] = .failed(error.localizedDescription)
        }
    }

    func localURL(for clip: AudioClipDescriptor, in pack: AudioPackDescriptor) async -> URL? {
        let name = "\(folder)/\(pack.id)/\(clip.relativePath)"
        guard (try? await store.exists(name)) == true else { return nil }
        return try? await store.url(for: name)
    }

    private static let systemVoicePacks: [AudioPackDescriptor] = [
        AudioPackDescriptor(
            id: "system-voice-a0-a1",
            titleAr: "النطق النظامي للمستويين A0 وA1",
            titleEn: "System Voice A0–A1",
            level: .a0,
            voiceName: "صوت iOS الإنجليزي المتاح على الجهاز",
            approximateBytes: 0,
            version: 1,
            clips: []
        )
    ]
}

enum AudioPackError: LocalizedError {
    case insecureURL
    case invalidResponse
    case clipTooLarge
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .insecureURL: return "يجب أن تستخدم ملفات الصوت اتصال HTTPS آمنًا."
        case .invalidResponse: return "لم يرسل خادم الصوت استجابة صالحة."
        case .clipTooLarge: return "ملف الصوت أكبر من الحد الآمن للتنزيل."
        case .checksumMismatch: return "فشل التحقق من سلامة ملف صوتي."
        }
    }
}

private extension Array {
    func asyncAllSatisfy(_ predicate: (Element) async throws -> Bool) async rethrows -> Bool {
        for element in self {
            if try await predicate(element) == false { return false }
        }
        return true
    }
}
