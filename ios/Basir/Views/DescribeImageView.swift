import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum DescribeImageMode {
    case detailed, altText, screenshot, currencyOrReceipt
    case medical, legal, table

    var title: String {
        switch self {
        case .detailed: return L10n.t("وصف الصورة", "Image description")
        case .altText: return L10n.t("الوصف البديل", "Alt text")
        case .screenshot: return L10n.t("قراءة لقطة شاشة", "Read a screenshot")
        case .currencyOrReceipt: return L10n.t("قراءة عملة أو فاتورة", "Read currency or receipt")
        case .medical: return L10n.t("قراءة مستند طبي", "Read a medical document")
        case .legal: return L10n.t("قراءة مستند قانوني", "Read a legal document")
        case .table: return L10n.t("قراءة جدول", "Read a table")
        }
    }

    var intro: String {
        switch self {
        case .detailed:
            return L10n.t("التقط صورة واضحة قدر الإمكان. سيبدأ بصير بخلاصة ثم ينتقل إلى التفاصيل والنص الظاهر.",
                          "Capture the clearest image you can. Basir starts with a summary, then moves to detail and visible text.")
        case .altText:
            return L10n.t("ينشئ بصير وصفًا بديلًا موجزًا ودقيقًا مناسبًا للنشر وقارئات الشاشة.",
                          "Basir creates concise, accurate alt text suitable for publishing and screen readers.")
        case .screenshot:
            return L10n.t("اختر لقطة الشاشة كاملة لتبقى أسماء الأزرار والتنبيهات وموقعها في السياق.",
                          "Choose the full screenshot so buttons, alerts, and their position remain in context.")
        case .currencyOrReceipt:
            return L10n.t("ضع العملة أو الفاتورة على سطح ثابت وصوّرها بإضاءة جيدة. راجع المبلغ قبل أي دفع أو تسليم.",
                          "Place the banknote or receipt on a steady surface with good lighting. Verify the amount before paying or handing anything over.")
        case .medical:
            return L10n.t("سيقرأ بصير النص وينظمه، لكنه لا يشخّص حالة ولا يستبدل الطبيب أو الصيدلي.",
                          "Basir reads and organizes the text, but does not diagnose or replace a doctor or pharmacist.")
        case .legal:
            return L10n.t("سيشرح النص ويستخرج النقاط المهمة، لكنه لا يقدم استشارة قانونية ولا يحسم الأثر النظامي.",
                          "Basir explains the text and extracts key points, but does not provide legal advice or decide legal effect.")
        case .table:
            return L10n.t("اختر صورة واضحة للجدول أو أرفق الملف، وسيعرض كل صف مع عناوين أعمدته.",
                          "Choose a clear table image or attach the file. Basir presents each row with its column headers.")
        }
    }

    var task: TaskKind {
        switch self {
        case .detailed: return .describeImage
        case .altText: return .altText
        case .screenshot: return .screenshot
        case .currencyOrReceipt: return .currencyOrReceipt
        case .medical: return .medicalText
        case .legal: return .legalText
        case .table: return .tableRead
        }
    }

    var instruction: String {
        GeminiPrompts.imageTaskInstruction(task, english: AppLanguage.current != .arabic)
    }

    var resultTitle: String {
        switch self {
        case .altText: return L10n.t("الوصف البديل المقترح", "Suggested alt text")
        case .screenshot: return L10n.t("محتوى الشاشة", "Screen content")
        case .currencyOrReceipt: return L10n.t("القراءة المحتملة", "Likely reading")
        case .medical: return L10n.t("قراءة المستند الطبي", "Medical document reading")
        case .legal: return L10n.t("قراءة المستند القانوني", "Legal document reading")
        case .table: return L10n.t("محتوى الجدول", "Table content")
        case .detailed: return L10n.t("وصف الصورة", "Image description")
        }
    }
}

struct DescribeImageView: View {
    let mode: DescribeImageMode
    @State private var pickerItem: PhotosPickerItem?
    @State private var resultText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showDocPicker = false
    @State private var lastImageData: Data?

    private var allowsDocument: Bool {
        mode == .medical || mode == .legal || mode == .table
    }

