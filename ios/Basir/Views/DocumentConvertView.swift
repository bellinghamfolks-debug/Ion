// DocumentConvertView.swift
// Resilient PDF / DOCX / PPTX / TXT processing for iOS. PDF and image
// pages are isolated so one malformed model response cannot erase a group
// of pages. The loop exposes progress, cancellation, diagnostics, retries,
// and a structured DOCX export.
//
// v3.3 — per-batch retry
// ──────────────────────
// Long-document runs sometimes lose one or two batches to a
// transient Gemini hiccup (timeout, rate-limit, content-filter
// false positive). v3.3 keeps the rest of the run: a failing
// batch is recorded, the loop continues, and the user gets a
// "Retry failed batches" button at the end — same pattern as
// Android's ConversionState.retainedSnapshot retry path. This
// closes the last big iOS↔Android gap for document conversion.

import SwiftUI
import UniformTypeIdentifiers

/// One Gemini call's worth of pages. The Identifiable id keeps
/// SwiftUI's @State diffing stable across success → failure → retry
/// transitions.
struct ConvertBatch: Identifiable {
    let id: Int
    let range: ClosedRange<Int>
    let input: String
    enum Status {
        case pending
        case success(output: String)
        case failed(error: String)
    }
    var status: Status
    var output: String? {
        if case let .success(o) = status { return o }
        return nil
    }
    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

struct DocumentConvertView: View {
    @EnvironmentObject var settings: BasirSettings
    private let initialURL: URL?
    @State private var hasAppliedInitialURL = false
    @State private var pickedURL: URL?
    @State private var pageCount: Int = 0
    @State private var resultText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPicker = false
    /// File URL of the latest generated DOCX, or nil if none was
    /// produced for the current result. Reset on every new conversion.
    @State private var lastDocxURL: URL?
    /// Per-batch progress for the chunked conversion loop.
    @State private var progress: (done: Int, total: Int) = (0, 0)
    /// True while we're OCR-scanning a scanned PDF (vs. the later
    /// language-processing pass), so the progress bar can say which
    /// phase the user is in.
    @State private var isScanning = false
    /// Structured conversion result (Android-parity). Holds the ordered
    /// blocks — including REAL tables — used to build a proper DOCX.
    @State private var convertedResult: StructuredDocConverter.Result?
    /// Transient phase note (e.g. "uploading…") shown while there is no
    /// numeric progress yet, so the bar sitting at 0 isn't mistaken for a
    /// stall during the initial upload.
    @State private var statusNote: String = ""
    /// Cooperative cancel flag — checked at every batch boundary.
    @State private var cancelRequested: Bool = false
    /// The actual asynchronous operation, retained so Stop cancels the
    /// in-flight network request instead of waiting only for a page boundary.
    @State private var conversionTask: Task<Void, Never>?
    /// File import and DOCX export run away from the main actor so a large
    /// local file cannot freeze VoiceOver or the rest of the interface.
    @State private var filePreparationTask: Task<Void, Never>?
    @State private var isPreparingFile = false
    @State private var isBuildingDocx = false
    /// Plain-language quality/completeness report for the latest run.
    @State private var conversionReport: String?
    /// Per-batch state for the current run. Populated when run()
    /// builds the batches; mutated as each one finishes. Used by
    /// the retry button to identify which batches still need a
    /// rerun.
    @State private var batches: [ConvertBatch] = []
    /// v3.3 — optional math-extraction mode. When ON, the prompt
    /// asks Gemini to also render every equation in the document
    /// using the spoken-math + LaTeX format the math card uses.
    /// Mirrors the toggle on Android's convert screen.
    @AppStorage("convert_math_mode") private var mathMode: Bool = false
    /// When ON, Basir renders each page with vision so Gemini can also
    /// describe any photos / figures / charts inside the document (the
    /// iOS counterpart to Android's "full" convert mode). OFF by default
    /// because text-only extraction is much cheaper.
    @AppStorage("convert_describe_images") private var describeImages: Bool = false

    /// Document types iOS now extracts on-device. DOCX and PPTX go
    /// through DocxReader / PptxReader (the iOS equivalents of
    /// Android's DocxExtractor / PptxExtractor); PDF goes through
    /// PdfReader; CSV / TXT are read as plain text.
    private static let maximumImportedDocumentBytes: Int64 = 512 * 1_024 * 1_024

