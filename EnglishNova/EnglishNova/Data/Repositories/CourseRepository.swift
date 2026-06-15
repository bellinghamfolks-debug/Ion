import Foundation

actor CourseRepository: CourseRepositoryProtocol {
    private let loader: BundledContentLoader
    private var cache: CourseCatalog?

    init(loader: BundledContentLoader) { self.loader = loader }

    func catalog() async throws -> CourseCatalog {
        if let cache { return cache }
        let value = try loader.loadCatalog()
        cache = value
        return value
    }

    func refresh() async throws -> CourseCatalog {
        cache = nil
        return try await catalog()
    }

    func lesson(id: String) async throws -> Lesson? {
        let catalog = try await catalog()
        return catalog.levels.lazy.flatMap(\.units).lazy.flatMap(\.lessons).first { $0.id == id }
    }
}
