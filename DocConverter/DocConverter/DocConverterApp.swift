import SwiftUI
import UniformTypeIdentifiers

@main
struct PDFToWordAccessibilityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Server config

enum Server {
    /// The shared EnglishNova/Ion backend that runs the conversion in the
    /// background (no per-user API key needed).
    static let baseURL = URL(string: "https://ion-production-da28.up.railway.app")!

    /// A stable per-device id so each device sees only its own jobs.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "device.id") { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "device.id")
        return new
    }
}

// MARK: - Models

enum JobStatus: String, Codable {
    case processing, done, partial, failed

    var titleAr: String {
        switch self {
        case .processing: return "قيد المعالجة"
        case .done: return "اكتمل"
        case .partial: return "اكتمل جزئيًا (توجد صفحات فشلت)"
        case .failed: return "فشل"
        }
    }
}

struct JobDetail: Codable {
    let jobId: String
    let filename: String
    let status: JobStatus
    let totalPages: Int
    let donePages: Int
    let failedPages: Int
    let resultText: String?
    let error: String?
}

struct JobSummary: Codable, Identifiable {
    let jobId: String
    let filename: String
    let status: JobStatus
    let totalPages: Int
    let donePages: Int
    var id: String { jobId }
}

// MARK: - API client

struct ConvertAPI {
    private var session: URLSession { .shared }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: Server.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue(Server.deviceID, forHTTPHeaderField: "X-Device-Id")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    func createJob(pdf: Data, filename: String, model: String, mode: String,
                   options: [String: Any]) async throws -> String {
        var r = request("convert/jobs", method: "POST")
        let body: [String: Any] = [
            "filename": filename,
            "model": model,
            "mode": mode,
            "options": options,
            "pdfBase64": pdf.base64EncodedString(),
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: r)
        try Self.check(resp, data)
        struct Created: Decodable { let jobId: String }
        return try JSONDecoder().decode(Created.self, from: data).jobId
    }

    func status(_ jobId: String) async throws -> JobDetail {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)"))
        try Self.check(resp, data)
        return try JSONDecoder().decode(JobDetail.self, from: data)
    }

    func list() async throws -> [JobSummary] {
        let (data, resp) = try await session.data(for: request("convert/jobs"))
        try Self.check(resp, data)
        struct Wrap: Decodable { let jobs: [JobSummary] }
        return try JSONDecoder().decode(Wrap.self, from: data).jobs
    }

    func resume(_ jobId: String) async throws {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)/resume", method: "POST"))
        try Self.check(resp, data)
    }

    func delete(_ jobId: String) async throws {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)", method: "DELETE"))
        try Self.check(resp, data)
    }

    /// Downloads the assembled result in the chosen format (docx/rtf/txt) to a temp URL.
    func downloadResult(_ jobId: String, filename: String, format: OutputFormat) async throws -> URL {
        let (data, resp) = try await session.data(for: request("convert/jobs/\(jobId)/result.\(format.rawValue)"))
        try Self.check(resp, data)
        let base = (filename as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base.isEmpty ? "document" : base).\(format.rawValue)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw NSError(domain: "Convert", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "خطأ من الخادم (\(http.statusCode)) \(msg)"])
        }
    }
}

// MARK: - AI model choice

enum GoogleModel: String, CaseIterable, Identifiable {
    case flashLite = "gemini-3.5-flash-lite"
    case flash = "gemini-3.6-flash"
    case pro = "gemini-3.1-pro-preview"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .flashLite: return "جيميني 3.5 لايت (أسرع وأوفر)"
        case .flash: return "جيميني 3.6 (أعلى دقة)"
        case .pro: return "جيميني 3.1 برو (الأقوى)"
        }
    }
}

enum ConversionMode: String, CaseIterable, Identifiable {
    case accessible, layout
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .accessible: return "وصولي (نص نظيف)"
        case .layout: return "محافظ على التنسيق"
        }
    }
    var hintAr: String {
        switch self {
        case .accessible: return "نص خطّي مرتّب — الأفضل لقارئ الشاشة."
        case .layout: return "يعيد بناء تخطيط الملف الأصلي (خطوط، جداول، صور، مواضع)."
        }
    }
}

enum MathMode: String, CaseIterable, Identifiable {
    case off, words, latex
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .off: return "بدون"
        case .words: return "كلمات مقروءة"
        case .latex: return "LaTeX"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case docx, rtf, txt
    var id: String { rawValue }
    var titleAr: String {
        switch self {
        case .docx: return "وورد (DOCX)"
        case .rtf: return "RTF"
        case .txt: return "نص عادي"
        }
    }
}

struct ConversionOptions {
    var faithful = true
    var describeImages = true
    var math: MathMode = .off
    var detectHeadings = true
    var preserveTables = true
    var pageNumbers = true

