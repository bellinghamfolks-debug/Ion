import SwiftUI
import UniformTypeIdentifiers
import PDFKit

@main
struct PDFToWordAccessibilityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Models
enum GoogleModel: String, CaseIterable {
    // Gemini 3 family (2026). 3.6 Flash = strongest/most accurate; 3.5 Flash-Lite
    // = fastest and cheapest, and is optimized for document parsing (ideal here).
    case pro = "gemini-3.6-flash"
    case flash = "gemini-3.5-flash-lite"

    var displayName: String {
        switch self {
        case .pro: return "جيميني 3.6 (أعلى دقة)"
        case .flash: return "جيميني 3.5 لايت (أسرع وأوفر)"
        }
    }
}

// MARK: - View Model
@MainActor
class AppViewModel: ObservableObject {
    @AppStorage("apiKey") var apiKey: String = ""
    @Published var selectedModel: GoogleModel = .pro
    @Published var selectedPDFURL: URL?
    @Published var convertedFileURL: URL?
    @Published var isConverting: Bool = false
    @Published var statusMessage: String = "جاهز للبدء. الرجاء إدخال مفتاح API واختيار ملف PDF."

    func convertPDF() async {
        guard !apiKey.isEmpty else {
            announce(message: "خطأ: يرجى إدخال مفتاح API أولاً.")
            return
        }
        guard let pdfURL = selectedPDFURL else {
            announce(message: "خطأ: يرجى اختيار ملف PDF.")
            return
        }

        isConverting = true
        announce(message: "جاري تحويل الملف، يرجى الانتظار.")

        do {
            let pdfData = try Data(contentsOf: pdfURL)
            let base64String = pdfData.base64EncodedString()

            let extractedText = try await callGoogleAPI(base64PDF: base64String)
            if let wordURL = try createWordDocument(from: extractedText) {
                self.convertedFileURL = wordURL
                announce(message: "تم التحويل بنجاح. يمكنك الآن مشاركة أو حفظ ملف الوورد.")
            }
        } catch {
            announce(message: "حدث خطأ أثناء التحويل: \(error.localizedDescription)")
        }

        isConverting = false
    }

    private func callGoogleAPI(base64PDF: String) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel.rawValue):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let parameters: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "قم باستخراج جميع النصوص من هذا الملف وتنسيقها بشكل ممتاز وصحيح لغوياً لتكون جاهزة للحفظ كملف وورد."],
                        [
                            "inline_data": [
                                "mime_type": "application/pdf",
                                "data": base64PDF
                            ]
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(GoogleAPIResponse.self, from: data)
        return json.candidates?.first?.content.parts.first?.text ?? "لم يتم العثور على نص."
    }

    private func createWordDocument(from text: String) throws -> URL? {
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 16)
        ])

        let rtfData = try attributedString.data(from: NSRange(location: 0, length: attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])

        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "ConvertedDocument_\(UUID().uuidString.prefix(5)).rtf"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        try rtfData.write(to: fileURL)
        return fileURL
    }

    func announce(message: String) {
        self.statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - API Response Models
struct GoogleAPIResponse: Codable {
    let candidates: [Candidate]?
}
struct Candidate: Codable {
    let content: Content
}
struct Content: Codable {
    let parts: [Part]
}
struct Part: Codable {
    let text: String?
}

// MARK: - UI Views
struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingFilePicker = false
    @State private var showingShareSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {

                    // حقل إدخال مفتاح API
                    VStack(alignment: .leading, spacing: 10) {
                        Text("مفتاح API الخاص بجوجل")
                            .font(.headline)
                            .accessibilityHidden(true)

                        SecureField("أدخل مفتاح API هنا", text: $viewModel.apiKey)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .accessibilityLabel("حقل إدخال مفتاح API الخاص بجوجل")
                            .accessibilityHint("أدخل المفتاح للتمكن من الاتصال بخوادم الذكاء الاصطناعي")
                    }

                    // اختيار النموذج
                    VStack(alignment: .leading, spacing: 10) {
                        Text("اختر نموذج الذكاء الاصطناعي")
                            .font(.headline)
                            .accessibilityHidden(true)

                        Picker("نموذج الذكاء الاصطناعي", selection: $viewModel.selectedModel) {
                            ForEach(GoogleModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .accessibilityLabel("اختيار نموذج الذكاء الاصطناعي")
                        .accessibilityValue(viewModel.selectedModel.displayName)
                        .accessibilityHint("اسحب لأعلى أو لأسفل لاختيار النموذج المناسب للتحويل")
                    }

                    Divider()

                    // حالة التطبيق والتوجيهات الصوتية
                    Text(viewModel.statusMessage)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(viewModel.isConverting ? .blue : .primary)
                        .padding()
                        .accessibilityLabel("حالة التطبيق: \(viewModel.statusMessage)")

                    // أزرار التحكم
                    VStack(spacing: 20) {
                        Button(action: {
                            showingFilePicker = true
                        }) {
                            HStack {
                                Image(systemName: "doc.text.viewfinder")
                                Text(viewModel.selectedPDFURL == nil ? "اختيار ملف PDF" : "تم اختيار الملف. اضغط لتغييره")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .font(.title2)
                            .cornerRadius(15)
                        }
                        .accessibilityLabel(viewModel.selectedPDFURL == nil ? "زر اختيار ملف PDF" : "زر تغيير ملف PDF المختار")
                        .accessibilityHint("يفتح تطبيق الملفات لاختيار المستند المراد تحويله")

                        if viewModel.selectedPDFURL != nil {
                            Button(action: {
                                Task {
                                    await viewModel.convertPDF()
                                }
                            }) {
                                HStack {
                                    if viewModel.isConverting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text("جاري التحويل...")
                                    } else {
                                        Image(systemName: "arrow.right.doc.on.clipboard")
                                        Text("بدء تحويل الملف إلى وورد")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.isConverting ? Color.gray : Color.green)
                                .foregroundColor(.white)
                                .font(.title2)
                                .cornerRadius(15)
                            }
                            .disabled(viewModel.isConverting)
                            .accessibilityLabel(viewModel.isConverting ? "جاري التحويل الآن، يرجى الانتظار" : "زر بدء تحويل الملف إلى وورد")
                        }

                        if viewModel.convertedFileURL != nil {
                            Button(action: {
                                showingShareSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("مشاركة وحفظ ملف الوورد")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .font(.title2)
                                .cornerRadius(15)
                            }
                            .accessibilityLabel("زر مشاركة وحفظ ملف الوورد الناتج")
                            .accessibilityHint("يفتح قائمة المشاركة لإرسال الملف أو حفظه في الجهاز")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("محول المستندات للمكفوفين")
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(selectedURL: $viewModel.selectedPDFURL)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = viewModel.convertedFileURL {
                    ShareSheetView(activityItems: [url])
                }
            }
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.selectedURL = url
            UIAccessibility.post(notification: .announcement, argument: "تم اختيار الملف بنجاح، يمكنك الآن الضغط على زر بدء التحويل.")
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            UIAccessibility.post(notification: .announcement, argument: "تم إلغاء اختيار الملف.")
        }
    }
}

// MARK: - Share Sheet
struct ShareSheetView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
