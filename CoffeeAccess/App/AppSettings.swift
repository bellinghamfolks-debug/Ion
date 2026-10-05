import Foundation

struct AppSettings: Codable, Equatable {
    var linkKind: MachineLinkKind = .demo
    var confirmBeforeBrewing = true
    var announcePhases = true
    var announceProgress = true
    var announceAlarms = true
    var haptics = true
    var speakWithoutVoiceOver = false
    var hasCompletedOnboarding = false

    private static let key = "app.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Tracks one drink from the moment it is ordered until it is in the cup.
struct BrewSession: Equatable, Identifiable {
    enum Outcome: Equatable { case running, finished, stopped, failed(String) }

    let id = UUID()
    let recipe: Recipe
    let startedAt: Date
    var activity: MachineActivity = .grinding
    var progress: Double = 0           // 0...1
    var outcome: Outcome = .running
    var sawMachineBusy = false
    var announcedMilestones: Set<Int> = []

    var isRunning: Bool { outcome == .running }

    /// Progress milestones (in percent) worth announcing, at most once each.
    mutating func milestonesToAnnounce() -> [Int] {
        let percent = Int(progress * 100)
        let due = [25, 50, 75].filter { percent >= $0 && !announcedMilestones.contains($0) }
        announcedMilestones.formUnion(due)
        return due
    }

    /// Bluetooth brewing: infer progress and completion from status polls.
    mutating func update(with snapshot: MachineSnapshot, now: Date = Date()) {
        guard isRunning else { return }
        if snapshot.power == .busy {
            sawMachineBusy = true
            if snapshot.activity != .idle { activity = snapshot.activity }
            if let reported = snapshot.progress {
                progress = max(progress, Double(reported) / 100)
            } else {
                let estimate = now.timeIntervalSince(startedAt) / Double(max(recipe.estimatedSeconds, 1))
                progress = max(progress, min(0.95, estimate))
            }
        } else if snapshot.power == .ready, sawMachineBusy {
            progress = 1
            outcome = .finished
        } else if !sawMachineBusy, now.timeIntervalSince(startedAt) > 15 {
            outcome = .failed(L("brew.error.didNotStart"))
        }
        if isRunning, let blocking = snapshot.blockingAlarms.first, sawMachineBusy, snapshot.power != .busy {
            outcome = .failed(blocking.title)
        }
    }
}