    private static let allowedTypes: [UTType] = {
        // Be generous so files aren't greyed out in the Files picker
        // (including from cloud providers that report broad UTIs). We
        // validate/extract by extension after picking, so an unsupported
        // pick just yields a clear error instead of being unselectable.
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText,
                               .text, .rtf, .content,
                               .image, .jpeg, .png, .heic]
        // DOCX / PPTX are declared by their MIME types so we work
        // even on iOS releases that haven't promoted them to a
        // first-class UTType identifier.
        if let docx = UTType(mimeType:
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document") {
            types.append(docx)
        }
        if let pptx = UTType(mimeType:
                "application/vnd.openxmlformats-officedocument.presentationml.presentation") {
            types.append(pptx)
        }
        return types
    }()

    /// Empty means organize the extracted text without translation.
    /// A selected language requests translation while preserving structure.
    @State private var translateTo: String = ""

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "اختر مستندًا، ثم حدد مستوى الدقة والخيارات التي تحتاجها. يعالج بصير الصفحات واحدة تلو الأخرى ويحفظ ما اكتمل حتى عند تعذر صفحة بعينها.",
                    "Choose a document, then select the accuracy level and only the options you need. Basir processes pages one at a time and preserves completed work even when one page cannot be read."
                )
            )

            pickerCard

            if isPreparingFile {
                BasirStatusBanner(
                    text: L10n.t("جارٍ تجهيز الملف داخل مساحة التطبيق…",
                                 "Preparing the file inside the app…"),
                    tone: .info,
                    title: L10n.t("تجهيز المستند", "Preparing document")
                )
            }

            if pickedURL != nil {
                BasirSectionHeader(
                    title: L10n.t("إعدادات المعالجة", "Processing settings"),
                    subtitle: L10n.t(
                        "تؤثر هذه الخيارات في مدة التحويل والتكلفة ودقة النتيجة.",
                        "These options affect processing time, cost, and result quality."
                    )
                )

                VStack(alignment: .leading, spacing: 18) {
                    modelPicker
                    Divider()
                    translationPicker
                    Divider()
                    describeImagesToggle
                    Divider()
                    mathToggle
                }
                .basirCardSurface()

                runButton
            }

            if isLoading {
                conversionProgressCard
            }

            if let conversionReport, !conversionReport.isEmpty {
                BasirStatusBanner(
                    text: conversionReport,
                    tone: batches.contains(where: { $0.isFailed }) ? .warning : .success,
                    title: L10n.t("تقرير اكتمال التحويل", "Conversion completeness report")
                )
                .accessibilityLabel(L10n.t(
                    "تقرير اكتمال التحويل: \(conversionReport)",
                    "Conversion completeness report: \(conversionReport)"
                ))
            }

            if !resultText.isEmpty {
                BasirResultCard(
                    title: L10n.t("النص المستخرج", "Extracted text"),
                    text: resultText
                ) {
                    HStack(spacing: 4) {
                        ShareLink(item: resultText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.t("مشاركة النص", "Share text"))
                        CopyButton(text: resultText)
                    }
                    .buttonStyle(BasirIconButtonStyle())
                }

                AskAboutResultLink(text: resultText)

                if let docxURL = lastDocxURL {
                    ShareLink(item: docxURL) {
                        Label(
                            L10n.t("حفظ أو مشاركة ملف Word", "Save or share the Word file"),
                            systemImage: "doc.fill"
                        )
                    }
                    .buttonStyle(BasirSecondaryButtonStyle(tone: .success))
                    .accessibilityHint(L10n.t(
                        "يفتح خيارات الحفظ والمشاركة لملف Word الناتج.",
                        "Opens save and share options for the generated Word file."
                    ))
                } else {
                    Button {
                        Task { await buildDocxFile() }
                    } label: {
                        if isBuildingDocx {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(L10n.t("جارٍ إنشاء ملف Word", "Creating the Word file"))
                            }
                        } else {
                            Label(
                                L10n.t("إنشاء ملف Word من النتيجة", "Create a Word file from the result"),
                                systemImage: "doc.badge.plus"
                            )
                        }
                    }
                    .buttonStyle(BasirSecondaryButtonStyle(tone: .success))
                    .disabled(isBuildingDocx)
                    .accessibilityHint(L10n.t(
                        "ينشئ ملف DOCX قابلًا للحفظ والمشاركة من النتيجة الحالية.",
                        "Creates a saveable and shareable DOCX file from the current result."
                    ))
                }
            }

            failedBatchesSection

            if let errorMessage {
                BasirStatusBanner(
                    text: errorMessage,
                    tone: .danger,
                    title: L10n.t("تعذرت المعالجة", "Processing could not be completed")
                )
            }
        }
        .navigationTitle(L10n.t("تحويل المستند إلى Word", "Convert document to Word"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(types: Self.allowedTypes) { url in
                if let url { handlePicked(url: url) }
            }
        }
        .onAppear {
            if !hasAppliedInitialURL, let initialURL {
                hasAppliedInitialURL = true
                handlePicked(url: initialURL)
            }
        }
        .onDisappear {
            if isLoading {
                cancelRequested = true
                conversionTask?.cancel()
            }
            filePreparationTask?.cancel()
        }
    }

    private var pickerCard: some View {
        Button {
            showPicker = true
        } label: {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: pickedURL == nil ? "doc.badge.plus" : "doc.text.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BasirTheme.brand)
                    .frame(width: 54, height: 54)
                    .background(BasirTheme.brand.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(pickedURL == nil
                         ? L10n.t("اختيار مستند", "Choose a document")
                         : L10n.t("المستند المحدد", "Selected document"))
                        .font(.headline)

                    if let url = pickedURL {
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if pageCount > 0 {
                            Text(L10n.t("\(pageCount) صفحة", "\(pageCount) pages"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(L10n.t(
                            "PDF وWord وPowerPoint وRTF وTXT وCSV والصور. الحد الأقصى لملفات PDF هو 500 صفحة.",
                            "PDF, Word, PowerPoint, RTF, TXT, CSV, and image files. PDFs can contain up to 500 pages."
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .basirCardSurface()
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isPreparingFile)
        .accessibilityLabel(pickedURL == nil
                            ? L10n.t("اختيار مستند للتحويل", "Choose a document to convert")
                            : L10n.t("تغيير المستند المحدد", "Change the selected document"))
        .accessibilityHint(L10n.t(
            "يفتح تطبيق الملفات لاختيار مستند.",
            "Opens Files so you can choose a document."
        ))
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("مستوى الدقة", "Accuracy level"))
                .font(.subheadline.bold())
            Picker(L10n.t("مستوى الدقة", "Accuracy level"), selection: $settings.docQuality) {
                Text(L10n.t("سريع", "Fast")).tag("fast")
                Text(L10n.t("متوازن", "Balanced")).tag("balanced")
                Text(L10n.t("الأدق", "Most accurate")).tag("best")
            }
            .pickerStyle(.segmented)
            Text(L10n.t(
                "اختر السريع للمستندات البسيطة، والمتوازن للاستخدام المعتاد، والأدق للجداول والتخطيطات المعقدة والصفحات الممسوحة.",
                "Use Fast for simple documents, Balanced for everyday work, and Most accurate for tables, complex layouts, and scanned pages."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(isLoading)
    }

    private var translationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("لغة النتيجة", "Result language"))
                .font(.subheadline.bold())
            Picker(L10n.t("لغة النتيجة", "Result language"), selection: $translateTo) {
                Text(L10n.t("الاحتفاظ باللغة الأصلية", "Keep the original language")).tag("")
                ForEach(L10n.supportedTranslationLanguages.filter { $0.code != "auto" }, id: \.code) { lang in
                    Text(BasirSettings.shared.language == .arabic ? lang.ar : lang.en)
                        .tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            Text(L10n.t(
                "عند اختيار لغة، يترجم بصير النص مع محاولة الحفاظ على العناوين والقوائم والجداول.",
                "When you choose a language, Basir translates the text while preserving headings, lists, and tables where possible."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(isLoading)
    }

    private var runButton: some View {
        Button {
            conversionTask?.cancel()
            conversionTask = Task {
                await run()
                conversionTask = nil
            }
        } label: {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(.white) }
                Label(
                    isLoading
                        ? L10n.t("جاري تحويل المستند", "Converting the document")
                        : L10n.t("بدء التحويل", "Start conversion"),
                    systemImage: "wand.and.stars"
                )
            }
        }
        .buttonStyle(BasirPrimaryButtonStyle())
        .disabled(isLoading || isPreparingFile)
        .accessibilityHint(L10n.t(
            "يبدأ قراءة المستند وتحويله وفق الخيارات المحددة.",
            "Starts reading and converting the document with the selected options."
        ))
    }

    private var describeImagesToggle: some View {
        Toggle(isOn: $describeImages) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("إضافة وصف للصور والرسوم", "Describe images and figures"))
                    .font(.callout.bold())
                Text(L10n.t(
                    "يضيف وصفًا نصيًا للصور والمخططات داخل المستند. فعّله فقط عندما تكون العناصر البصرية مهمة، لأنه يزيد مدة المعالجة.",
                    "Adds text descriptions for images and charts in the document. Turn it on only when visual content matters, because it increases processing time."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(isLoading)
    }

    private var mathToggle: some View {
        Toggle(isOn: $mathMode) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("قراءة المعادلات الرياضية", "Read mathematical equations"))
                    .font(.callout.bold())
                Text(L10n.t(
                    "يحوّل المعادلات إلى وصف منطوق ويضيف صيغة LaTeX للمراجعة والنسخ.",
                    "Turns equations into spoken descriptions and adds LaTeX for review and copying."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(isLoading)
    }

    private var conversionProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("جاري تحويل المستند", "Converting the document"))
                        .font(.headline)
                    Text(currentProgressText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }

            if statusNote.isEmpty, progress.total > 1 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .tint(BasirTheme.brand)
                    .accessibilityLabel(L10n.t("تقدم التحويل", "Conversion progress"))
                    .accessibilityValue("\(progress.done) / \(progress.total)")
            }

            Button(role: .destructive) {
                cancelRequested = true
                conversionTask?.cancel()
            } label: {
                Label(L10n.t("إيقاف التحويل", "Stop conversion"), systemImage: "stop.circle.fill")
            }
            .buttonStyle(BasirSecondaryButtonStyle(tone: .danger))
            .accessibilityHint(L10n.t(
                "يوقف الطلب الجاري ويحتفظ بالصفحات التي اكتملت معالجتها.",
                "Stops the active request and keeps pages that have already been completed."
            ))
        }
        .basirCardSurface()
    }

    private var currentProgressText: String {
        if !statusNote.isEmpty { return statusNote }
        if progress.total > 1 {
            return isScanning
                ? L10n.t("قراءة الصفحة \(progress.done) من \(progress.total)",
                         "Reading page \(progress.done) of \(progress.total)")
                : L10n.t("معالجة الجزء \(progress.done) من \(progress.total)",
                         "Processing part \(progress.done) of \(progress.total)")
        }
        return L10n.t(
            "يُرجى إبقاء هذه الشاشة مفتوحة حتى تظهر النتيجة.",
            "Keep this screen open until the result appears."
        )
    }

    @ViewBuilder
    private var failedBatchesSection: some View {
        let failed = batches.filter { $0.isFailed }
        if !failed.isEmpty && !isLoading {
            VStack(alignment: .leading, spacing: 14) {
                BasirStatusBanner(
                    text: L10n.t(
                        "اكتملت بقية الصفحات، لكن تعذرت معالجة \(failed.count) من أصل \(batches.count) جزء. يمكنك إعادة محاولة الأجزاء غير المكتملة فقط.",
                        "The remaining pages were completed, but \(failed.count) of \(batches.count) parts could not be processed. You can retry only the unfinished parts."
                    ),
                    tone: .warning,
                    title: L10n.t("النتيجة جزئية", "Partial result")
                )

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(failed) { batch in
                        if case let .failed(err) = batch.status {
                            Text(L10n.t(
                                "الصفحات \(batch.range.lowerBound) إلى \(batch.range.upperBound): \(err)",
                                "Pages \(batch.range.lowerBound) to \(batch.range.upperBound): \(err)"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .basirCardSurface(padding: 14)

                Button {
                    conversionTask?.cancel()
                    conversionTask = Task {
                        await retryFailedBatches()
                        conversionTask = nil
                    }
                } label: {
                    Label(
                        L10n.t("إعادة محاولة الأجزاء غير المكتملة", "Retry unfinished parts"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(BasirPrimaryButtonStyle(tone: .warning))
                .accessibilityHint(L10n.t(
                    "يعيد معالجة الأجزاء التي لم تكتمل فقط، ويحتفظ بالنتائج الناجحة.",
                    "Retries only unfinished parts and keeps all successful results."
                ))
            }
        }
    }

    private func handlePicked(url: URL) {
        filePreparationTask?.cancel()
        filePreparationTask = Task {
            await preparePickedFile(url: url)
            filePreparationTask = nil
        }
    }

    private func preparePickedFile(url: URL) async {
        isPreparingFile = true
        errorMessage = nil
        defer { isPreparingFile = false }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let prepared = try await Task.detached(priority: .userInitiated) { () throws -> (URL, Int) in
                try Task.checkCancellation()
                let fileExtension = url.pathExtension.lowercased()
                guard DocumentText.supportedExtensions.contains(fileExtension) else {
                    throw DocumentTextError.unsupportedType(fileExtension)
                }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else {
                    throw NSError(domain: "BasirImport", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "The selected item is not a regular file."
                    ])
                }
                let size = Int64(values.fileSize ?? 0)
                guard size > 0 else {
                    throw NSError(domain: "BasirImport", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "The selected file is empty."
                    ])
                }
                guard size <= Self.maximumImportedDocumentBytes else {
                    throw NSError(domain: "BasirImport", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "The selected file exceeded the allowed size."
                    ])
                }

                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: url, to: destination)
                do {
                    try Task.checkCancellation()
                    let pages = destination.pathExtension.lowercased() == "pdf"
                        ? PdfReader.pageCount(of: destination) : 0
                    return (destination, pages)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            }.value

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: prepared.0)
                return
            }
            if let old = pickedURL, old != prepared.0 {
                try? FileManager.default.removeItem(at: old)
            }
            pickedURL = prepared.0
            pageCount = prepared.1
            resultText = ""
            convertedResult = nil
            conversionReport = nil
            lastDocxURL = nil
            batches = []
        } catch is CancellationError {
            return
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }

    private func run() async {
        guard let url = pickedURL else { return }
        isLoading = true
        errorMessage = nil
        conversionReport = nil
        resultText = ""
        progress = (done: 0, total: 0)
        cancelRequested = false
        lastDocxURL = nil
        batches = []
        isScanning = false
        convertedResult = nil
        statusNote = ""
        ProcessingFeedback.start()
        var succeeded = false
        defer {
            isLoading = false
            progress = (done: 0, total: 0)
            isScanning = false
            statusNote = ""
            if succeeded { ProcessingFeedback.done() }
            else { ProcessingFeedback.failed() }
        }

        do {
            let ext = url.pathExtension.lowercased()
            let isImageFile = DocumentText.imageExtensions.contains(ext)

            // ===== Android-parity structured conversion (PDF / image) =====
            // Gemini SEES the real page and returns structured JSON, so
            // tables come back as real cell data and the Word file is a
            // genuine table instead of flattened local text. Both direct
            // Gemini and a configured proxy use this structured path.
            if (ext == "pdf" || isImageFile), StructuredDocConverter.isAvailable {
                isScanning = true
                let options = DocConvertOptions(translateTo: translateTo,
                                                describeImages: describeImages,
                                                math: mathMode)
                let result: StructuredDocConverter.Result
                if ext == "pdf" {
                    result = try await StructuredDocConverter.convertPdf(
                        url: url, options: options,
                        shouldCancel: { cancelRequested },
                        onStatus: { note in statusNote = note },
                        onProgress: { d, t in progress = (done: d, total: t) },
                        onPartial: { txt in resultText = txt })
                } else {
                    result = try await StructuredDocConverter.convertImage(
                        url: url, options: options,
                        onProgress: { d, t in progress = (done: d, total: t) })
                }
                isScanning = false
                convertedResult = result
                resultText = StructuredDocConverter.displayText(result)
                conversionReport = L10n.t(result.diagnostics.summaryArabic,
                                          result.diagnostics.summaryEnglish)
                lastDocxURL = nil
                guard !resultText.isEmpty else {
                    throw NSError(domain: "BasirDocument", code: 1, userInfo: [
                        NSLocalizedDescriptionKey:
                            L10n.t("لم يُعثر على محتوى قابل للقراءة في الملف.",
                                   "No readable content was found in the file.")])
                }
                let complete = result.diagnostics.isComplete
                ArchiveStore.shared.addResult(ArchivedResult(
                    title: (complete
                            ? L10n.t("اكتملت معالجة الملف: ", "Processed document: ")
                            : L10n.t("نتيجة جزئية للملف: ", "Partial document result: "))
                        + url.lastPathComponent,
                    kind: translateTo.isEmpty ? "convert" : "translate_doc",
                    text: resultText,
                    summary: String(resultText.prefix(140))))
                if complete {
                    LastDocumentStore.shared.set(text: resultText,
                                                 sourceName: url.lastPathComponent)
                }
                UIAccessibility.post(notification: .announcement,
                    argument: complete
                        ? L10n.t("اكتملت المعالجة. راجع النتيجة قبل استخدامها.",
                                 "Processing is complete. Review the result before using it.")
                        : L10n.t("توقفت المعالجة أو بقيت صفحات غير مكتملة. حُفظت النتيجة الجزئية مع تقرير واضح.",
                                 "Processing stopped or some pages remain incomplete. The partial result was preserved with a clear report."))
                succeeded = true
                return
            }

            // ===== Legacy text path (DOCX / PPTX / TXT, or proxy / keyless) =====
            let pages: [String]
            var fromOCR = false
            switch ext {
            case "pdf":
                if describeImages {
                    // User wants images described → analyze every page with
                    // vision (even if a text layer exists), so figures and
                    // charts are captured, not just the text.
                    isScanning = true
                    let vision = await DocumentText.ocrPdf(
                        from: url, describeImages: true) { done, total in
                        progress = (done: done, total: total)
                    } ?? ""
                    isScanning = false
                    pages = Self.splitByCharBudget(vision)
                    fromOCR = true
                } else {
                    do {
                        pages = try await Task.detached(priority: .userInitiated) {
                            try PdfReader.extractPages(from: url)
                        }.value
                    } catch PdfReadError.empty {
                        // Scanned PDF (no text layer): OCR each page via Gemini
                        // vision, then process the transcription like any text.
                        // Report per-page scan progress to the progress bar.
                        isScanning = true
                        let ocr = await DocumentText.ocrPdf(from: url) { done, total in
                            progress = (done: done, total: total)
                        } ?? ""
                        isScanning = false
                        pages = Self.splitByCharBudget(ocr)
                        fromOCR = true
                    }
                }
            case "docx", "pptx", "rtf":
                // Read document containers away from the main actor, then
                // split their text into stable page-equivalent chunks.
                let text = try await Task.detached(priority: .userInitiated) {
                    try DocumentText.extractLocal(from: url)
                }.value
                pages = Self.splitByCharBudget(text)
            case "jpg", "jpeg", "png", "heic", "heif",
                 "gif", "bmp", "tiff", "tif", "webp":
                // Image file (photo/scan) picked from Files → OCR via
                // Gemini vision, then process the transcription as text.
                isScanning = true
                let ocr = try await DocumentText.ocrImage(
                    from: url, describeImages: describeImages) { done, total in
                    progress = (done: done, total: total)
                }
                isScanning = false
                pages = Self.splitByCharBudget(ocr)
                fromOCR = true
            default:
                let text = try await Task.detached(priority: .userInitiated) {
                    try DocumentText.extractLocal(from: url)
                }.value
                pages = Self.splitByCharBudget(text)
            }
            guard pages.contains(where: { !$0.isEmpty }) else {
                throw NSError(domain: "BasirDocument", code: 1,
                              userInfo: [NSLocalizedDescriptionKey:
                                L10n.t("لم يُعثر على نص قابل للقراءة في الملف.",
                                       "No readable text was found in the file.")])
            }

            // Smart: a scanned PDF was already transcribed by Gemini OCR.
            // If the user only wants to read/convert it (no translation,
            // no math), the OCR text IS the result — skip a second,
            // wasteful Gemini pass over the same content.
            if fromOCR && translateTo.isEmpty && !mathMode {
                resultText = pages.joined(separator: "\n\n")
                lastDocxURL = nil
                ArchiveStore.shared.addResult(ArchivedResult(
                    title: L10n.t("اكتمل استخراج النص من: ", "Text extracted from: ") + url.lastPathComponent,
                    kind: "convert",
                    text: resultText,
                    summary: String(resultText.prefix(140))
                ))
                LastDocumentStore.shared.set(text: resultText,
                                             sourceName: url.lastPathComponent)
                UIAccessibility.post(notification: .announcement,
                                     argument: L10n.t("اكتملت المعالجة. راجع النتيجة قبل استخدامها.",
                                                       "Processing is complete. Review the result before using it."))
                succeeded = true
                return
            }

            // Batch pages into Gemini-sized chunks and seed state.
            let rawBatches = Self.batch(pages, pagesPerBatch: PdfReader.pagesPerBatch)
            batches = rawBatches.enumerated().map { idx, b in
                ConvertBatch(id: idx, range: b.range,
                              input: b.text, status: .pending)
            }
            progress = (done: 0, total: batches.count)

            await runBatches(allIndices: Array(batches.indices),
                             sourceName: url.lastPathComponent)
            succeeded = !resultText.isEmpty
        } catch {
            if cancelRequested || error is CancellationError || isCancelledError(error) {
                conversionReport = L10n.t(
                    "أُوقفت المعالجة. احتُفظ بكل ما اكتمل دون الادعاء بأن المستند كامل.",
                    "Processing was stopped. All completed content was kept without claiming the document is complete.")
                UIAccessibility.post(notification: .announcement,
                                     argument: conversionReport)
                succeeded = !resultText.isEmpty
            } else {
                errorMessage = UserFriendlyErrorMapper.map(error)
            }
        }
    }

    /// v3.3 — retry only the FAILED batches from the previous run.
    /// Successful batches keep their output verbatim; the retry loop
    /// re-runs the failed ones in order and re-aggregates resultText.
    private func retryFailedBatches() async {
        let failedIdx = batches.enumerated()
            .filter { $0.element.isFailed }
            .map(\.offset)
        guard !failedIdx.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        cancelRequested = false
        // Reset the retry candidates back to .pending so the UI flips
        // out of the warning banner while they're in flight.
        for i in failedIdx { batches[i].status = .pending }
        progress = (done: 0, total: failedIdx.count)
        ProcessingFeedback.start()
        defer {
            isLoading = false
            progress = (done: 0, total: 0)
            ProcessingFeedback.done()
        }
        let sourceName = pickedURL?.lastPathComponent ?? "document"
        await runBatches(allIndices: failedIdx, sourceName: sourceName)
    }

    /// Shared loop body for the initial run + the retry run. Walks
    /// the requested batch indices, calls Gemini per batch, records
    /// success or failure into `batches[i].status`, and rebuilds
    /// `resultText` from the union of successful outputs in order.
    private func runBatches(allIndices: [Int], sourceName: String) async {
        for (loopIdx, batchIdx) in allIndices.enumerated() {
            if cancelRequested || Task.isCancelled { break }
            let b = batches[batchIdx]
            let target = translateTo.isEmpty ? nil : GeminiPrompts.bcp47Name(translateTo)
            let scoped = GeminiPrompts.documentTextChunkInstruction(
                pageRange: b.range,
                translateToName: target,
                math: mathMode)
            do {
                let response = try await AiProviderFactory.current().ask(
                    task: .convert,
                    input: b.input,
                    instruction: scoped,
                    language: BasirSettings.shared.language,
                    imageData: nil,
                    mimeType: nil
                )
                batches[batchIdx].status = .success(output: response)
            } catch {
                if cancelRequested || Task.isCancelled || isCancelledError(error) { break }
                // v3.3 — a single batch failure does NOT abort the run.
                // We record it, keep going, and surface a retry button
                // when the loop ends.
                batches[batchIdx].status = .failed(
                    error: UserFriendlyErrorMapper.map(error))
            }
            progress = (done: loopIdx + 1, total: allIndices.count)
            // Rebuild resultText from every success in original order.
            resultText = batches.compactMap(\.output).joined(separator: "\n\n")
            // Invalidate any stale DOCX whenever we change resultText.
            lastDocxURL = nil
        }

        if !cancelRequested {
            let failedCount = batches.filter(\.isFailed).count
            conversionReport = failedCount == 0
                ? L10n.t("اكتملت جميع الأجزاء: \(batches.count) من \(batches.count).",
                         "All parts completed: \(batches.count) of \(batches.count).")
                : L10n.t("اكتمل \(batches.count - failedCount) من \(batches.count) جزء، وتعذّر \(failedCount). النتيجة جزئية.",
                         "Completed \(batches.count - failedCount) of \(batches.count) parts; \(failedCount) failed. The result is partial.")
            if failedCount == 0 {
                ArchiveStore.shared.addResult(ArchivedResult(
                    title: L10n.t("اكتملت معالجة الملف: ", "Processed document: ") + sourceName,
                    kind: translateTo.isEmpty ? "convert" : "translate_doc",
                    text: resultText,
                    summary: String(resultText.prefix(140))
                ))
                // Cache for "Ask about the latest document" (Documents tab).
                LastDocumentStore.shared.set(text: resultText, sourceName: sourceName)
                UIAccessibility.post(notification: .announcement,
                                      argument: L10n.t("اكتملت المعالجة. راجع النتيجة قبل استخدامها.",
                                                        "Processing is complete. Review the result before using it."))
            } else {
                UIAccessibility.post(notification: .announcement,
                                      argument: L10n.t(
                                          "اكتملت المعالجة، لكن تعذّر إنهاء \(failedCount) أجزاء. يمكنك إعادة محاولتها.",
                                          "Processing finished, but \(failedCount) parts did not complete. You can retry them."))
            }
        } else {
            conversionReport = L10n.t(
                "أُوقفت المعالجة بعد اكتمال \(batches.filter { $0.output != nil }.count) من \(batches.count) جزء. النتيجة جزئية.",
                "Processing stopped after \(batches.filter { $0.output != nil }.count) of \(batches.count) parts. The result is partial.")
        }
    }

    private func isCancelledError(_ error: Error) -> Bool {
        if case GeminiError.cancelled = error { return true }
        return false
    }

    // MARK: - Chunking helpers

    /// Split a flat string into "page-equivalent" pieces so DOCX /
    /// PPTX / TXT inputs can ride the same batching pipeline as PDF.
    /// Targets ~4000 characters per piece (≈600-800 tokens),
    /// preferring paragraph boundaries. Empty input collapses to a
    /// single empty entry so the page-count guard upstream still
    /// fires correctly.
    private static func splitByCharBudget(_ text: String,
                                            target: Int = 4000) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [""] }
        var out: [String] = []
        var current = ""
        for paragraph in trimmed.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 > target && !current.isEmpty {
                out.append(current)
                current = ""
            }
            if !current.isEmpty { current += "\n\n" }
            current += paragraph
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Group `pages` into batches of `pagesPerBatch` and stamp each
    /// page with its "[Page N]" header so the model can refer back to
    /// page numbers in the output. Empty pages still count toward the
    /// numbering so subsequent batches stay aligned.
    private static func batch(_ pages: [String],
                                pagesPerBatch: Int)
                              -> [(text: String, range: ClosedRange<Int>)] {
        var result: [(text: String, range: ClosedRange<Int>)] = []
        var i = 0
        while i < pages.count {
            let end = min(i + pagesPerBatch, pages.count)
            var sb = ""
            for j in i..<end {
                let body = pages[j].isEmpty
                    ? "(no readable text on this page)"
                    : pages[j]
                sb += "[Page \(j + 1)]\n\(body)\n\n"
            }
            result.append((sb, (i + 1)...end))
            i = end
        }
        return result
    }

    /// Build a .docx file from the current resultText and stash its
    /// URL into lastDocxURL so the ShareLink shows up. Writes into the
    /// caches dir so the share sheet can read it without sandbox
    /// surprises; the OS reaps the file when caches are pruned.
    private func buildDocxFile() async {
        guard !resultText.isEmpty, !isBuildingDocx else { return }
        isBuildingDocx = true
        errorMessage = nil
        defer { isBuildingDocx = false }

        let rtl = BasirSettings.shared.language == .arabic
        let baseName = pickedURL?.deletingPathExtension().lastPathComponent ?? "Basir"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-basir-\(UUID().uuidString).docx")
        let structured = convertedResult
        let plainText = resultText

        do {
            let url = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                try Task.checkCancellation()
                if let structured {
                    try StructuredDocConverter.buildDocx(structured, rtl: rtl, to: outputURL)
                } else {
                    var writer = DocxWriter(rtl: rtl)
                    writer.appendPlain(plainText)
                    try writer.write(to: outputURL)
                }
                try Task.checkCancellation()
                return outputURL
            }.value
            if let old = lastDocxURL, old != url { try? FileManager.default.removeItem(at: old) }
            lastDocxURL = url
            UIAccessibility.post(notification: .announcement,
                                  argument: L10n.t(
                                      "ملف Word جاهز. استخدم زر المشاركة لحفظه أو إرساله.",
                                      "Your Word file is ready. Use Share to save or send it."))
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
