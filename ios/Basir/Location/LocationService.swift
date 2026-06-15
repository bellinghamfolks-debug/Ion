// LocationService.swift
// CoreLocation wrapper for emergency mode and walking mode.
//
// One-shot fetch only — Basir does not need background location and
// must not ask for "Always" authorisation (Apple rejects apps that
// request more access than they justify).

import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    enum AuthState { case undetermined, denied, restricted, whenInUse, always }

    @Published private(set) var authorization: AuthState = .undetermined
    @Published private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var oneShotContinuation: CheckedContinuation<CLLocation?, Never>?
    private var oneShotTimeoutTask: Task<Void, Never>?
    private var locationRequestStartedAt: Date?
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var authTimeoutTask: Task<Void, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateAuthState()
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Fetch one location reading, asking for permission first if needed.
    /// Returns nil on denial, cancellation, or timeout. Every continuation
    /// is resumed exactly once, including when Core Location never calls back.
    func fetchOnce(timeout: TimeInterval = 8) async -> CLLocation? {
        let boundedTimeout = max(1, min(timeout, 30))
        if authorization == .undetermined {
            await waitForAuthorization(timeout: max(15, boundedTimeout))
        }
        guard !Task.isCancelled,
              authorization == .whenInUse || authorization == .always else {
            return nil
        }
        return await requestOneLocation(timeout: boundedTimeout)
    }

    private func waitForAuthorization(timeout: TimeInterval) async {
        // Only one permission waiter may exist. Resolve an older waiter rather
        // than overwriting its checked continuation and leaking the task.
        finishAuthorizationWait()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
                authTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.finishAuthorizationWait() }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishAuthorizationWait()
            }
        }
    }

    private func requestOneLocation(timeout: TimeInterval) async -> CLLocation? {
        // Avoid overwriting an in-flight continuation. A newer request wins,
        // while the older caller receives nil immediately.
        finishLocationRequest(with: nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                oneShotContinuation = continuation
                locationRequestStartedAt = Date()
                manager.requestLocation()
                oneShotTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.finishLocationRequest(with: nil) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishLocationRequest(with: nil)
            }
        }
    }

    private func finishAuthorizationWait() {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume()
    }

    private func finishLocationRequest(with location: CLLocation?) {
        oneShotTimeoutTask?.cancel()
        oneShotTimeoutTask = nil
        locationRequestStartedAt = nil
        guard let continuation = oneShotContinuation else { return }
        oneShotContinuation = nil
        continuation.resume(returning: location)
    }

    /// Format a coordinate as a Google Maps link (works on any
    /// messaging app, no Apple-specific URL scheme).
    static func mapsLink(for coord: CLLocationCoordinate2D) -> String {
        "https://maps.google.com/?q=\(coord.latitude),\(coord.longitude)"
    }

    private func updateAuthState() {
        switch manager.authorizationStatus {
        case .notDetermined:       authorization = .undetermined
        case .restricted:          authorization = .restricted
        case .denied:              authorization = .denied
        case .authorizedWhenInUse: authorization = .whenInUse
        case .authorizedAlways:    authorization = .always
        @unknown default:          authorization = .undetermined
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updateAuthState()
            // Resume any fetchOnce() that was waiting for the prompt.
            if self.authorization != .undetermined {
                self.finishAuthorizationWait()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                      didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let loc = locations.last {
                // Ignore cached readings older than this request.
                if let started = self.locationRequestStartedAt,
                   loc.timestamp < started.addingTimeInterval(-1) { return }
                self.lastKnownCoordinate = loc.coordinate
                self.finishLocationRequest(with: loc)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                      didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.finishLocationRequest(with: nil)
        }
    }
}
