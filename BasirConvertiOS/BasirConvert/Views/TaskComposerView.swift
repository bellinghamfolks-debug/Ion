import SwiftUI
import UIKit
import VisionKit
import UniformTypeIdentifiers

struct TaskComposerView: View {
    let operation: OperationKind

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var network: NetworkMonitor
    @State private var pendingURLs: [URL] = []
    @State private var metadata: [String: DocumentMetadata] = [:]
    @State private var showSourceMenu = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showPrivacyConfirmation = false
    @State private var showConfigurationRequired = false
    @State private var pickerError: String?
    @State private var previewItem: PreviewItem?
    @State private var customOutputName = ""
    @State private var passwordURL: URL?
    @State private var pdfPassword = ""

    private var isTranslation: Bool { operation == .translate }
    private var supportedExtensions: Set<String> {
        isTranslation ? SupportedInput.translationExtensions : SupportedInput.conversionExtensions
    }
    private var contentTypes: [UTType] {
        isTranslation
            ? [.pdf, .basirDOCX, .basirDOC, .basirPPTX, .basirPPT, .image]
            : [.pdf, .basirPPTX, .basirPPT, .image, .audio, .movie]
    }
    private var options: ConversionOptions {
        ConversionOptions(
            operation: operation,
            outputMode: settings.outputMode,
            targetLanguage: isTranslation ? settings.targetLanguage : nil,
            embedVisuals: settings.embedVisuals,
            includeMath: settings.includeMath,
            preserveSymbols: settings.preserveSymbols,
            interfaceLanguage: l10n.language,
            pdfQuality: settings.pdfQuality,
            pageSelection: settings.pageSelection,
            includeSpeakerNotes: settings.includeSpeakerNotes,
            includeHiddenSlides: settings.includeHiddenSlides,
            preserveLinks: settings.preserveLinks,
            skipBlankPages: settings.skipBlankPages,
            preferPDFText: settings.preferPDFText,
            concurrentPages: settings.concurrentPages,
            rotationCorrection: settings.rotationCorrection,
            outputName: customOutputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : customOutputName,
            preferredModel: settings.preferredModel.rawValue
        )
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BasirHeroCard(
                        title: isTranslation
                            ? l10n.t("ترجمة", "Translate")
                            : l10n.t("تحويل", "Convert"),
                        systemImage: isTranslation ? "character.book.closed.fill" : "doc.richtext.fill"
                    )

                    if pendingURLs.isEmpty {
                        PrimaryActionButton(
                            title: l10n.t("اختيار ملف أو صورة أو تسجيل صوتي", "Choose a file, image, or audio recording"),
                            systemImage: "plus.circle.fill"
                        ) { showSourceMenu = true }
                    } else {
                        selectedFilesSection
                    }

                    if isTranslation { languageCard }
                    taskSummaryCard

                    VStack(alignment: .leading, spacing: 10) {
                        GlassSectionTitle(title: l10n.t("اسم النتيجة", "Result name"), systemImage: "pencil")
                        TextField(l10n.t("اختياري", "Optional"), text: $customOutputName)
                            .textInputAutocapitalization(.sentences)
                            .padding(14)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .glassSurface()

                    if let pickerError { InlineMessage(text: pickerError, isError: true) }

                    if !pendingURLs.isEmpty {
                        PrimaryActionButton(
                            title: isTranslation ? l10n.t("بدء الترجمة", "Start translation")
                                                 : l10n.t("بدء التحويل", "Start conversion"),
                            systemImage: "play.fill"
                        ) {
                            if !settings.isConfigured { showConfigurationRequired = true }
                            else { showPrivacyConfirmation = true }
                        }
                    }
                }
                .appScreenContent(bottomPadding: 28)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog(l10n.t("مصدر المستند", "Document source"),
                            isPresented: $showSourceMenu,
                            titleVisibility: .visible) {
            Button(l10n.t("تطبيق الملفات", "Files"), systemImage: "folder") { showFiles = true }
            Button(l10n.t("مكتبة الصور", "Photos"), systemImage: "photo.on.rectangle.angled") { showPhotos = true }
            Button(l10n.t("التقاط صورة", "Take a photo"), systemImage: "camera") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                else { pickerError = l10n.t("الكاميرا غير متاحة على هذا الجهاز.", "The camera is not available on this device.") }
            }
            Button(l10n.t("مسح مستند متعدد الصفحات", "Scan a multi-page document"), systemImage: "doc.viewfinder") {
                if VNDocumentCameraViewController.isSupported { showScanner = true }
                else { pickerError = l10n.t("ماسح المستندات غير متاح على هذا الجهاز.", "Document scanning is not available on this device.") }
            }
            Button(l10n.t("لصق صورة من الحافظة", "Paste an image from clipboard"), systemImage: "doc.on.clipboard") {
                pasteImages()
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { }
        }
        .alert(l10n.t("تأكيد الإرسال", "Confirm sending"), isPresented: $showPrivacyConfirmation) {
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { }
            Button(isTranslation ? l10n.t("بدء الترجمة", "Start translation")
                                 : l10n.t("بدء التحويل", "Start conversion")) { enqueuePending() }
        } message: { Text(privacyMessage) }
        .alert(l10n.t("تعذر بدء المهمة", "Unable to start"), isPresented: $showConfigurationRequired) {
            Button(l10n.t("حسنًا", "OK"), role: .cancel) { }
        } message: {
            Text(l10n.t("التطبيق غير مرتبطة بالاتصال بعد. ثبّت النسخة النهائية المرتبطة بالخادم.",
                        "The app is not connected to the Connection. Install the final server-enabled build."))
        }
        .alert(l10n.t("ملف PDF محمي", "Password-protected PDF"), isPresented: Binding(
            get: { passwordURL != nil },
            set: { if !$0 { passwordURL = nil; pdfPassword = "" } }
        )) {
            SecureField(l10n.t("كلمة مرور الملف", "PDF password"), text: $pdfPassword)
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) {
                if let passwordURL { remove(passwordURL) }
                self.passwordURL = nil
                pdfPassword = ""
            }
            Button(l10n.t("فتح الملف", "Unlock")) { unlockPDF() }
        } message: {
            Text(l10n.t("تُستخدم كلمة المرور محليًا لإنشاء نسخة غير محمية، ولا تُحفظ ولا تُرسل.",
                        "The password is used locally to make an unlocked copy. It is neither stored nor sent."))
        }
        .fullScreenCover(isPresented: $showFiles) {
            BasirDocumentPicker(contentTypes: contentTypes, allowsMultipleSelection: true) { urls in
                showFiles = false
                handleSelected(urls)
            } onCancel: { showFiles = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotos) {
            PhotoLibraryPicker { urls in
                showPhotos = false
                handleSelected(urls)
            } onError: { error in
                showPhotos = false
                pickerError = error.localizedDescription
            } onCancel: { showPhotos = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { url in
                showCamera = false
                handleSelected([url])
            } onError: { error in
                showCamera = false
                pickerError = error.localizedDescription
            } onCancel: { showCamera = false }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { url in
                showScanner = false
                handleSelected([url])
            } onError: { error in
                showScanner = false
                pickerError = error.localizedDescription
            } onCancel: { showScanner = false }
            .ignoresSafeArea()
        }
        .sheet(item: $previewItem) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        .onAppear { receiveExternalIfNeeded() }
        .onChange(of: viewModel.routedExternalBatch?.id) { _ in receiveExternalIfNeeded() }
        .onChange(of: viewModel.routedExternalDocument?.id) { _ in receiveExternalIfNeeded() }
    }

    private var taskSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionTitle(title: l10n.t("إعدادات المهمة", "Task settings"), systemImage: "gearshape.2.fill")
            Text(settings.preferredModel.title(l10n))
                .font(.headline)
            Text(settings.preferredModel.detail(l10n))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            Text(l10n.t(
                "محتوى Word: \(settings.outputMode.title(l10n)) • الصور: \(settings.embedVisuals ? "نعم" : "لا") • المعادلات: \(settings.includeMath ? "نعم" : "لا")",
                "Word content: \(settings.outputMode.title(l10n)) • images: \(settings.embedVisuals ? "on" : "off") • math: \(settings.includeMath ? "on" : "off")"
            ))
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            Button { viewModel.isSettingsPresented = true } label: {
                Label(l10n.t("تغيير إعدادات المهمة", "Change task settings"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .tint(BasirPalette.cyan)
            .frame(minHeight: 44)
        }
        .glassSurface()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("لغة الترجمة", "Translation language"), systemImage: "character.bubble")
            Picker(l10n.t("اختر لغة الترجمة", "Choose translation language"),
                   selection: Binding(get: { settings.targetLanguageCode }, set: {
                    settings.targetLanguageCode = $0; settings.save()
                   })) {
                ForEach(SupportedLanguage.all) { Text($0.name(interface: l10n.language)).tag($0.code) }
            }
            .pickerStyle(.menu).tint(BasirPalette.cyan)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .glassSurface()
    }

    private var resultStyleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("محتوى ملف Word", "Word file content"), systemImage: "slider.horizontal.3")
            Picker(l10n.t("محتوى الملف", "File content"), selection: Binding(get: { settings.outputMode }, set: {
                settings.outputMode = $0; settings.save()
            })) {
                ForEach(OutputMode.allCases) { Text($0.title(l10n)).tag($0) }
            }
            .pickerStyle(.menu).tint(BasirPalette.cyan)
        }
        .glassSurface()
    }

    private var sourceOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(l10n.t("إدراج الصور والشعارات", "Include images and logos"), isOn: Binding(
                get: { settings.embedVisuals }, set: { settings.embedVisuals = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            Toggle(l10n.t("شرح المعادلات الرياضية", "Explain mathematical equations"), isOn: Binding(
                get: { settings.includeMath }, set: { settings.includeMath = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            Toggle(l10n.t("الحفاظ على الرموز ومعانيها", "Preserve symbols and their meaning"), isOn: Binding(
                get: { settings.preserveSymbols }, set: { settings.preserveSymbols = $0; settings.save(); OperationFeedback.selectionChanged() }
            )).tint(BasirPalette.cyan)
            Text(l10n.t(
                "يشمل علامات الصح والخطأ ومربعات الاختيار والتحذير والأسهم والرموز المشابهة مثل ✓ ✗ ☑ ☐ ⚠.",
                "Includes check/cross marks, checkboxes, warnings, arrows, and similar symbols such as ✓ ✗ ☑ ☐ ⚠."
            ))
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            if !isTranslation {
                Text(l10n.t(
                    "يدعم بصير أيضًا التسجيلات الصوتية من تطبيق الملفات ويحوّلها إلى تفريغ مكتوب داخل ملف Word، بما في ذلك التسجيلات الطويلة.",
                    "Basir also accepts audio recordings from Files and creates a written Word transcript, including long recordings."
                ))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(l10n.t("صفحات PDF المطلوبة (اختياري)", "PDF pages (optional)")).font(.subheadline.weight(.semibold))
                TextField(l10n.t("مثال: 1-20، 25، 30-40", "Example: 1-20, 25, 30-40"),
                          text: Binding(get: { settings.pageSelection }, set: {
                            settings.pageSelection = $0; settings.save()
                          }))
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .glassSurface()
    }

    private var selectedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionTitle(title: l10n.t("العناصر المختارة: \(pendingURLs.count)",
                                                "Selected items: \(pendingURLs.count)"),
                                  systemImage: "checkmark.circle.fill")
                Spacer()
                Button(l10n.t("إضافة", "Add")) { showSourceMenu = true }.buttonStyle(.bordered)
            }
            ForEach(pendingURLs, id: \.standardizedFileURL) { url in
                VStack(alignment: .leading, spacing: 8) {
                    Text(url.lastPathComponent).font(.headline).lineLimit(3)
                    if let value = metadata[url.standardizedFileURL.path] {
                        Text(metadataText(value)).font(.footnote).foregroundStyle(BasirPalette.secondaryText)
                    } else {
                        ProgressView().tint(BasirPalette.cyan).accessibilityLabel(l10n.t("جارٍ فحص الملف", "Inspecting file"))
                    }
                    HStack {
                        Button { previewItem = PreviewItem(url: url) } label: {
                            Label(l10n.t("معاينة", "Preview"), systemImage: "eye")
                        }
                        .buttonStyle(.bordered).tint(BasirPalette.cyan)
                        Button(role: .destructive) { remove(url) } label: {
                            Label(l10n.t("إزالة", "Remove"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .glassSurface(accent: .green)
    }

    private func handleSelected(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pickerError = nil
        let valid = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard valid.count == urls.count else {
            pickerError = l10n.t("أحد العناصر المختارة غير مدعوم في هذه العملية.", "One selected item is unsupported for this task.")
            return
        }
        Task {
            do {
                let normalized: [URL]
                if valid.count > 1, valid.allSatisfy({ SupportedInput.imageExtensions.contains($0.pathExtension.lowercased()) }) {
                    let combined = try await Task.detached(priority: .userInitiated) {
                        try MediaImport.combineImagesAsPDF(valid, name: "صور مجمعة.pdf")
                    }.value
                    valid.forEach(viewModel.discardExternalSource)
                    normalized = [combined]
                } else { normalized = valid }
                for url in normalized where !pendingURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    pendingURLs.append(url)
                    inspect(url)
                }
                UIAccessibility.post(notification: .announcement,
                                     argument: l10n.t("تم اختيار \(normalized.count) من العناصر.", "Added \(normalized.count) item(s)."))
            } catch { pickerError = error.localizedDescription }
        }
    }

    private func inspect(_ url: URL) {
        Task {
            do {
                let value = try await Task.detached(priority: .utility) { try DocumentInspector.inspect(url) }.value
                metadata[url.standardizedFileURL.path] = value
            } catch {
                if let basir = error as? BasirError, case .passwordProtectedPDF = basir {
                    passwordURL = url
                } else {
                    remove(url)
                    pickerError = error.localizedDescription
                }
            }
        }
    }

    private func unlockPDF() {
        guard let source = passwordURL else { return }
        let password = pdfPassword
        passwordURL = nil
        pdfPassword = ""
        Task {
            do {
                let unlocked = try await Task.detached(priority: .userInitiated) {
                    try DocumentInspector.unlockedCopy(of: source, password: password)
                }.value
                if let index = pendingURLs.firstIndex(where: { $0.standardizedFileURL == source.standardizedFileURL }) {
                    pendingURLs[index] = unlocked
                }
                viewModel.discardExternalSource(source)
                inspect(unlocked)
            } catch {
                passwordURL = source
                pickerError = l10n.t("كلمة المرور غير صحيحة أو تعذر فتح الملف.",
                                     "The password is incorrect or the PDF could not be unlocked.")
            }
        }
    }

    private func remove(_ url: URL) {
        pendingURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        metadata.removeValue(forKey: url.standardizedFileURL.path)
        viewModel.discardExternalSource(url)
    }

    private func pasteImages() {
        do { handleSelected(try MediaImport.pasteboardImages()) }
        catch { pickerError = l10n.t("لا توجد صورة قابلة للصق في الحافظة.", "There is no pasteable image on the clipboard.") }
    }

    private func receiveExternalIfNeeded() {
        if let batch = viewModel.routedExternalBatch, batch.operation == operation {
            viewModel.consumeRoutedExternalBatch(id: batch.id)
            handleSelected(batch.urls)
        } else if let document = viewModel.routedExternalDocument, document.operation == operation {
            viewModel.consumeRoutedExternalDocument(id: document.id)
            handleSelected([document.url])
        }
    }

    private func enqueuePending() {
        let selected = pendingURLs
        pendingURLs = []
        metadata = [:]
        customOutputName = ""
        settings.save()
        viewModel.start(pickerURLs: selected, options: options,
                        configuration: settings.configuration, l10n: l10n)
    }

    private func metadataText(_ value: DocumentMetadata) -> String {
        var parts = [value.humanReadableSize, value.contentType]
        if let count = value.itemCount { parts.append(l10n.t("\(count) صفحة أو صورة", "\(count) page(s) or image(s)")) }
        if let width = value.pixelWidth, let height = value.pixelHeight { parts.append("\(width)×\(height)") }
        return parts.joined(separator: " • ")
    }

    private var privacyMessage: String {
        let networkNotice = network.snapshot.isExpensive
            ? l10n.t(" أنت تستخدم بيانات الهاتف.", " You are using cellular data.") : ""
        return l10n.t(
            "سيُرسل محتوى \(pendingURLs.count) من العناصر إلى الاتصال لمعالجته، ثم تُنزّل النتيجة إلى جهازك.\(networkNotice)",
            "Content from \(pendingURLs.count) item(s) will be sent to the Connection, then the result will be downloaded to your device.\(networkNotice)"
        )
    }

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }
}