    var body: some View {
        BasirScreen {
            BasirPageIntro(text: mode.intro, tone: introTone)

            BasirSectionHeader(
                title: L10n.t("إضافة المحتوى", "Add content"),
                subtitle: L10n.t("اختر طريقة واحدة، وستبدأ المعالجة تلقائيًا.",
                                 "Choose one method and processing starts automatically.")
            )

            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    Label(L10n.t("التقاط صورة الآن", "Take a photo now"), systemImage: "camera.fill")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            if CameraPicker.isAvailable {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة من المكتبة", "Choose from Photos"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirSecondaryButtonStyle())
                .disabled(isLoading)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة من المكتبة", "Choose from Photos"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            if allowsDocument {
                Button { showDocPicker = true } label: {
                    Label(L10n.t("اختيار ملف من تطبيق الملفات", "Choose a file from Files"),
                          systemImage: "doc.badge.plus")
                }
                .buttonStyle(BasirSecondaryButtonStyle(tone: .info))
                .disabled(isLoading)
            }

            if isLoading {
                BasirStatusBanner(
                    text: L10n.t("جاري قراءة المحتوى. اترك هذه الشاشة مفتوحة حتى تظهر النتيجة.",
                                 "Reading the content. Keep this screen open until the result appears."),
                    tone: .info,
                    title: L10n.t("جاري التحليل", "Analyzing")
                )
            }

            if let errorMessage {
                BasirStatusBanner(
                    text: errorMessage,
                    tone: .danger,
                    title: L10n.t("تعذّرت القراءة", "Could not read the content")
                )
            }

            if !resultText.isEmpty {
                BasirResultCard(title: mode.resultTitle, text: resultText) {
                    HStack(spacing: 4) {
                        CopyButton(text: resultText)
                        ShareLink(item: resultText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(BasirIconButtonStyle())
                        .accessibilityLabel(L10n.t("مشاركة النتيجة", "Share result"))
                    }
                }
                AskAboutResultLink(text: resultText, imageData: lastImageData)
                BasirStatusBanner(text: resultCaution, tone: .warning)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    guard !isLoading else { return }
                    if DocumentText.isImage(url) {
                        let data = await Task.detached(priority: .userInitiated) {
                            DocumentText.imageData(from: url)
                        }.value
                        guard let data else {
                            errorMessage = L10n.t(
                                "تعذّر تجهيز الصورة ضمن الحد الآمن.",
                                "The image could not be prepared within the safe limit."
                            )
                            return
                        }
                        await analyze(rawData: data)
                        return
                    }
                    isLoading = true
                    errorMessage = nil
                    defer { isLoading = false }
                    do {
                        let text = try await DocumentText.extractTextAsync(from: url)
                        await analyzeText(text)
                    } catch {
                        errorMessage = UserFriendlyErrorMapper.map(error)
                    }
                }
            }
        }
    }

    private var introTone: BasirTone {
        switch mode {
        case .currencyOrReceipt, .medical, .legal: return .warning
        default: return .info
        }
    }

    private var resultCaution: String {
        switch mode {
        case .currencyOrReceipt:
            return L10n.t("تحقق من الفئة والمبلغ بطريقة أخرى قبل الدفع أو التسليم. لا يستطيع بصير إثبات أصالة العملة.",
                          "Verify the denomination and amount another way before paying or handing it over. Basir cannot verify authenticity.")
        case .medical:
            return L10n.t("راجع الطبيب أو الصيدلي قبل اتخاذ قرار يتعلق بالعلاج أو الجرعة.",
                          "Consult a doctor or pharmacist before making treatment or dosage decisions.")
        case .legal:
            return L10n.t("راجع مختصًا قانونيًا قبل اتخاذ إجراء أو الاعتماد على تفسير النص.",
                          "Consult a legal professional before acting on or relying on the interpretation.")
        default:
            return BasirCopy.verifyImportantInformation
        }
    }

    private func analyzeText(_ text: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        resultText = ""
        lastImageData = nil
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            resultText = try await AiProviderFactory.current().ask(
                task: mode.task,
                input: String(text.prefix(12_000)),
                instruction: mode.instruction + " The content is provided below as text, not as an image.",
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        resultText = ""
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            guard let compressed = await Task.detached(priority: .userInitiated, operation: {
                ImagePreprocessor.jpeg(from: data)
            }).value else {
                throw GeminiError.decode("image could not be prepared safely")
            }
            lastImageData = compressed
            resultText = try await AiProviderFactory.current().ask(
                task: mode.task,
                input: "",
                instruction: mode.instruction,
                language: BasirSettings.shared.language,
                imageData: compressed,
                mimeType: "image/jpeg"
            )
            ProcessingFeedback.done()
            UIAccessibility.post(notification: .announcement, argument: BasirCopy.resultReady)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
