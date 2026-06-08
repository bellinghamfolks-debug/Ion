// DescribeImageView.swift
// Reusable image task screen for: detailed description, alt text,
// screenshot reading, currency/receipt reading. The four modes share
// the same picker + Gemini round-trip; only the prompt differs.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum DescribeImageMode {
    case detailed, altText, screenshot, currencyOrReceipt
    case medical, legal, table

    var title: String {
        switch self {
        case .detailed:           return L10n.t("وصف الصورة", "Image description")
        case .altText:            return L10n.t("إنشاء وصف بديل", "Create alt text")
        case .screenshot:         return L10n.t("قراءة لقطة شاشة", "Read a screenshot")
        case .currencyOrReceipt:  return L10n.t("قارئ العملات والفواتير",
                                                 "Currency and receipt reader")
        case .medical:            return L10n.t("قراءة مستند طبي", "Read a medical document")
        case .legal:              return L10n.t("قراءة مستند قانوني", "Read a legal document")
        case .table:              return L10n.t("تحويل جدول إلى نص", "Turn a table into text")
        }
    }

    var task: TaskKind {
        switch self {
        case .detailed:           return .describeImage
        case .altText:            return .altText
        case .screenshot:         return .screenshot
        case .currencyOrReceipt:  return .currencyOrReceipt
        case .medical:            return .medicalText
        case .legal:              return .legalText
        case .table:              return .tableRead
        }
    }

    var instruction: String {
        switch self {
        case .detailed:
            return "Provide a detailed description suitable for a blind user. Start with a one-sentence summary, then objects, layout, visible text, and any practical notes."
        case .altText:
            return "Write precise alt text for a blind user: objects, spatial relationships, colors, visible text, practical relevance."
        case .screenshot:
            return "Explain the screenshot for a screen-reader user: page, buttons, messages, errors, and the next useful step."
        case .currencyOrReceipt:
            return "You are Basir, an assistant for blind and low-vision users. The image contains either banknotes/coins OR a paid receipt/invoice. BANKNOTES/COINS: state the currency and denomination in the FIRST sentence. RECEIPTS/INVOICES: state the grand total and the currency in the FIRST sentence. Keep the answer under 80 words, plain prose, no markdown."
        case .medical:
            // Mirrors Android's medical-text prompt: READING ONLY, no diagnosis.
            return "You are Basir, an assistant for blind and low-vision users. The image contains medical text (a prescription, drug leaflet, lab result, or doctor's note). FIRST: read the document type and the most important fact in one sentence (drug name + dose, or test name + value). THEN: list the other readable fields plainly: patient name if visible, date, dosage instructions, frequency, warnings, allergies, expiry. Render numbers and units exactly as printed. DO NOT diagnose, do NOT recommend treatment, do NOT suggest stopping or starting medication. End with: \"راجِع طبيبك أو الصيدلي قبل أي قرار.\" / \"Consult your doctor or pharmacist before any decision.\" No markdown."
        case .legal:
            // Mirrors Android's legal-text prompt: SUMMARIZING ONLY.
            return "You are Basir, an assistant for blind and low-vision users. The image contains a legal document (contract, lease, agreement, terms, court paper, or official form). FIRST: state the document type and the parties in one sentence. THEN: bullet the key clauses in plain language: obligations, dates, monetary amounts, penalties, termination conditions, signatures. Quote any critical number or date verbatim. DO NOT give legal advice, do NOT predict outcomes, do NOT recommend signing or refusing. End with: \"راجِع محاميًا قبل التوقيع.\" / \"Consult a lawyer before signing.\" No markdown."
        case .table:
            return "You are Basir, an assistant for blind and low-vision users. The image contains a TABLE (timetable, results sheet, schedule, line-item invoice, lecture grid). Read the column headers first as a header line. Then read each row as: \"Row 1: <header1> <cell1>, <header2> <cell2>, ...\". Preserve numbers, times, and units exactly. If the table is a lecture / class schedule, treat the LEFT column as the time / period label and announce it FIRST per row. Keep the response under 200 words; if the table is longer, end with \"…and \" + how many more rows are visible. No markdown."
        }
    }
}

