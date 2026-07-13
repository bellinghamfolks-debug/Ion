import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: RouterViewModel
    @EnvironmentObject private var settings: RouterSettings

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                if let s = model.status {
                    signalSection(s)
                    detailsSection(s)
                }
                if let msg = model.lastMessage {
                    Section { Text(msg).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("حالة الإشارة")
            .toolbar {
                Button {
                    Task { await model.refresh() }
                } label: { Image(systemName: "arrow.clockwise") }
                .disabled(!model.isConnected)
            }
            .refreshable { await model.refresh() }
        }
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText)
                Spacer()
                if model.connection == .connecting || model.busy { ProgressView() }
            }
            if !model.isConnected {
                Button("اتصال بالراوتر") { Task { await model.connect() } }
                    .disabled(settings.password.isEmpty)
                if settings.password.isEmpty {
                    Text("أدخل كلمة مرور الراوتر في الإعدادات أولًا.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: { Text("الاتصال (\(settings.host))") }
    }

    private func signalSection(_ s: RouterStatus) -> some View {
        Section("الإشارة الحالية") {
            HStack {
                Label(s.networkType ?? "—", systemImage: "network")
                Spacer()
                signalBars(s.signalBars)
            }
            metric("النطاق النشط (4G)", s.lteBand)
            metric("النطاق النشط (5G)", s.nr5gBand)
            metric("RSRP (4G)", s.lteRSRP.map { "\($0) dBm" })
            metric("SINR (4G)", s.lteSINR)
            metric("RSRP (5G)", s.nr5gRSRP.map { "\($0) dBm" })
            metric("SINR (5G)", s.nr5gSINR)
        }
    }

    private func detailsSection(_ s: RouterStatus) -> some View {
        Section("تفاصيل") {
            metric("المشغّل", s.networkProvider)
            metric("RSSI", s.rssi)
            metric("RSRQ (4G)", s.lteRSRQ)
            metric("تجميع الحوامل", s.lteCA)
            metric("Cell ID", s.cellID)
            metric("PCI", s.pci)
        }
    }

    @ViewBuilder private func metric(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).environment(\.layoutDirection, .leftToRight)
            }
            .font(.subheadline)
        }
    }

    private func signalBars(_ bars: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 6, height: CGFloat(6 + i * 4))
            }
        }
        .accessibilityLabel("قوة الإشارة \(bars) من 4")
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch model.connection {
        case .connected: return "متصل"
        case .connecting: return "جارٍ الاتصال…"
        case .failed(let m): return "فشل: \(m)"
        case .disconnected: return "غير متصل"
        }
    }
}
