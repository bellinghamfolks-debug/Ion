import SwiftUI

struct AudioPacksView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        AudioPacksContent(
            service: container.audioPackService,
            hasServer: container.settings.serverURL != nil
        )
    }
}

private struct AudioPacksContent: View {
    @ObservedObject var service: AudioPackService
    let hasServer: Bool

    var body: some View {
        List {
            Section {
                Text("يستخدم التطبيق صوت iOS المحلي دائمًا بوصفه بديلًا يعمل دون إنترنت. ويمكن لخادم EnglishNova توفير ملفات بشرية أو استوديوهات نطق تُحفظ داخل التطبيق.")
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
                            Button("حذف الملفات المحلية", role: .destructive) { Task { await service.delete(pack) } }
                        }
                    }
                }
            }

            Section("الحزم المتصلة") {
                Button("تحديث قائمة الحزم من الخادم") {
                    Task { await service.refreshIndex() }
                }
                .disabled(!hasServer || service.isRefreshing)
                if service.isRefreshing { ProgressView("جاري جلب فهرس الصوت") }
                if !hasServer {
                    Text("عيّن عنوان الخادم في الإعدادات لإظهار حزم الصوت المتاحة عبر الإنترنت.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("حزم الصوت دون إنترنت")
        .task { await service.loadLocalState() }
        .alert("تعذر تحديث الحزم", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("حسنًا") { service.errorMessage = nil }
        } message: { Text(service.errorMessage ?? "") }
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