struct DescribeImageView: View {
    let mode: DescribeImageMode
    @State private var pickerItem: PhotosPickerItem?
    @State private var resultText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showDocPicker = false
    /// Last analyzed image (compressed), kept so "Ask about the result"
    /// can re-examine it for follow-up questions.
    @State private var lastImageData: Data?

    /// Reading modes where attaching a document (not just an image) makes
    /// sense — matches Android's medical/legal/table document support.
    /// Currency reading stays image-only by design.
    private var allowsDocument: Bool {
        mode == .medical || mode == .legal || mode == .table
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Capture a NEW photo with the camera — what blind users
                // most often want. Hidden on devices/simulators without a
                // camera.
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text(L10n.t("التقاط صورة", "Take a photo"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(L10n.t("اختيار صورة", "Choose a photo"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(CameraPicker.isAvailable
                                ? Color(.secondarySystemBackground) : Color.accentColor)
                    .foregroundStyle(CameraPicker.isAvailable ? Color.primary : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if allowsDocument {
                    Button {
                        showDocPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(L10n.t("اختيار مستند",
                                        "Choose document"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                if isLoading {
                    HStack {
                        ProgressView()
                        Text(L10n.t("أحلّل المحتوى...",
                                     "Analyzing content..."))
                    }
                }

                if !resultText.isEmpty {
                    Divider().padding(.vertical, 8)
                    Text(L10n.t("النتيجة", "Result"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(resultText)
                        .textSelection(.enabled)
                        .accessibilityLabel(resultText)
                    CopyButton(text: resultText)
                    AskAboutResultLink(text: resultText, imageData: lastImageData)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
        }
        .navigationTitle(mode.title)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await runDescribe(item: item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { Task { await analyze(rawData: data) } }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker(types: DocumentText.importTypes) { url in
                guard let url else { return }
                Task {
                    isLoading = true
                    let text = await DocumentText.extractTextAsync(from: url)
                    isLoading = false
                    if let text, !text.isEmpty {
                        await analyzeText(text)
                    } else {
                        errorMessage = L10n.t("لم أتمكن من استخراج نص قابل للقراءة من هذا الملف.",
                                              "I couldn't extract readable text from this file.")
                    }
                }
            }
        }
    }

    /// Run the mode's reading prompt over extracted document text instead
    /// of an image (medical / legal / table modes).
    private func analyzeText(_ text: String) async {
        isLoading = true
        errorMessage = nil
        resultText = ""
        lastImageData = nil   // document path: no image to re-examine
        ProcessingFeedback.start()
        defer { isLoading = false }
        do {
            let response = try await AiProviderFactory.current().ask(
                task: mode.task,
                input: String(text.prefix(12000)),
                instruction: mode.instruction
                    + " The content is provided below as text (not an image).",
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            resultText = response
            ProcessingFeedback.done()
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }

    private func runDescribe(item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw GeminiError.decode("could not read image")
            }
            await analyze(rawData: data)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }

    private func analyze(rawData data: Data) async {
        isLoading = true
        errorMessage = nil
        resultText = ""
        ProcessingFeedback.start()
        defer { isLoading = false }
        do {
            // Same 1600-px JPEG-85 compression used by MathExtractView.
            let compressed = UIImage(data: data).flatMap { img -> Data? in
                let maxLongEdge: CGFloat = 1600
                let longEdge = max(img.size.width, img.size.height)
                guard longEdge > 0 else { return nil }
                let scale = min(1.0, maxLongEdge / longEdge)
                let newSize = CGSize(width: img.size.width * scale,
                                     height: img.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                return renderer.image { _ in
                    img.draw(in: CGRect(origin: .zero, size: newSize))
                }.jpegData(compressionQuality: 0.85)
            } ?? data
            lastImageData = compressed

            let response = try await AiProviderFactory.current().ask(
                task: mode.task,
                input: "",
                instruction: mode.instruction,
                language: BasirSettings.shared.language,
                imageData: compressed,
                mimeType: "image/jpeg"
            )
            resultText = response
            ProcessingFeedback.done()
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
