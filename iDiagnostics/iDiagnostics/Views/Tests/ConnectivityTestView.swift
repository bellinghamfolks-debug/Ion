import SwiftUI

/// Live view of Wi-Fi, cellular (carrier + radio), Bluetooth and GPS status.
/// Records a `.pass` when the device is online, otherwise a `.warning`.
struct ConnectivityTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var service = ConnectivityService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                networkCard
                bluetoothLocationCard
                permissionCard
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.connectivity.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            service.start()
            record()
        }
        .onChange(of: signature) { _ in record() }
    }

    // MARK: - Cards

    private var networkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("الشبكة", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Divider()

                StatusRow(
                    icon: ConnectionInterfaceKind.wifi.systemImage,
                    title: "واي فاي",
                    detail: wifiConnected ? "متصل" : "غير متصل",
                    color: wifiConnected ? .green : .secondary
                )

                StatusRow(
                    icon: ConnectionInterfaceKind.cellular.systemImage,
                    title: "خلوي",
                    detail: cellularDetail,
                    color: cellularColor,
                    footnote: cellularFootnote
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var bluetoothLocationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("الأجهزة والموقع", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Divider()

                StatusRow(
                    icon: "bolt.horizontal.circle",
                    title: "بلوتوث",
                    detail: service.bluetooth.titleAr,
                    color: service.bluetooth.color
                )

                StatusRow(
                    icon: "location.fill",
                    title: "GPS / الموقع",
                    detail: service.location.titleAr,
                    color: service.location.color
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var permissionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("لتحديد حالة الموقع بدقّة، امنح إذن الوصول إلى الموقع أثناء استخدام التطبيق.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "طلب إذن الموقع", systemImage: "location") {
                    service.requestLocationPermission()
                }
                .disabled(service.location.isAuthorized)
                .accessibilityLabel("طلب إذن الوصول إلى الموقع أثناء استخدام التطبيق")
                .accessibilityHint(service.location.isAuthorized ? "الإذن ممنوح بالفعل" : "يفتح نافذة إذن النظام")
            }
        }
    }

    // MARK: - Derived state

    private var wifiConnected: Bool {
        service.isConnected && service.interface == .wifi
    }

    private var cellularActive: Bool {
        service.isConnected && service.interface == .cellular
    }

    private var cellularDetail: String {
        if cellularActive { return "متصل" }
        if !service.carrierName.isEmpty || !service.radioTechnologyAr.isEmpty { return "متاح" }
        return "غير متصل"
    }

    private var cellularColor: Color {
        cellularActive ? .green : .secondary
    }

    private var cellularFootnote: String? {
        var parts: [String] = []
        parts.append("المشغّل: " + (service.carrierName.isEmpty ? "غير متاح" : service.carrierName))
        if !service.radioTechnologyAr.isEmpty {
            parts.append("الشبكة: " + service.radioTechnologyAr)
        }
        return parts.joined(separator: " · ")
    }

    /// A compact, Equatable signature of all live state so `.onChange` can
    /// re-record the result whenever anything meaningful changes.
    private var signature: String {
        [
            service.isConnected ? "1" : "0",
            service.interface.titleAr,
            service.carrierName,
            service.radioTechnologyAr,
            service.bluetooth.titleAr,
            service.location.titleAr,
        ].joined(separator: "|")
    }

    // MARK: - Recording

    private func record() {
        let outcome: TestOutcome = service.isConnected ? .pass : .warning
        let summary = service.isConnected
            ? "الجهاز متصل عبر \(service.interface.titleAr)"
            : "لا يوجد اتصال شبكي حالياً"

        let metrics: [TestResult.Metric] = [
            .init(label: "الحالة", value: service.isConnected ? "متصل" : "غير متصل"),
            .init(label: "الواجهة", value: service.interface.titleAr),
            .init(label: "المشغّل", value: service.carrierName.isEmpty ? "غير متاح" : service.carrierName),
            .init(label: "تقنية الشبكة", value: service.radioTechnologyAr.isEmpty ? "غير متاح" : service.radioTechnologyAr),
            .init(label: "بلوتوث", value: service.bluetooth.titleAr),
            .init(label: "الموقع", value: service.location.titleAr),
        ]

        store.record(
            TestResult(
                category: .connectivity,
                outcome: outcome,
                summaryAr: summary,
                metrics: metrics
            )
        )
    }
}

/// A live connectivity row: icon, label, colored status and optional footnote.
private struct StatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)، \(detail)\(footnote.map { "، \($0)" } ?? "")")
    }
}
