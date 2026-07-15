import Foundation
import Combine
import SwiftUI
import Network
import CoreTelephony
import CoreBluetooth
import CoreLocation

/// The active network interface, as reported by `NWPathMonitor`.
enum ConnectionInterfaceKind {
    case wifi, cellular, wiredEthernet, other, none

    var titleAr: String {
        switch self {
        case .wifi:          return "واي فاي"
        case .cellular:      return "خلوي"
        case .wiredEthernet: return "إيثرنت سلكي"
        case .other:         return "اتصال آخر"
        case .none:          return "غير متصل"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi:          return "wifi"
        case .cellular:      return "antenna.radiowaves.left.and.right"
        case .wiredEthernet: return "cable.connector"
        case .other:         return "network"
        case .none:          return "wifi.slash"
        }
    }
}

/// Bluetooth radio power/authorization, mapped from `CBManagerState`.
enum BluetoothPower {
    case poweredOn, poweredOff, unauthorized, unsupported, unknown

    var titleAr: String {
        switch self {
        case .poweredOn:    return "قيد التشغيل"
        case .poweredOff:   return "متوقّف"
        case .unauthorized: return "غير مُصرَّح"
        case .unsupported:  return "غير مدعوم"
        case .unknown:      return "قيد التحقق…"
        }
    }

    var color: Color {
        switch self {
        case .poweredOn:                        return .green
        case .poweredOff, .unknown:             return .secondary
        case .unauthorized, .unsupported:       return .orange
        }
    }

    var isReady: Bool { self == .poweredOn }
}

/// Location (GPS) authorization state, mapped from `CLAuthorizationStatus`.
enum LocationAuth {
    case authorizedAlways, authorizedWhenInUse, denied, restricted, notDetermined

    var titleAr: String {
        switch self {
        case .authorizedAlways:   return "مسموح دائمًا"
        case .authorizedWhenInUse: return "مسموح أثناء الاستخدام"
        case .denied:             return "مرفوض"
        case .restricted:         return "مقيّد"
        case .notDetermined:      return "لم يُطلب بعد"
        }
    }

    var color: Color {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse: return .green
        case .denied, .restricted:                    return .red
        case .notDetermined:                          return .secondary
        }
    }

    var isAuthorized: Bool {
        self == .authorizedAlways || self == .authorizedWhenInUse
    }
}

/// Publishes live connectivity status across Wi-Fi/cellular, carrier & radio,
/// Bluetooth power and GPS authorization using only public iOS APIs.
@MainActor
final class ConnectivityService: NSObject, ObservableObject {

    // MARK: Network
    @Published private(set) var isConnected = false
    @Published private(set) var interface: ConnectionInterfaceKind = .none

    // MARK: Cellular
    /// May be empty / "--" on eSIM-only devices or iOS 16+, handled gracefully.
    @Published private(set) var carrierName: String = ""
    @Published private(set) var radioTechnologyAr: String = ""

    // MARK: Bluetooth & Location
    @Published private(set) var bluetooth: BluetoothPower = .unknown
    @Published private(set) var location: LocationAuth = .notDetermined

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.idiagnostics.connectivity.path")
    private let telephonyInfo = CTTelephonyNetworkInfo()
    private var centralManager: CBCentralManager?
    private let locationManager = CLLocationManager()
    private var didStart = false

    /// Begin monitoring. Instantiating the Bluetooth central prompts the system
    /// Bluetooth permission — that is expected on first launch.
    func start() {
        guard !didStart else { return }
        didStart = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let kind = Self.interfaceKind(for: path)
            Task { @MainActor [weak self] in
                self?.applyPath(connected: connected, kind: kind)
            }
        }
        pathMonitor.start(queue: pathQueue)

        refreshCellular()

        // Passing the main queue keeps delegate callbacks on the main thread.
        centralManager = CBCentralManager(delegate: self, queue: .main)

        locationManager.delegate = self
        location = Self.locationAuth(for: locationManager.authorizationStatus)
    }

    /// Prompt for "while using the app" location permission.
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func stop() {
        pathMonitor.cancel()
    }

    // MARK: - Network mapping

    private func applyPath(connected: Bool, kind: ConnectionInterfaceKind) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isConnected = connected
            interface = connected ? kind : .none
        }
        if kind == .cellular { refreshCellular() }
    }

    private static func interfaceKind(for path: NWPath) -> ConnectionInterfaceKind {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .other
    }

    // MARK: - Cellular

    private func refreshCellular() {
        // carrierName is deprecated and returns "--" on iOS 16+; treat any
        // placeholder or empty value as "unavailable" rather than showing junk.
        var resolvedCarrier = ""
        if let carriers = telephonyInfo.serviceSubscriberCellularProviders {
            for carrier in carriers.values {
                if let name = carrier.carrierName,
                   !name.isEmpty, name != "--", name != "Carrier" {
                    resolvedCarrier = name
                    break
                }
            }
        }
        carrierName = resolvedCarrier

        var resolvedRadio = ""
        if let techs = telephonyInfo.serviceCurrentRadioAccessTechnology,
           let raw = techs.values.first(where: { !$0.isEmpty }) {
            resolvedRadio = Self.radioTechnologyArabic(raw)
        }
        radioTechnologyAr = resolvedRadio
    }

    static func radioTechnologyArabic(_ raw: String) -> String {
        switch raw {
        case CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "2G"
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyLTE:
            return "LTE (4G)"
        default:
            if #available(iOS 14.1, *) {
                if raw == CTRadioAccessTechnologyNRNSA || raw == CTRadioAccessTechnologyNR {
                    return "5G"
                }
            }
            return raw
        }
    }

    // MARK: - Bluetooth / Location mapping

    static func bluetoothPower(for state: CBManagerState) -> BluetoothPower {
        switch state {
        case .poweredOn:     return .poweredOn
        case .poweredOff:    return .poweredOff
        case .unauthorized:  return .unauthorized
        case .unsupported:   return .unsupported
        case .resetting, .unknown: return .unknown
        @unknown default:    return .unknown
        }
    }

    static func locationAuth(for status: CLAuthorizationStatus) -> LocationAuth {
        switch status {
        case .authorizedAlways:    return .authorizedAlways
        case .authorizedWhenInUse: return .authorizedWhenInUse
        case .denied:              return .denied
        case .restricted:          return .restricted
        case .notDetermined:       return .notDetermined
        @unknown default:          return .notDetermined
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ConnectivityService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let mapped = Self.bluetoothPower(for: central.state)
        Task { @MainActor [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.bluetooth = mapped
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ConnectivityService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.location = Self.locationAuth(for: status)
            }
        }
    }
}
