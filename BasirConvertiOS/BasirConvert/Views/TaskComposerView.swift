import SwiftUI
import UIKit
import VisionKit
import UniformTypeIdentifiers

/// The "New" tab: one place to convert or translate. Large source buttons
/// come first, the chosen files and options follow, and the latest result
/// stays one tap away underneath.
struct TaskComposerView: View {
    @Binding var operation: OperationKind

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var library: OutputLibraryStore
    @EnvironmentObject private var intents: IntentRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingURLs: [URL] = []
    @State private var metadata: [String: DocumentMetadata] = [:]
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showPrivacyConfirmation = false
    @State private var showConfigurationRequired = false
    @State private var pickerError: String?
    @State private var previewItem: PreviewItem?
    @State private var shareItem: OutputRecord?
    @State private var customOutputName = ""
    @State private var passwordURL: URL?
    @State private var pdfPassword = ""
    @AccessibilityFocusState private var focusSelectedFiles: Bool

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
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("مهمة جديدة", "New task"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(BasirPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    operationPicker

                    if pendingURLs.isEmpty {
                        SectionHeading(title: l10n.t("من أين الملف؟", "Where is the file?"))
                        sourceGrid
                        if !isTranslation {
                            Text(l10n.t(
                                "يقبل التحويل ملفات PDF والعروض والصور والتسجيلات الصوتية.",
                                "Conversion accepts PDF, presentations, images, and audio recordings."
                            ))
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        selectedFilesSection
                        if isTranslation { languageCard }
                        taskSummaryCard
                        resultNameCard
                    }

                    if let pickerError { InlineMessage(text: pickerError, isError: true) }

                    if !pendingURLs.isEmpty {
                        PrimaryActionButton(
                            title: isTranslation ? l10n.t("ابدأ الترجمة", "Start translation")
                                                 : l10n.t("ابدأ التحويل", "Start conversion"),
                            systemImage: "play.fill"
                        ) {
                            if !settings.isConfigured { showConfigurationRequired = true }
                            else { showPrivacyConfirmation = true }
                        }
                    }

                    if pendingURLs.isEmpty, let last = library.items.first {
                        SectionHeading(title: l10n.t("آخر نتيجة", "Latest result"))
                        lastResultCard(last)
                    }
                }
                .appScreenContent(bottomPadding: 28)
            }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("جديد", "New"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(l10n.t("تأكيد الإرسال", "Confirm sending"), isPresented: $showPrivacyConfirmation) {
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { }
            Button(isTranslation ? l10n.t("ابدأ الترجمة", "Start translation")
                                 : l10n.t("ابدأ التحويل", "Start conversion")) { enqueuePending() }
        } message: { Text(privacyMessage) }
        .alert(l10n.t("تعذر بدء المهمة", "Unable to start"), isPresented: $showConfigurationRequired) {
            Button(l10n.t("حسنًا", "OK"), role: .cancel) { }
        } message: {
            Text(l10n.t("هذه النسخة غير مرتبطة بخادم بصير بعد. ثبّت النسخة النهائية المرتبطة بالخادم.",
                        "This build is not connected to the Basir server. Install the final server-enabled build."))
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
        .sheet(item: $shareItem) { ActivityShareView(urls: [$0.url]) }
        .onAppear {
            receiveExternalIfNeeded()
            handleIntentIfNeeded()
        }
        .onChange(of: viewModel.routedExternalBatch?.id) { _ in receiveExternalIfNeeded() }
        .onChange(of: viewModel.routedExternalDocument?.id) { _ in receiveExternalIfNeeded() }
        .onChange(of: intents.pendingAction) { _ in handleIntentIfNeeded() }
        .onChange(of: operation) { _ in dropFilesUnsupportedByOperation() }
    }

    // MARK: - Operation

    private var operationPicker: some View {
        AdaptiveStack(spacing: BasirSpacing.s) {
            operationButton(.convert,
                            title: l10n.t("تحويل إلى Word", "Convert to Word"),
                            systemImage: "doc.richtext.fill")
            operationButton(.translate,
                            title: l10n.t("ترجمة", "Translate"),
                            systemImage: "character.book.closed.fill")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l10n.t("نوع المهمة", "Task type"))
    }

    private func operationButton(_ kind: OperationKind, title: String, systemImage: String) -> some View {
        let selected = operation == kind
        return Button {
            guard operation != kind else { return }
            operation = kind
            OperationFeedback.selectionChanged()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(selected ? BasirPalette.onAccent : BasirPalette.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? BasirPalette.accent : BasirPalette.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Color.clear : BasirPalette.stroke, lineWidth: 1)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Sources

    private var sourceGrid: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: BasirSpacing.m), GridItem(.flexible(), spacing: BasirSpacing.m)]
        return LazyVGrid(columns: columns, spacing: BasirSpacing.m) {
            SourceTile(title: l10n.t("ملف", "File"),
                       detail: l10n.t("من تطبيق الملفات", "From the Files app"),
                       systemImage: "folder.fill") { showFiles = true }
            SourceTile(title: l10n.t("مسح ضوئي", "Scan"),
                       detail: l10n.t("مستند متعدد الصفحات", "Multi-page document"),
                       systemImage: "doc.viewfinder.fill") { openScanner() }
            SourceTile(title: l10n.t("كاميرا", "Camera"),
                       detail: l10n.t("التقاط صورة", "Take a photo"),
                       systemImage: "camera.fill") { openCamera() }
            SourceTile(title: l10n.t("لصق", "Paste"),
                       detail: l10n.t("صورة من الحافظة", "Image from clipboard"),
                       systemImage: "doc.on.clipboard.fill") { pasteImages() }
            SourceTile(title: l10n.t("الصور", "Photos"),
                       detail: l10n.t("من مكتبة الصور", "From your library"),
                       systemImage: "photo.on.rectangle.angled") { showPhotos = true }
        }
    }

    private var addMoreMenu: some View {
        Menu {
            Button { showFiles = true } label: { Label(l10n.t("ملف", "File"), systemImage: "folder") }
            Button { openScanner() } label: { Label(l10n.t("مسح ضوئي", "Scan"), systemImage: "doc.viewfinder") }
            Button { openCamera() } label: { Label(l10n.t("كاميرا", "Camera"), systemImage: "camera") }
            Button { pasteImages() } label: { Label(l10n.t("لصق", "Paste"), systemImage: "doc.on.clipboard") }
            Button { showPhotos = true } label: {
                Label(l10n.t("الصور", "Photos"), systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            Label(l10n.t("إضافة المزيد", "Add more"), systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(BasirPalette.accent)
    }

    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
        else { pickerError = l10n.t("الكاميرا غير متاحة على هذا الجهاز.", "The camera is not available on this device.") }
    }

    private func openScanner() {
        if VNDocumentCameraViewController.isSupported { showScanner = true }
        else { pickerError = l10n.t("ماسح المستندات غير متاح على هذا الجهاز.", "Document scanning is not available on this device.") }
    }

    // MARK: - Selected files and options

    private var selectedFilesSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            AdaptiveStack {
                GlassSectionTitle(title: l10n.t("الملفات المختارة: \(pendingURLs.count)",
                                                "Selected files: \(pendingURLs.count)"),
                                  systemImage: "checkmark.circle.fill")
                    .accessibilityFocused($focusSelectedFiles)
                Spacer(minLength: 0)
                addMoreMenu
            }
            ForEach(pendingURLs, id: \.standardizedFileURL) { url in
                VStack(alignment: .leading, spacing: BasirSpacing.s) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let value = metadata[url.standardizedFileURL.path] {
                        Text(metadataText(value))
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView().tint(BasirPalette.cyan).accessibilityLabel(l10n.t("جارٍ فحص الملف", "Inspecting file"))
                    }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("معاينة", "Preview"), systemImage: "eye") {
                            previewItem = PreviewItem(url: url)
                        }
                        CardActionButton(title: l10n.t("إزالة", "Remove"), systemImage: "trash") { remove(url) }
                    }
                }
                .padding(BasirSpacing.m)
                .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
            }
        }
        .glassSurface(accent: BasirPalette.success)
    }

    private var taskSummaryCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("خيارات المهمة", "Task options"), systemImage: "slider.horizontal.3")
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button { viewModel.isSettingsPresented = true } label: {
                Label(l10n.t("تغيير الخيارات", "Change options"), systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .tint(BasirPalette.accent)
        }
        .glassSurface()
    }

    private var summaryText: String {
        let yes = l10n.t("نعم", "on"), no = l10n.t("لا", "off")
        return l10n.t(
            "المحتوى: \(settings.outputMode.title(l10n)) • الصور: \(settings.embedVisuals ? yes : no) • المعادلات: \(settings.includeMath ? yes : no) • النموذج: \(settings.preferredModel.title(l10n))",
            "Content: \(settings.outputMode.title(l10n)) • images: \(settings.embedVisuals ? yes : no) • math: \(settings.includeMath ? yes : no) • model: \(settings.preferredModel.title(l10n))"
        )
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("لغة الترجمة", "Translation language"), systemImage: "character.bubble")
            Picker(l10n.t("اختر لغة الترجمة", "Choose translation language"),
                   selection: Binding(get: { settings.targetLanguageCode }, set: {
                    settings.targetLanguageCode = $0; settings.save()
                   })) {
                ForEach(SupportedLanguage.all) { Text($0.name(interface: l10n.language)).tag($0.code) }
            }
            .pickerStyle(.menu).tint(BasirPalette.cyan)
            .padding(BasirSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .glassSurface()
    }

    private var resultNameCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            GlassSectionTitle(title: l10n.t("اسم النتيجة (اختياري)", "Result name (optional)"), systemImage: "pencil")
            TextField(l10n.t("يُستخدم اسم الملف الأصلي إذا تركته فارغًا", "The original name is used if left empty"),
                      text: $customOutputName)
                .textInputAutocapitalization(.sentences)
                .padding(BasirSpacing.m)
                .background(BasirPalette.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .glassSurface()
    }

    // MARK: - Latest result

    private func lastResultCard(_ item: OutputRecord) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Label(item.displayName, systemImage: "doc.richtext.fill")
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.createdAt.formatted(.relative(presentation: .named)))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            if let quality = item.quality {
                QualityBadge(report: quality)
            }
            AdaptiveStack {
                CardActionButton(title: l10n.t("معاينة", "Preview"), systemImage: "eye.fill", prominent: true) {
                    previewItem = PreviewItem(url: item.url)
                }
                CardActionButton(title: l10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up") {
                    shareItem = item
                }
            }
        }
        .glassSurface()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Intake

    private func handleSelected(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pickerError = nil
        let valid = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard valid.count == urls.count else {
            pickerError = isTranslation
                ? l10n.t("أحد العناصر المختارة لا يمكن ترجمته. التسجيلات الصوتية تُحوَّل فقط.",
                         "One selected item cannot be translated. Audio recordings can only be converted.")
                : l10n.t("أحد العناصر المختارة لا يمكن تحويله. ملفات Word تُترجم فقط.",
                         "One selected item cannot be converted. Word files can only be translated.")
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
                                     argument: l10n.t("تمت إضافة \(normalized.count) من العناصر. اختر ابدأ عند الجاهزية.",
                                                      "Added \(normalized.count) item(s). Choose Start when ready."))
                focusSelectedFiles = true
            } catch { pickerError = error.localizedDescription }
        }
    }

    private func dropFilesUnsupportedByOperation() {
        let unsupported = pendingURLs.filter { !supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !unsupported.isEmpty else { return }
        unsupported.forEach(remove)
        pickerError = l10n.t("أُزيل \(unsupported.count) من العناصر لأنه لا يناسب هذه المهمة.",
                             "Removed \(unsupported.count) item(s) that do not fit this task.")
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
        if let batch = viewModel.routedExternalBatch {
            viewModel.consumeRoutedExternalBatch(id: batch.id)
            operation = batch.operation
            handleSelected(batch.urls)
        } else if let document = viewModel.routedExternalDocument {
            viewModel.consumeRoutedExternalDocument(id: document.id)
            operation = document.operation
            handleSelected([document.url])
        }
    }

    private func handleIntentIfNeeded() {
        guard let action = intents.pendingAction else { return }
        switch action {
        case .chooseFile(let requested):
            intents.pendingAction = nil
            operation = requested
            showFiles = true
        case .openLatestResult:
            intents.pendingAction = nil
            library.refresh()
            if let latest = library.items.first {
                previewItem = PreviewItem(url: latest.url)
            } else {
                pickerError = l10n.t("لا توجد نتيجة محفوظة بعد.", "There is no saved result yet.")
            }
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
        var parts = [value.humanReadableSize]
        if let count = value.itemCount { parts.append(l10n.t("\(count) صفحة أو صورة", "\(count) page(s) or image(s)")) }
        if let width = value.pixelWidth, let height = value.pixelHeight { parts.append("\(width)×\(height)") }
        return parts.joined(separator: " • ")
    }

    private var privacyMessage: String {
        let networkNotice = network.snapshot.isExpensive
            ? l10n.t(" أنت تستخدم بيانات الهاتف.", " You are using cellular data.") : ""
        return l10n.t(
            "سيُرسل محتوى \(pendingURLs.count) من العناصر إلى خادم بصير لمعالجته، ثم تُنزّل النتيجة إلى جهازك.\(networkNotice)",
            "Content from \(pendingURLs.count) item(s) will be sent to the Basir server, then the result will be downloaded to your device.\(networkNotice)"
        )
    }

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }
}

/// A large, high-contrast source button used on the start screen.
struct SourceTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(BasirPalette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BasirPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(BasirSpacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BasirPalette.stroke, lineWidth: 1)
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
