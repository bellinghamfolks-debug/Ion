import CoreLocation
import Foundation

/// Picks the machine nearest to where the person is when the app opens
/// (home, office): one location reading, only when the feature is on, never
/// stored anywhere but the machine's own saved place.
@MainActor
final class LocationSwitcher: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSwitcher()
    /// Within this distance the machine counts as "here".
    static let radius: CLLocationDistance = 200

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// One reading, asking permission the first time.
    func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            // Before permission is answered, the authorization callback asks.
            if waiters.count == 1, manager.authorizationStatus != .notDetermined { manager.requestLocation() }
        }
    }

    func checkNearestMachine(model: AppModel) {
        let placed = model.data.life.machines.filter { $0.latitude != nil && $0.longitude != nil }
        guard placed.count > 1 || (placed.count == 1 && model.data.life.machines.count > 1) else { return }
        Task {
            guard let here = await currentLocation(),
                  let nearest = Self.nearest(to: here, in: placed),
                  nearest.id != model.data.life.activeMachine?.id else { return }
            model.switchMachine(to: nearest, announcement: L("location.switched", nearest.name))
        }
    }

    static func nearest(to location: CLLocation, in machines: [MachineRecord]) -> MachineRecord? {
        machines.compactMap { machine -> (MachineRecord, CLLocationDistance)? in
            guard let lat = machine.latitude, let lon = machine.longitude else { return nil }
            let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
            return distance <= radius ? (machine, distance) : nil
        }
        .min { $0.1 < $1.1 }?.0
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted { self.finish(nil) }
            else if !self.waiters.isEmpty, status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.requestLocation() }
        }
    }
}
