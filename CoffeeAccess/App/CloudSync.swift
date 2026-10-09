import Foundation
import WidgetKit

enum WidgetReloader {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}

/// Keeps favorites, personal recipes, beans, household and schedules the
/// same on every device signed in to the same iCloud account, through
/// iCloud key-value storage. History stays on each device (it can be large).
/// Works only when this copy of the app was signed with iCloud enabled.
@MainActor
final class CloudSync {
    static let shared = CloudSync()
    private let store = NSUbiquitousKeyValueStore.default
    private let key = "coffee.sync.v1"
    private var observing = false
    private var pendingPush: Task<Void, Never>?
    private let pushedKey = "coffee.sync.lastPush"
    /// True while an iCloud copy is being applied, so it is not pushed back.
    private(set) var applying = false

    /// Pushes a moment after the last change, so a burst of edits is one write.
    func schedulePush(from model: AppModel) {
        pendingPush?.cancel()
        pendingPush = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            push(from: model)
        }
    }

    struct Payload: Codable {
        var profiles: [SyncedProfile]
        var beans: [BeanProfile]
        var household: [HouseholdMember]
        var schedules: [ScheduledBrew]
        var savedAt: Date
    }

    struct SyncedProfile: Codable {
        var id: Int
        var name: String
        var colorIndex: Int
        var favorites: [Recipe]
        var personalDefaults: [BeverageID: Recipe]
    }

    var lastSyncText: String? {
        guard let data = store.data(forKey: key), let payload = try? JSONDecoder.coffee.decode(Payload.self, from: data) else { return nil }
        return payload.savedAt.formatted(date: .abbreviated, time: .shortened)
    }

    func push(from model: AppModel) {
        observe(model)
        let payload = Payload(
            profiles: model.data.profiles.map {
                SyncedProfile(id: $0.id, name: $0.name, colorIndex: $0.colorIndex, favorites: $0.favorites, personalDefaults: $0.personalDefaults)
            },
            beans: model.data.beanProfiles, household: model.data.life.household,
            schedules: model.data.life.scheduledBrews, savedAt: Date())
        guard let data = try? JSONEncoder.coffee.encode(payload), data.count < 900_000 else { return }
        store.set(data, forKey: key)
        store.synchronize()
        UserDefaults.standard.set(payload.savedAt, forKey: pushedKey)
    }

    /// Takes the iCloud copy when it is newer than what this device holds.
    func pull(into model: AppModel) {
        observe(model)
        store.synchronize()
        guard let data = store.data(forKey: key),
              let payload = try? JSONDecoder.coffee.decode(Payload.self, from: data) else { return }
        // Only another device's newer copy replaces what is here.
        if let pushed = UserDefaults.standard.object(forKey: pushedKey) as? Date, payload.savedAt <= pushed { return }
        UserDefaults.standard.set(payload.savedAt, forKey: pushedKey)
        applying = true
        defer { applying = false }
        model.updateData { local in
            for synced in payload.profiles {
                guard let index = local.profiles.firstIndex(where: { $0.id == synced.id }) else { continue }
                local.profiles[index].name = synced.name
                local.profiles[index].colorIndex = synced.colorIndex
                local.profiles[index].favorites = synced.favorites
                local.profiles[index].personalDefaults = synced.personalDefaults
            }
            local.beanProfiles = payload.beans
            if local.activeBeanID.map({ id in !payload.beans.contains { $0.id == id } }) ?? true {
                local.activeBeanID = payload.beans.first?.id
            }
            local.life.household = payload.household
            local.life.scheduledBrews = payload.schedules
        }
        model.rescheduleDrinks()
    }

    private func observe(_ model: AppModel) {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { _ in
            Task { @MainActor in
                if model.settings.iCloudSync { self.pull(into: model) }
            }
        }
    }
}
