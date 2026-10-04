import Foundation

/// "Word of the day": one real word from the learner's level, the same all
/// day and different tomorrow. Deterministic, offline, and testable.
enum DailyContentEngine {
    static func wordOfTheDay(catalog: CourseCatalog?, level: CEFRLevel, date: Date = .now, calendar: Calendar = .current) -> VocabularyWord? {
        let words = (catalog?.levels.first { $0.level == level }?.units.flatMap(\.lessons).flatMap(\.vocabulary) ?? [])
            .filter { word in
                let example = word.example.lowercased()
                return !word.english.isEmpty && !word.arabic.isEmpty
                    && !example.contains("key word") && !example.contains("today’s") && !example.contains("today's")
            }
        guard !words.isEmpty else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dayNumber = (parts.year ?? 0) * 372 + (parts.month ?? 0) * 31 + (parts.day ?? 0)
        let seed = ExerciseSynthesizer.stableSeed("\(level.rawValue)-\(dayNumber)")
        return words[Int(seed % UInt64(words.count))]
    }
}
