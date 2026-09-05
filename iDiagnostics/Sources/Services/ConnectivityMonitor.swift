import Combine
import CoreBluetooth
import CoreLocation
import Foundation
import Network

final class ConnectivityMonitor: NSObject, ObservableObject {
    @Published private(set) var isOnline = false
    @Published private(set) var interfaceTitle = "جارٍ التحقق…"
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false
    @Published private(set) var bluetoothTitle = "لم يبدأ الفحص"
    @Published private(set) var locationAuthorizationTitle = "لم يُطلب"
    @Published private(set) var locationAccuracy: CLLocationAccuracy?
    @Published private(set) var locationTimestamp: Date?
    @Published private(set) var isRequestingLocation = false
    @Published private(set) var errorMessage: String?

    private let pathQueue = DispatchQueue(label: "com.bellinghamfolks.idiagnostics.network")
    private var pathMonitor: NWPathMonitor?
    private var centralManager: CBCentralManager?
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.interfaceTitle = Self.interfaceTitle(for: path)
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
            }
        }
        pathMonitor = monitor
        monitor.start(queue: pathQueue)

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        refreshLocationAuthorization()
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        locationManager.stopUpdatingLocation()
        isRequestingLocation = false
        started = false
    }

    func requestOneLocation() {
        errorMessage = nil
        locationAccuracy = nil
        locationTimestamp = nil
        isRequestingLocation = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            isRequestingLocation = false
            refreshLocationAuthorization()
            errorMessage = "إذن الموقع غير متاح. يمكنك تغييره من إعدادات النظام."
        @unknown default:
            isRequestingLocation = false
            errorMessage = "تعذر تحديد حالة إذن الموقع."
        }
    }

    var metrics: [DiagnosticMetric] {
        var values: [DiagnosticMetric] = [
            .init(label: "الاتصال بالإنترنت", value: isOnline ? "متاح" : "غير متاح الآن"),
            .init(label: "مسار الاتصال", value: interfaceTitle),
            .init(label: "اتصال قد يستهلك بيانات", value: isExpensive ? "نعم" : "لا"),
            .init(label: "نمط بيانات منخفض", value: isConstrained ? "نعم" : "لا"),
            .init(label: "البلوتوث", value: bluetoothTitle),
            .init(label: "إذن الموقع", value: locationAuthorizationTitle)
        ]
        if let locationAccuracy {
            values.append(.init(label: "دقة قراءة GPS", value: "±\(Int(locationAccuracy.rounded())) متر"))
        }
        return values
    }

    private func refreshLocationAuthorization() {
        locationAuthorizationTitle = Self.authorizationTitle(locationManager.authorizationStatus)
    }

    private static func interfaceTitle(for path: NWPath) -> String {
        guard path.status == .satisfied else { return "لا يوجد مسار متاح" }
        if path.usesInterfaceType(.wifi) { return "Wi‑Fi" }
        if path.usesInterfaceType(.cellular) { return "شبكة خلوية" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        if path.usesInterfaceType(.loopback) { return "محلي" }
        return "نوع آخر"
    }

    private static func authorizationTitle(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "لم يُطلب"
        case .restricted: return "مقيّد"
        case .denied: return "مرفوض"
        case .authorizedAlways: return "مسموح دائمًا"
        case .authorizedWhenInUse: return "مسموح أثناء الاستخدام"
        @unknown default: return "غير معروف"
        }
    }
}

extension ConnectivityMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown: bluetoothTitle = "جارٍ التحقق…"
        case .resetting: bluetoothTitle = "جارٍ إعادة الضبط"
        case .unsupported: bluetoothTitle = "غير مدعوم"
        case .unauthorized: bluetoothTitle = "الإذن غير متاح"
        case .poweredOff: bluetoothTitle = "متوقف"
        case .poweredOn: bluetoothTitle = "يعمل"
        @unknown default: bluetoothTitle = "غير معروف"
        }
    }
}

extension ConnectivityMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationAuthorization()
        if isRequestingLocation,
           (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse) {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isRequestingLocation = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationAccuracy = max(0, location.horizontalAccuracy)
        locationTimestamp = location.timestamp
        isRequestingLocation = false
        AccessibilityAnnouncer.post("نجحت قراءة نظام تحديد الموقع")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            return
        }
        isRequestingLocation = false
        errorMessage = "تعذرت قراءة الموقع: \(error.localizedDescription)"
    }
}
