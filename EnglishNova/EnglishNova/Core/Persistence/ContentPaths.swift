import Foundation

enum ContentPaths {
    static var rootDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("EnglishNova/Content", isDirectory: true)
    }

    static var activeCurriculumURL: URL? {
        rootDirectory?.appendingPathComponent("curriculum.active.json")
    }

    static func prepare() throws {
        guard let rootDirectory else { return }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }
}
