import SwiftUI

/// Presents collected device/system information, grouped into cards, and records
/// a `.pass` result once the information has been gathered. Battery health items
/// iOS does not expose are shown honestly as unavailable.
struct SystemInfoView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var service = SystemInfoService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                deviceCard
                storageCard
                memoryCard
                batteryCard
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.system.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: gather)
    }

    // MARK: - Cards

    private var deviceCard: some View {
        InfoSection(title: "الجهاز", systemImage: "iphone") {
            InfoRow(label: "الموديل", value: service.marketingName)
            InfoRow(label: "معرّف الموديل", value: service.modelIdentifier)
            InfoRow(label: "النظام", value: service.systemName)
            InfoRow(label: "الإصدار", value: service.systemVersion)
        }
    }

    private var storageCard: some View {
        InfoSection(title: "التخزين", systemImage: "internaldrive") {
            InfoRow(label: "السعة الكلية", value: service.storageTotal)
            InfoRow(label: "المستخدَم", value: service.storageUsed)
            InfoRow(label: "المتاح", value: service.storageFree)
        }
    }

    private var memoryCard: some View {
        InfoSection(title: "الذاكرة والمعالج", systemImage: "memorychip") {
            InfoRow(label: "الذاكرة العشوائية", value: service.physicalMemory)
            InfoRow(label: "أنوية المعالج", value: "\(service.processorCountTotal)")
            InfoRow(label: "الأنوية النشطة", value: "\(service.processorCountActive)")
            InfoRow(label: "حالة الحرارة", value: service.thermalStateAr)
            InfoRow(label: "مدة التشغيل", value: service.uptime)
        }
    }

    private var batteryCard: some View {
        InfoSection(title: "البطارية", systemImage: "battery.100") {
            InfoRow(label: "مستوى الشحن", value: service.batteryLevel)
            InfoRow(label: "حالة الشحن", value: service.batteryStateAr)
            InfoRow(label: "صحة البطارية", value: service.batteryHealthAr, isUnavailable: true)
            InfoRow(label: "دورات الشحن", value: service.batteryHealthAr, isUnavailable: true)
        }
    }

    // MARK: - Actions

    private func gather() {
        service.refresh()
        store.record(
            TestResult(
                category: .system,
                outcome: .pass,
                summaryAr: "تم جمع معلومات النظام",
                metrics: [
                    .init(label: "الموديل", value: service.marketingName),
                    .init(label: "معرّف الموديل", value: service.modelIdentifier),
                    .init(label: "النظام", value: "\(service.systemName) \(service.systemVersion)"),
                    .init(label: "السعة الكلية", value: service.storageTotal),
                    .init(label: "المستخدَم", value: service.storageUsed),
                    .init(label: "المتاح", value: service.storageFree),
                    .init(label: "الذاكرة العشوائية", value: service.physicalMemory),
                    .init(label: "أنوية المعالج", value: "\(service.processorCountTotal)"),
                    .init(label: "الأنوية النشطة", value: "\(service.processorCountActive)"),
                    .init(label: "حالة الحرارة", value: service.thermalStateAr),
                    .init(label: "مدة التشغيل", value: service.uptime),
                    .init(label: "مستوى الشحن", value: service.batteryLevel),
                    .init(label: "حالة الشحن", value: service.batteryStateAr),
                    .init(label: "صحة البطارية", value: service.batteryHealthAr),
                    .init(label: "دورات الشحن", value: service.batteryHealthAr),
                ]
            )
        )
    }
}

/// A titled `Card` grouping a set of information rows.
private struct InfoSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.tint)
                Divider()
                content
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A single label/value row that reads naturally to VoiceOver as one element.
private struct InfoRow: View {
    let label: String
    let value: String
    var isUnavailable: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(isUnavailable ? Color.secondary : Color.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