    var dictionary: [String: Any] {
        [
            "faithful": faithful,
            "describeImages": describeImages,
            "math": math == .off ? "" : math.rawValue,
            "detectHeadings": detectHeadings,
            "preserveTables": preserveTables,
            "pageNumbers": pageNumbers,
        ]
    }
}

// MARK: - View Model

@MainActor
final class AppViewModel: ObservableObject {
    @AppStorage("model") private var modelRaw: String = GoogleModel.flashLite.rawValue
    @Published var selectedModel: GoogleModel = .flashLite

    @Published var mode: ConversionMode = .accessible
    @Published var options = ConversionOptions()
    @Published var outputFormat: OutputFormat = .docx

    @Published var selectedPDFURL: URL?
    @Published var current: JobDetail?
    @Published var resultURL: URL?
    @Published var history: [JobSummary] = []
    @Published var isUploading = false
    @Published var statusMessage = "جاهز للبدء. اختر ملف PDF لتحويله على الخادم."

    private let api = ConvertAPI()
    private var pollTask: Task<Void, Never>?

    init() { selectedModel = GoogleModel(rawValue: modelRaw) ?? .flashLite }

    func setModel(_ m: GoogleModel) { selectedModel = m; modelRaw = m.rawValue }

    func announce(_ message: String) {
        statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func startConversion() async {
        guard let pdfURL = selectedPDFURL else { announce("اختر ملف PDF أولًا."); return }
        isUploading = true
        announce("جارٍ رفع الملف إلى الخادم…")
        do {
            let needsStop = pdfURL.startAccessingSecurityScopedResource()
            defer { if needsStop { pdfURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: pdfURL)
            let jobId = try await api.createJob(pdf: data, filename: pdfURL.lastPathComponent,
                                                model: selectedModel.rawValue,
                                                mode: mode.rawValue,
                                                options: options.dictionary)
            resultURL = nil
            announce("بدأ التحويل على الخادم. يمكنك إغلاق التطبيق؛ ستجد الملف في السجل.")
            startPolling(jobId)
        } catch {
            announce("تعذّر بدء التحويل: \(error.localizedDescription)")
        }
        isUploading = false
    }

    func startPolling(_ jobId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let detail = try await api.status(jobId)
                    current = detail
                    switch detail.status {
                    case .processing:
                        statusMessage = "قيد المعالجة: \(detail.donePages) من \(detail.totalPages) صفحة."
                    case .done:
                        announce("اكتمل التحويل. جارٍ تجهيز ملف الوورد.")
                        await fetchResult(detail)
                        await refreshHistory()
                        return
                    case .partial:
                        announce("اكتمل جزئيًا: نجحت \(detail.donePages) وفشلت \(detail.failedPages) صفحة. يمكنك إعادة المحاولة.")
                        await fetchResult(detail)
                        await refreshHistory()
                        return
                    case .failed:
                        announce("فشل التحويل: \(detail.error ?? "خطأ غير معروف")")
                        return
                    }
                } catch {
                    // transient network error — keep polling
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func fetchResult(_ detail: JobDetail) async {
        do { resultURL = try await api.downloadResult(detail.jobId, filename: detail.filename, format: outputFormat) }
        catch { announce("تعذّر تنزيل الملف الناتج: \(error.localizedDescription)") }
    }

    func openJob(_ summary: JobSummary) async {
        do {
            let detail = try await api.status(summary.jobId)
            current = detail
            if detail.status == .done || detail.status == .partial { await fetchResult(detail) }
            if detail.status == .processing { startPolling(detail.jobId) }
        } catch { announce("تعذّر فتح المهمة: \(error.localizedDescription)") }
    }

    func resumeCurrent() async {
        guard let jobId = current?.jobId else { return }
        do {
            try await api.resume(jobId)
            announce("جارٍ إعادة محاولة الصفحات الفاشلة…")
            startPolling(jobId)
        } catch { announce("تعذّرت إعادة المحاولة: \(error.localizedDescription)") }
    }

    func refreshHistory() async {
        do { history = try await api.list() } catch { }
    }

    func delete(_ summary: JobSummary) async {
        try? await api.delete(summary.jobId)
        await refreshHistory()
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var showingFilePicker = false
    @State private var showingShareSheet = false
    @State private var showingHistory = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 26) {
                    Picker("نموذج الذكاء الاصطناعي", selection: Binding(
                        get: { vm.selectedModel }, set: { vm.setModel($0) })) {
                        ForEach(GoogleModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("اختيار نموذج الذكاء الاصطناعي")
                    .accessibilityValue(vm.selectedModel.displayName)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("نمط التحويل").font(.headline)
                        Picker("نمط التحويل", selection: $vm.mode) {
                            ForEach(ConversionMode.allCases) { Text($0.titleAr).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityValue(vm.mode.titleAr)
                        Text(vm.mode.hintAr).font(.caption).foregroundColor(.secondary)
                    }

                    if vm.mode == .accessible { optionsSection }

                    Text(vm.statusMessage)
                        .font(.title3).fontWeight(.bold).multilineTextAlignment(.center)
                        .padding()
                        .accessibilityLabel("حالة التطبيق: \(vm.statusMessage)")

                    if let job = vm.current, job.status == .processing {
                        ProgressView(value: Double(job.donePages), total: Double(max(job.totalPages, 1)))
                            .accessibilityLabel("التقدم: \(job.donePages) من \(job.totalPages) صفحة")
                    }

                    controls
                }
                .padding()
            }
            .navigationTitle("محول المستندات للمكفوفين")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await vm.refreshHistory() }
                        showingHistory = true
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("سجل التحويلات السابقة")
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(selectedURL: $vm.selectedPDFURL)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = vm.resultURL { ShareSheetView(activityItems: [url]) }
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView(vm: vm, openShare: { showingShareSheet = true })
            }
            .task { await vm.refreshHistory() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder private var optionsSection: some View {
        DisclosureGroup("خيارات التحويل (اختيارية)") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("دقّة حرفية (بلا تعديل من الذكاء)", isOn: $vm.options.faithful)
                    Text("يستخرج النص الأصلي من الملف كما هو دون أن يغيّر الذكاء الأسماء أو الأرقام. يُنصَح بإبقائه مُفعّلًا للمستندات الرسمية.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Toggle("اكتشاف العناوين وتنسيقها", isOn: $vm.options.detectHeadings)
                Toggle("إدراج وصف مفصّل للصور المُضمَّنة", isOn: $vm.options.describeImages)
                Toggle("تحويل الجداول إلى جداول حقيقية", isOn: $vm.options.preserveTables)
                Toggle("ترقيم الصفحات", isOn: $vm.options.pageNumbers)

                VStack(alignment: .leading, spacing: 6) {
                    Text("صياغة المعادلات الرياضية").font(.subheadline)
                    Picker("صياغة المعادلات", selection: $vm.options.math) {
                        ForEach(MathMode.allCases) { Text($0.titleAr).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityValue(vm.options.math.titleAr)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("صيغة الملف الناتج").font(.subheadline)
                    Picker("صيغة الملف", selection: $vm.outputFormat) {
                        ForEach(OutputFormat.allCases) { Text($0.titleAr).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityValue(vm.outputFormat.titleAr)
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 18) {
            bigButton(vm.selectedPDFURL == nil ? "اختيار ملف PDF" : "تغيير الملف (\(vm.selectedPDFURL!.lastPathComponent))",
                      icon: "doc.text.viewfinder", color: .blue) { showingFilePicker = true }

            if vm.selectedPDFURL != nil {
                bigButton(vm.isUploading ? "جارٍ الرفع…" : "بدء التحويل على الخادم",
                          icon: "arrow.up.doc", color: vm.isUploading ? .gray : .green,
                          loading: vm.isUploading) {
                    Task { await vm.startConversion() }
                }
                .disabled(vm.isUploading)
            }

            if vm.current?.status == .partial {
                bigButton("إعادة محاولة الصفحات الفاشلة", icon: "arrow.clockwise", color: .orange) {
                    Task { await vm.resumeCurrent() }
                }
            }

            if vm.resultURL != nil {
                bigButton("مشاركة وحفظ ملف الوورد", icon: "square.and.arrow.up", color: .orange) {
                    showingShareSheet = true
                }
            }
        }
    }

    private func bigButton(_ title: String, icon: String, color: Color,
                           loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if loading { ProgressView().tint(.white) } else { Image(systemName: icon) }
                Text(title)
            }
            .frame(maxWidth: .infinity).padding()
            .background(color).foregroundColor(.white).font(.title2).cornerRadius(15)
        }
        .accessibilityLabel(title)
    }
}

// MARK: - History View

struct HistoryView: View {
    @ObservedObject var vm: AppViewModel
    var openShare: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if vm.history.isEmpty {
                    Text("لا توجد تحويلات سابقة بعد.").foregroundColor(.secondary)
                }
                ForEach(vm.history) { job in
                    Button {
                        Task {
                            await vm.openJob(job)
                            dismiss()
                            if vm.resultURL != nil { openShare() }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.filename).font(.headline).lineLimit(1)
                            Text("\(job.status.titleAr) — \(job.donePages)/\(job.totalPages) صفحة")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(job.filename)، \(job.status.titleAr)، \(job.donePages) من \(job.totalPages) صفحة")
                    }
                    .swipeActions {
                        Button("حذف", role: .destructive) { Task { await vm.delete(job) } }
                    }
                }
            }
            .navigationTitle("سجل التحويلات")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() } }
            }
            .refreshable { await vm.refreshHistory() }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.selectedURL = url
            UIAccessibility.post(notification: .announcement, argument: "تم اختيار الملف. اضغط بدء التحويل.")
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            UIAccessibility.post(notification: .announcement, argument: "تم إلغاء اختيار الملف.")
        }
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
