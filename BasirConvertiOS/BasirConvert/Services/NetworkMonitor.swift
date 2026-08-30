import Foundation
import Network
import Combine

struct NetworkSnapshot: Equatable, Sendable {
    let isConnected: Bool
    let usesWiFi: Bool
    let isExpensive: Bool
    let isConstrained: Bool

    static let unknown = NetworkSnapshot(
        isConnected: true,
        usesWiFi: false,
        isExpensive: false,
        isConstrained: false
    )
}

enum NetworkPolicy {
    static func validate(
        snapshot: NetworkSnapshot,
        wifiOnly: Bool,
        allowLowData: Bool
    ) throws {
        guard snapshot.isConnected else { throw BasirError.networkUnavailable }
        if wifiOnly, !snapshot.usesWiFi { throw BasirError.wifiRequired }
        if snapshot.isConstrained, !allowLowData { throw BasirError.constrainedNetwork }
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var snapshot: NetworkSnapshot = .unknown
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.basir.network-monitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let value = NetworkSnapshot(
                isConnected: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor in self?.snapshot = value }
        }
        monitor.start(queue: queue)
    }

    func validate(settings: SettingsStore) throws {
        try NetworkPolicy.validate(snapshot: snapshot,
                                   wifiOnly: settings.wifiOnly,
                                   allowLowData: settings.allowLowData)
    }
}

