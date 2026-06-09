import Foundation

struct BundledContentLoader {
    enum LoaderError: Error { case missingResource, decoding(Error) }

    func loadCatalog() throws -> CourseCatalog {
        let bundledURL = Bundle.main.url(forResource: "curriculum", withExtension: "json", subdirectory: "Curriculum")
            ?? Bundle.main.url(forResource: "curriculum", withExtension: "json")
        let url: URL
        if let active = ContentPaths.activeCurriculumURL, FileManager.default.fileExists(atPath: active.path) {
            url = active
        } else if let bundledURL {
            url = bundledURL
        } else {
            throw LoaderError.missingResource
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CourseCatalog.self, from: data)
        } catch {
            throw LoaderError.decoding(error)
        }
    }
}
