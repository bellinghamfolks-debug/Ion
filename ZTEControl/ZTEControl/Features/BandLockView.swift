import SwiftUI

struct BandLockView: View {
    @EnvironmentObject private var model: RouterViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("وضع الشبكة", selection: $model.mode) {
                        ForEach(NetworkMode.allCases) { Text($0.titleAr).tag($0) }
                    }
                    Button("تطبيق وضع الشبكة") { Task { await model.applyMode() } }
                        .disabled(!model.isConnected || model.busy)
                } header: {
                    Text("وضع الشبكة")
                } footer: {
                    Text("في المناطق البعيدة غالبًا يكون «4G فقط» أثبت من 5G. جرّب وراقب الإشارة.")
                }

                bandSection(title: "نطاقات 4G (LTE)",
                            bands: RadioBand.lte,
                            selection: $model.selectedLTE)
                bandSection(title: "نطاقات 5G (NR)",
                            bands: RadioBand.nr5g,
                            selection: $model.selectedNR5G)

                Section {
                    Button("تثبيت النطاقات المحددة") { Task { await model.applyBandLock() } }
                        .disabled(!model.isConnected || model.busy ||
                                  (model.selectedLTE.isEmpty && model.selectedNR5G.isEmpty))
                    Button("إلغاء التثبيت (تلقائي)", role: .destructive) {
                        Task { await model.clearLock() }
                    }
                    .disabled(!model.isConnected || model.busy)
                } footer: {
                    Text("النطاقات المنخفضة (مثل 8 و20 و28) تصل لمسافات أبعد وتخترق الجدران أفضل — جرّبها أولًا في الديرة.")
                }

                if let msg = model.lastMessage {
                    Section { Text(msg).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("التحكم في النطاقات")
            .overlay {
                if model.busy { ProgressView().scaleEffect(1.3) }
            }
        }
    }

    private func bandSection(title: String, bands: [Int], selection: Binding<Set<Int>>) -> some View {
        Section(title) {
            ForEach(bands, id: \.self) { band in
                Button {
                    if selection.wrappedValue.contains(band) { selection.wrappedValue.remove(band) }
                    else { selection.wrappedValue.insert(band) }
                } label: {
                    HStack {
                        Text("Band \(band)").environment(\.layoutDirection, .leftToRight)
                        if RadioBand.longRangeHint.contains(band) {
                            Text("مدى بعيد").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                        Image(systemName: selection.wrappedValue.contains(band)
                              ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.wrappedValue.contains(band) ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
