import Foundation

/// One of the machine's four user profiles, mirrored in the app.
struct UserProfile: Codable, Hashable, Identifiable {
    var id: Int                      // 1...4, matches the machine's profile number
    var name: String
    var colorIndex: Int
    /// Personal defaults per drink: "my cappuccino" replaces the standard one.
    var personalDefaults: [BeverageID: Recipe] = [:]
    var favorites: [Recipe] = []
    var history: [BrewRecord] = []

    func recipe(for beverage: BeverageID) -> Recipe {
        personalDefaults[beverage]?.normalized() ?? Recipe.standard(beverage)
    }
}

struct BrewRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var recipe: Recipe
    var date: Date
    var completed: Bool
}

struct AppData: Codable, Equatable {
    static let profileCount = 4
    static let historyLimit = 50

    var profiles: [UserProfile]
    var activeProfileID: Int

    static func initial(names: [String]) -> AppData {
        let profiles = (1...profileCount).map { index in
            UserProfile(id: index, name: names[safe: index - 1] ?? "\(index)", colorIndex: index - 1)
        }
        return AppData(profiles: profiles, activeProfileID: 1)
    }

    var activeProfile: UserProfile {
        get { profiles.first { $0.id == activeProfileID } ?? profiles[0] }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
            profiles[index] = newValue
        }
    }

    mutating func record(_ recipe: Recipe, completed: Bool, at date: Date = Date()) {
        var profile = activeProfile
        profile.history.insert(BrewRecord(recipe: recipe, date: date, completed: completed), at: 0)
        if profile.history.count > Self.historyLimit { profile.history.removeLast(profile.history.count - Self.historyLimit) }
        activeProfile = profile
    }

    /// Adds or replaces a favorite (matched by id). Returns false when an
    /// identical drink with the same name is already saved.
    @discardableResult
    mutating func saveFavorite(_ recipe: Recipe) -> Bool {
        var profile = activeProfile
        let recipe = recipe.normalized()
        if let index = profile.favorites.firstIndex(where: { $0.id == recipe.id }) {
            profile.favorites[index] = recipe
        } else {
            let duplicate = profile.favorites.contains { existing in
                var a = existing; a.id = recipe.id
                return a == recipe
            }
            if duplicate { return false }
            profile.favorites.append(recipe)
        }
        activeProfile = profile
        return true
    }

    mutating func removeFavorite(id: UUID) {
        var profile = activeProfile
        profile.favorites.removeAll { $0.id == id }
        activeProfile = profile
    }

    mutating func moveFavorite(from source: IndexSet, to destination: Int) {
        var profile = activeProfile
        let moving = source.sorted().map { profile.favorites[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { profile.favorites.remove(at: index) }
        profile.favorites.insert(contentsOf: moving, at: max(0, min(insertAt, profile.favorites.count)))
        activeProfile = profile
    }

    mutating func setPersonalDefault(_ recipe: Recipe?) {
        guard let recipe else { return }
        var profile = activeProfile
        let normalized = recipe.normalized()
        if normalized.isStandard {
            profile.personalDefaults[recipe.beverage] = nil
        } else {
            profile.personalDefaults[recipe.beverage] = normalized
        }
        activeProfile = profile
    }

    mutating func resetPersonalDefault(_ beverage: BeverageID) {
        var profile = activeProfile
        profile.personalDefaults[beverage] = nil
        activeProfile = profile
    }

    /// Most-brewed drinks for the active profile, newest first on ties.
    func frequentRecipes(limit: Int = 3) -> [Recipe] {
        var counts: [BeverageID: (count: Int, latest: Recipe)] = [:]
        for record in activeProfile.history where record.completed {
            if let entry = counts[record.recipe.beverage] {
                counts[record.recipe.beverage] = (entry.count + 1, entry.latest)
            } else {
                counts[record.recipe.beverage] = (1, record.recipe)
            }
        }
        return counts.values.sorted { $0.count > $1.count }.prefix(limit).map { $0.latest }
    }
}

/// Saves app data as JSON in Application Support. Writes are atomic; a
/// corrupt file is moved aside instead of silently discarding data.
struct AppDataStore {
    let url: URL

    static var standard: AppDataStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppDataStore(url: base.appendingPathComponent("CoffeeAccess/app-data.json"))
    }

    func load() -> AppData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            var decoded = try JSONDecoder.coffee.decode(AppData.self, from: data)
            if decoded.profiles.count != AppData.profileCount { return nil }
            if !decoded.profiles.contains(where: { $0.id == decoded.activeProfileID }) { decoded.activeProfileID = 1 }
            return decoded
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    func save(_ appData: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.coffee.encode(appData)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension JSONEncoder {
    static var coffee: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var coffee: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
