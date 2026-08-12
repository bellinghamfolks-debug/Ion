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
                Text(L("يستطيع التطبيق استخدام أصوات iOS الموجودة على الجهاز. وقد تتوفر حزم صوت إضافية لبعض المستويات."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(service.packs) { pack in
                Section("\(pack.level.rawValue) • \(pack.titleAr)") {
                    LabeledContent(L("الصوت"), value: pack.voiceName)
                    LabeledContent(L("الإصدار"), value: "\(pack.version)")
                    if pack.approximateBytes > 0 {
                        LabeledContent(
                            L("الحجم"),
                            value: ByteCountFormatter.string(fromByteCount: pack.approximateBytes, countStyle: .file)
                        )
                    }

                    let state = service.states[pack.id] ?? .notDownloaded
                    Label(state.accessibilityDescription, systemImage: icon(for: state))
                        .accessibilityElement(children: .combine)

                    switch state {
                    case .notDownloaded, .failed:
                        Button(L("تنزيل")) { Task { await service.download(pack) } }
                            .disabled(pack.clips.isEmpty)
                    case .downloading:
                        Label(L("جارٍ التنزيل"), systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    case .ready:
                        if pack.clips.isEmpty {
                            Text(L("هذا الصوت متوفر من النظام ولا يحتاج إلى تنزيل إضافي."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(L("حذف الملفات المحمّلة"), role: .destructive) {
                                packToDelete = pack
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("الأصوات المحمّلة"))
        .task { await service.loadLocalState() }
        .alert(L("تعذر تحميل قائمة الأصوات"), isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button(L("حسنًا")) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
        .confirmationDialog(
            L("حذف الملفات المحمّلة؟"),
            isPresented: Binding(
                get: { packToDelete != nil },
                set: { if !$0 { packToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: packToDelete
        ) { pack in
            Button(L("حذف"), role: .destructive) {
                Task {
                    await service.delete(pack)
                    ToastCenter.shared.show(L("تم حذف الملفات"), style: .info)
                }
                packToDelete = nil
            }
            Button(L("إلغاء"), role: .cancel) { packToDelete = nil }
        } message: { pack in
            Text(Lf("ستُحذف ملفات %@ من هذا الجهاز، ويمكن تنزيلها مرة أخرى لاحقًا.", pack.titleAr))
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
