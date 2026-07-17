import SwiftUI

struct AudioPacksView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        AudioPacksContent(service: container.audioPackService)
    }
}

private struct AudioPacksContent: View {
    @ObservedObject var service: AudioPackService
    @State private var packToDelete: AudioPackDescriptor?

    var body: some View {
        List {
            Section {
                Text("يستخدم التطبيق صوت iOS المحلي دائمًا لنطق الكلمات والجمل، ويعمل دون إنترنت.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            ForEach(service.packs) { pack in
                Section("\(pack.level.rawValue) • \(pack.titleAr)") {
                    LabeledContent("الصوت", value: pack.voiceName)
                    LabeledContent("الإصدار", value: "\(pack.version)")
                    if pack.approximateBytes > 0 {
                        LabeledContent("الحجم التقريبي", value: ByteCountFormatter.string(fromByteCount: pack.approximateBytes, countStyle: .file))
                    }
                    let state = service.states[pack.id] ?? .notDownloaded
                    Label(state.accessibilityDescription, systemImage: icon(for: state))
                        .accessibilityElement(children: .combine)

                    switch state {
                    case .notDownloaded, .failed:
                        Button("تنزيل الحزمة") { Task { await service.download(pack) } }
                            .disabled(pack.clips.isEmpty)
                    case .downloading:
                        Button("جاري التنزيل") { }
                            .disabled(true)
                    case .ready:
                        if pack.clips.isEmpty {
                            Text("هذا الصوت يوفره النظام، لذلك لا يحتاج إلى ملف تنزيل داخل التطبيق.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("حذف الملفات المحلية", role: .destructive) { packToDelete = pack }
                        }
                    }
                }
            }
        }
        .navigationTitle("حزم الصوت")
        .task { await service.loadLocalState() }
        .alert("تعذر تحميل الحزم", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("حسنًا") { service.errorMessage = nil }
        } message: { Text(service.errorMessage ?? "") }
        .confirmationDialog(
            "حذف الملفات المحلية؟",
            isPresented: Binding(get: { packToDelete != nil },
                                 set: { if !$0 { packToDelete = nil } }),
            titleVisibility: .visible,
            presenting: packToDelete
        ) { pack in
            Button("حذف", role: .destructive) {
                Task {
                    await service.delete(pack)
                    ToastCenter.shared.show("تم حذف ملفات الحزمة", style: .info)
                }
                packToDelete = nil
            }
            Button("إلغاء", role: .cancel) { packToDelete = nil }
        } message: { pack in
            Text("ستُحذف ملفات \(pack.titleAr) من جهازك، ويمكنك تنزيلها مجددًا لاحقًا.")
        }
    }

    private func icon(for state: AudioPackState) -> String {
        switch state {
        case .notDownloaded: return "icloud.and.arrow.down"
        case .downloading: return "arrow.down.circle"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
