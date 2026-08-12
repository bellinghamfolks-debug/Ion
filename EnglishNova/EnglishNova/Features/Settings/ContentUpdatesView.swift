import SwiftUI

@MainActor
final class ContentUpdatesViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case available(version: Int, notes: String)
        case installing
        case installed(version: Int)
        case failed(String)
    }

    @Published var status: Status = .idle
    private var manifest: RemoteContentManifest?

    func check(service: ContentUpdateService) async {
        status = .checking
        do {
            let value = try await service.check()
            manifest = value
            status = .available(version: value.version, notes: value.notesAr)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func install(service: ContentUpdateService, repository: CourseRepositoryProtocol) async {
        guard let manifest else { return }
        status = .installing
        do {
            _ = try await service.install(manifest)
            _ = try await repository.refresh()
            status = .installed(version: manifest.version)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

struct ContentUpdatesView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ContentUpdatesViewModel()

    var body: some View {
        List {
            Section(L("حالة المحتوى")) {
                switch model.status {
                case .idle:
                    Text(L("يمكنك التحقق من وجود نسخة أحدث من محتوى المنهج."))
                case .checking:
                    ProgressView(L("جارٍ التحقق من التحديثات"))
                case let .available(version, notes):
                    LabeledContent(L("الإصدار المتاح"), value: "\(version)")
                    if !notes.isEmpty { Text(L(notes)) }
                    Button(L("تنزيل التحديث")) {
                        Task {
                            await model.install(
                                service: container.contentUpdateService,
                                repository: container.courseRepository
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case .installing:
                    ProgressView(L("جارٍ تثبيت المحتوى"))
                case let .installed(version):
                    Label(Lf("تم تثبيت الإصدار %@", "\(version)"), systemImage: "checkmark.seal.fill")
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                }
            }

            Section(L("التحقق من الملف")) {
                Text(L("قبل استخدام أي تحديث، يتحقق التطبيق من الاتصال الآمن وبصمة الملف ثم يحاول قراءة المنهج كاملًا."))
                    .font(.subheadline)
                Text(L("إذا لم يثبت التحديث بنجاح، يبقى المنهج المدمج مع التطبيق متاحًا."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(L("التحقق من وجود تحديث")) {
                Task { await model.check(service: container.contentUpdateService) }
            }
            .disabled(container.settings.serverURL == nil)
        }
        .navigationTitle(L("تحديث المنهج"))
    }
}
