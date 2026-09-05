import Foundation
import UIKit

struct SystemSnapshotService {
    struct Snapshot {
        let metrics: [DiagnosticMetric]
        let outcome: TestOutcome
        let summary: String
    }

    private let formatter: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.countStyle = .file
        value.allowedUnits = [.useGB, .useMB]
        return value
    }()

    func collect() -> Snapshot {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let process = ProcessInfo.processInfo
        let storage = storageValues()
        let batteryLevel = UIDevice.current.batteryLevel
        let thermal = thermalTitle(process.thermalState)

        var metrics: [DiagnosticMetric] = [
            .init(label: "الجهاز", value: DeviceIdentity.marketingName),
            .init(label: "معرّف العتاد", value: DeviceIdentity.modelIdentifier),
            .init(label: "النظام", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            .init(label: "الذاكرة الفعلية", value: formatter.string(fromByteCount: Int64(process.physicalMemory))),
            .init(label: "أنوية المعالجة النشطة", value: "\(process.activeProcessorCount) من \(process.processorCount)"),
            .init(label: "الحالة الحرارية", value: thermal),
            .init(label: "شحن البطارية الحالي", value: batteryLevel >= 0 ? "\(Int((batteryLevel * 100).rounded()))٪" : "غير متاح"),
            .init(label: "حالة الشحن", value: batteryStateTitle(UIDevice.current.batteryState)),
            .init(label: "نمط الطاقة المنخفضة", value: process.isLowPowerModeEnabled ? "مفعّل" : "غير مفعّل"),
            .init(label: "صحة البطارية ودوراتها", value: "لا تتيحها واجهات iOS العامة")
        ]

        if let storage {
            metrics.insert(contentsOf: [
                .init(label: "سعة التخزين", value: formatter.string(fromByteCount: storage.total)),
                .init(label: "المتاح للتطبيقات", value: formatter.string(fromByteCount: storage.available)),
                .init(label: "نسبة المساحة المتاحة", value: "\(Int((storage.freeFraction * 100).rounded()))٪")
            ], at: 3)
        } else {
            metrics.insert(.init(label: "التخزين", value: "تعذر قراءته"), at: 3)
        }

        let storageIsLow = storage.map { $0.freeFraction < 0.05 } ?? false
        let thermalIsHigh = process.thermalState == .serious || process.thermalState == .critical
        let outcome: TestOutcome = storageIsLow || thermalIsHigh ? .warning : .pass
        let summary = outcome == .pass
            ? "استُخرجت معلومات النظام بنجاح، ولم تظهر حالة حرارية مرتفعة أو مساحة شديدة الانخفاض."
            : "نجح جمع المعلومات، لكن الحرارة الحالية أو المساحة المتاحة تحتاج الانتباه."

        return Snapshot(metrics: metrics, outcome: outcome, summary: summary)
    }

    private func storageValues() -> (total: Int64, available: Int64, freeFraction: Double)? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let totalValue = values.volumeTotalCapacity,
        totalValue > 0 else { return nil }

        let total = Int64(totalValue)
        let available = max(0, values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (total, available, min(1, Double(available) / Double(total)))
    }

    private func thermalTitle(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "طبيعية"
        case .fair: return "مرتفعة قليلًا"
        case .serious: return "مرتفعة"
        case .critical: return "حرجة"
        @unknown default: return "غير معروفة"
        }
    }

    private func batteryStateTitle(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "قيد الشحن"
        case .full: return "مكتمل"
        case .unplugged: return "يعمل بالبطارية"
        case .unknown: return "غير معروفة"
        @unknown default: return "غير معروفة"
        }
    }
}
