import Foundation
import UIKit
import Combine

/// Collects and publishes device/system information using only public iOS APIs.
/// Values iOS does not expose (battery maximum capacity, charge-cycle count) are
/// reported honestly as unavailable rather than fabricated.
@MainActor
final class SystemInfoService: ObservableObject {

    // MARK: Device
    @Published private(set) var modelIdentifier: String = ""
    @Published private(set) var marketingName: String = ""
    @Published private(set) var systemName: String = ""
    @Published private(set) var systemVersion: String = ""

    // MARK: Storage
    @Published private(set) var storageTotal: String = "—"
    @Published private(set) var storageUsed: String = "—"
    @Published private(set) var storageFree: String = "—"

    // MARK: Memory & CPU
    @Published private(set) var physicalMemory: String = "—"
    @Published private(set) var processorCountTotal: Int = 0
    @Published private(set) var processorCountActive: Int = 0
    @Published private(set) var thermalStateAr: String = "—"
    @Published private(set) var uptime: String = "—"

    // MARK: Battery
    @Published private(set) var batteryLevel: String = "—"
    @Published private(set) var batteryStateAr: String = "—"
    /// iOS exposes no public API for battery maximum capacity or cycle count.
    let batteryHealthAr = "لا يتيحها iOS"

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter
    }()

    /// Gather all information into the published properties. Safe to call on
    /// `.onAppear`; runs synchronously on the main actor.
    func refresh() {
        collectDevice()
        collectStorage()
        collectMemoryAndCPU()
        collectBattery()
    }

    // MARK: - Collection

    private func collectDevice() {
        modelIdentifier = DeviceIdentity.modelIdentifier
        marketingName = DeviceIdentity.marketingName
        systemName = UIDevice.current.systemName
        systemVersion = UIDevice.current.systemVersion
    }

    private func collectStorage() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(
            forKeys: [.volumeTotalCapacityKey,
                      .volumeAvailableCapacityForImportantUsageKey]
        ) else {
            storageTotal = "غير متاح"
            storageUsed = "غير متاح"
            storageFree = "غير متاح"
            return
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let used = max(0, total - available)

        storageTotal = byteFormatter.string(fromByteCount: total)
        storageUsed = byteFormatter.string(fromByteCount: used)
        storageFree = byteFormatter.string(fromByteCount: available)
    }

    private func collectMemoryAndCPU() {
        let info = ProcessInfo.processInfo
        physicalMemory = byteFormatter.string(fromByteCount: Int64(info.physicalMemory))
        processorCountTotal = info.processorCount
        processorCountActive = info.activeProcessorCount
        thermalStateAr = Self.thermalStateArabic(info.thermalState)
        uptime = Self.formattedUptime(info.systemUptime)
    }

    private func collectBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let device = UIDevice.current

        let level = device.batteryLevel
        if level < 0 {
            // -1 means the level is unknown (e.g. Simulator).
            batteryLevel = "غير متاح"
        } else {
            batteryLevel = "\(Int((level * 100).rounded()))٪"
        }

        batteryStateAr = Self.batteryStateArabic(device.batteryState)
    }

    // MARK: - Mapping helpers

    static func thermalStateArabic(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "عادية"
        case .fair:     return "مقبولة"
        case .serious:  return "مرتفعة"
        case .critical: return "حرجة"
        @unknown default: return "غير معروفة"
        }
    }

    static func batteryStateArabic(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging:  return "قيد الشحن"
        case .full:      return "مكتمل"
        case .unplugged: return "يعمل بالبطارية"
        case .unknown:   return "غير معروفة"
        @unknown default: return "غير معروفة"
        }
    }

    static func formattedUptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 3
        formatter.calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "ar")
            return calendar
        }()
        return formatter.string(from: seconds) ?? "—"
    }
}
