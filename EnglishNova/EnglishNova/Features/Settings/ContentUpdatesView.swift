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
            Section(L("الحالة")) {
                switch model.status {
                case .idle:
                    Text(L("اضغط فحص التحديثات للبحث عن منهج أحدث من الخادم الذي حددته."))
                case .checking:
                    ProgressView(L("جاري فحص التحديثات"))
                case let .available(version, notes):
                    LabeledContent(L("الإصدار المتاح"), value: "\(version)")
                    Text(notes)
                    Button(L("تنزيل وتثبيت المحتوى")) {
                        Task { await model.install(service: container.contentUpdateService, repository: container.courseRepository) }
                    }
                    .buttonStyle(.borderedProminent)
                case .installing:
                    ProgressView(L("جاري التحقق والتثبيت"))
                case let .installed(version):
                    Label(Lf("تم تثبيت الإصدار %@", "\(version)"), systemImage: "checkmark.seal.fill")
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                }
            }
            Section(L("الأمان")) {
                Text(L("لا تُثبت الحزمة إلا عبر HTTPS، وبعد مطابقة بصمة SHA-256 وفك ترميز المنهج كاملًا بنجاح."))
                Text(L("يُحفظ المحتوى المحدّث في مساحة التطبيق، ويمكن الرجوع إلى المحتوى المدمج بحذف بيانات التطبيق."))
            }
            Button(L("فحص التحديثات")) {
                Task { await model.check(service: container.contentUpdateService) }
            }
            .disabled(container.settings.serverURL == nil)
        }
        .navigationTitle(L("تحديثات المنهج"))
    }
}
