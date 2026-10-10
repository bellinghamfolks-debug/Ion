import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Turns photos, camera captures and image files into one PDF on the
/// iPhone, in the order the person chooses, then hands it straight to
/// conversion or translation, or saves and shares it.
struct ImagesToPDFView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    struct PageImage: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }

    @State private var images: [PageImage] = []
    @State private var fileName = ""
    @State private var pageSize: ImagePDFBuilder.PageSize = .fit
    @State private var quality: ImagePDFBuilder.Quality = .high
    @State private var showCapture = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var importing: (done: Int, total: Int)?
    @State private var building: (done: Int, total: Int)?
    @State private var buildTask: Task<Void, Never>?
    @State private var outcome: ImagePDFBuilder.Outcome?
    @State private var message: String?
    @State private var preview: StablePreviewItem?
    @State private var handedOff = false
    @AccessibilityFocusState private var resultFocused: Bool

    private var limit: Int { ImagePDFBuilder.maximumImages }
    private var isBusy: Bool { importing != nil || building != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Text(l10n.t("اجمع الصور في ملف PDF واحد على جهازك، بالترتيب الذي تختاره، ثم حوّله إلى Word أو ترجمه أو احفظه. يصل الملف إلى \(limit) صورة.",
                                "Combine photos into one PDF on your device, in the order you choose, then convert it to Word, translate it, or save it. A file can hold up to \(limit) images."))
                        .fixedSize(horizontal: false, vertical: true)
                    if let outcome {
                        resultCard(outcome)
                    } else {
                        addButtons
                        if !images.isEmpty {
                            pagesSection
                            optionsSection
                            createSection
                        }
                    }
                    if let importing {
                        ProgressView(value: Double(importing.done), total: Double(max(importing.total, 1))) {
                            Text(l10n.t("جارٍ إضافة الصور: \(importing.done) من \(importing.total)",
                                        "Adding images: \(importing.done) of \(importing.total)"))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let message { InlineMessage(text: message, isError: true) }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("صور إلى PDF", "Images to PDF"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { close() } }
            }
        }
        .escapeToDismiss { close() }
        .onAppear { if fileName.isEmpty { fileName = defaultName() } }
        .fullScreenCover(isPresented: $showCapture) {
            GuidedCaptureView { pages in
                showCapture = false
                add(pages)
            } onCancel: { showCapture = false }
            .environmentObject(l10n)
        }
        .fullScreenCover(isPresented: $showPhotos) {
            PhotoLibraryPicker { urls in
                showPhotos = false
                importing = nil
                add(urls)
            } onError: { error in
                showPhotos = false
                importing = nil
                message = AppViewModel.localized(error, l10n: l10n)
            } onCancel: {
                showPhotos = false
            } onProgress: { done, total in
                importing = (done, total)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFiles) {
            BasirDocumentPicker(contentTypes: [.image], allowsMultipleSelection: true) { urls in
                showFiles = false
                addFiles(urls)
            } onCancel: { showFiles = false }
            .ignoresSafeArea()
        }
        .sheet(item: $preview) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
    }

    // MARK: - Adding images

    private var addButtons: some View {
        VStack(spacing: BasirSpacing.m) {
            PrimaryActionButton(title: l10n.t("تصوير الصفحات", "Photograph pages"), systemImage: "viewfinder") {
                showCapture = true
            }
            SecondaryActionButton(title: l10n.t("من مكتبة الصور", "From the photo library"), systemImage: "photo.on.rectangle") {
                showPhotos = true
            }
            SecondaryActionButton(title: l10n.t("من الملفات", "From Files"), systemImage: "folder") {
                showFiles = true
            }
            SecondaryActionButton(title: l10n.t("لصق صورة", "Paste an image"), systemImage: "doc.on.clipboard") {
                pasteImages()
            }
        }
        .disabled(isBusy || images.count >= limit)
    }

    private func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        message = nil
        let room = limit - images.count
        let accepted = Array(urls.prefix(max(room, 0)))
        urls.dropFirst(accepted.count).forEach(discard)
        images.append(contentsOf: accepted.map { PageImage(url: $0) })
        outcome = nil
        if accepted.count < urls.count {
            message = l10n.t("أُضيفت \(accepted.count) صورة فقط، لأن الحد الأقصى \(limit) صورة في الملف.",
                             "Only \(accepted.count) images were added, because a file can hold up to \(limit).")
        }
        announce(l10n.t("أُضيفت \(accepted.count) صورة. المجموع \(images.count).",
                        "Added \(accepted.count) images. Total \(images.count)."))
    }

    /// Files from the Files app become app-owned copies before use.
    private func addFiles(_ urls: [URL]) {
        importing = (0, urls.count)
        Task {
            var staged: [URL] = []
            for (index, url) in urls.enumerated() {
                if let copy = try? await Task.detached(priority: .userInitiated, operation: {
                    try FileAccess.stageExternalSource(url).source
                }).value {
                    staged.append(copy)
                }
                importing = (index + 1, urls.count)
            }
            importing = nil
            if staged.count < urls.count {
                message = l10n.t("تعذرت إضافة \(urls.count - staged.count) من الملفات.",
                                 "\(urls.count - staged.count) files could not be added.")
            }
            add(staged)
        }
    }

    private func pasteImages() {
        do { add(try MediaImport.pasteboardImages()) }
        catch {
            message = l10n.t("لا توجد صورة في الحافظة. انسخ صورة ثم أعد المحاولة.",
                             "There is no image on the clipboard. Copy an image, then try again.")
        }
    }

    // MARK: - Pages

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            HStack {
                SectionHeading(title: l10n.t("الصفحات: \(images.count) من \(limit)", "Pages: \(images.count) of \(limit)"))
                Spacer(minLength: 0)
                Menu {
                    Button {
                        images.reverse()
                        announce(l10n.t("عُكس ترتيب الصفحات.", "Page order reversed."))
                    } label: { Label(l10n.t("عكس الترتيب", "Reverse order"), systemImage: "arrow.up.arrow.down") }
                    Button(role: .destructive) {
                        images.forEach { discard($0.url) }
                        images.removeAll()
                        announce(l10n.t("حُذفت كل الصور.", "All images removed."))
                    } label: { Label(l10n.t("حذف كل الصور", "Remove all images"), systemImage: "trash") }
                } label: {
                    Label(l10n.t("خيارات الصفحات", "Page options"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(l10n.t("خيارات الصفحات", "Page options"))
            }
            Text(l10n.t("مع VoiceOver، اسحب لأعلى أو لأسفل على الصفحة لنقلها أو حذفها.",
                        "With VoiceOver, swipe up or down on a page to move or remove it."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LazyVStack(spacing: BasirSpacing.s) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    pageRow(image, index: index)
                }
            }
        }
    }

    private func pageRow(_ image: PageImage, index: Int) -> some View {
        HStack(spacing: BasirSpacing.m) {
            ImageThumbnail(url: image.url)
                .frame(width: 56, height: 72)
                .accessibilityHidden(true)
            Text(l10n.t("الصفحة \(index + 1)", "Page \(index + 1)"))
                .font(.body.weight(.semibold))
            Spacer(minLength: 0)
            Menu {
                Button { move(index, by: -1) } label: { Label(l10n.t("نقل للأعلى", "Move up"), systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button { move(index, by: 1) } label: { Label(l10n.t("نقل للأسفل", "Move down"), systemImage: "arrow.down") }
                    .disabled(index == images.count - 1)
                Button { move(index, to: 0) } label: { Label(l10n.t("نقل إلى البداية", "Move to start"), systemImage: "arrow.up.to.line") }
                    .disabled(index == 0)
                Button { move(index, to: images.count - 1) } label: { Label(l10n.t("نقل إلى النهاية", "Move to end"), systemImage: "arrow.down.to.line") }
                    .disabled(index == images.count - 1)
                Button(role: .destructive) { remove(index) } label: { Label(l10n.t("حذف", "Remove"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityHidden(true)
        }
        .padding(BasirSpacing.s)
        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t("الصفحة \(index + 1) من \(images.count)", "Page \(index + 1) of \(images.count)"))
        .accessibilityAction(named: l10n.t("نقل للأعلى", "Move up")) { move(index, by: -1) }
        .accessibilityAction(named: l10n.t("نقل للأسفل", "Move down")) { move(index, by: 1) }
        .accessibilityAction(named: l10n.t("نقل إلى البداية", "Move to start")) { move(index, to: 0) }
        .accessibilityAction(named: l10n.t("نقل إلى النهاية", "Move to end")) { move(index, to: images.count - 1) }
        .accessibilityAction(named: l10n.t("معاينة", "Preview")) { preview = StablePreviewItem(url: image.url) }
        .accessibilityAction(named: l10n.t("حذف", "Remove")) { remove(index) }
    }

    private func move(_ index: Int, by offset: Int) { move(index, to: index + offset) }

    private func move(_ index: Int, to target: Int) {
        guard images.indices.contains(index), images.indices.contains(target), index != target else { return }
        let item = images.remove(at: index)
        images.insert(item, at: target)
        announce(l10n.t("نُقلت إلى الصفحة \(target + 1) من \(images.count).",
                        "Moved to page \(target + 1) of \(images.count)."))
    }

    private func remove(_ index: Int) {
        guard images.indices.contains(index) else { return }
        discard(images.remove(at: index).url)
        announce(l10n.t("حُذفت الصفحة. بقي \(images.count).", "Page removed. \(images.count) left."))
    }

    // MARK: - Options and building

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("خيارات الملف", "File options"), systemImage: "doc.richtext")
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("اسم الملف", "File name")).font(.headline)
                TextField(l10n.t("اسم الملف", "File name"), text: $fileName)
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Picker(l10n.t("حجم الصفحة", "Page size"), selection: $pageSize) {
                Text(l10n.t("حسب الصورة", "Match each image")).tag(ImagePDFBuilder.PageSize.fit)
                Text("A4").tag(ImagePDFBuilder.PageSize.a4)
                Text("Letter").tag(ImagePDFBuilder.PageSize.letter)
            }
            Picker(l10n.t("الجودة", "Quality"), selection: $quality) {
                Text(l10n.t("عالية، للنص الصغير", "High, for small print")).tag(ImagePDFBuilder.Quality.high)
                Text(l10n.t("متوسطة", "Standard")).tag(ImagePDFBuilder.Quality.standard)
                Text(l10n.t("ملف أصغر", "Smaller file")).tag(ImagePDFBuilder.Quality.compact)
            }
            Text(l10n.t("إذا تجاوز الملف \(FileAccess.maximumSourceBytes / (1024 * 1024)) ميجابايت، يخفّض بصير الجودة تلقائيًا حتى يمكن تحويله.",
                        "If the file would exceed \(FileAccess.maximumSourceBytes / (1024 * 1024)) MB, Basir lowers the quality automatically so it can still be converted."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .tint(BasirPalette.accent)
        .glassSurface()
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            if let building {
                ProgressView(value: Double(building.done), total: Double(max(building.total, 1))) {
                    Text(l10n.t("جارٍ إنشاء PDF: الصفحة \(building.done) من \(building.total)",
                                "Creating PDF: page \(building.done) of \(building.total)"))
                }
                .accessibilityElement(children: .combine)
                SecondaryActionButton(title: l10n.t("إيقاف", "Stop"), systemImage: "stop.circle") {
                    buildTask?.cancel()
                }
            } else {
                PrimaryActionButton(title: l10n.t("إنشاء ملف PDF", "Create PDF"), systemImage: "doc.badge.plus") { build() }
                    .disabled(importing != nil)
            }
        }
    }

    private func build() {
        let urls = images.map(\.url)
        let name = fileName.isEmpty ? defaultName() : fileName
        let options = ImagePDFBuilder.Options(pageSize: pageSize, quality: quality)
        message = nil
        building = (0, urls.count)
        announce(l10n.t("جارٍ إنشاء ملف PDF من \(urls.count) صورة.", "Creating a PDF from \(urls.count) images."))
        let spoken = SpokenProgress()
        buildTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImagePDFBuilder.build(urls, name: name, options: options) { done, total in
                        Task { @MainActor in
                            building = (done, total)
                            // A spoken update every 25 pages on long files.
                            if total > 25, done - spoken.last >= 25, done < total {
                                spoken.last = done
                                UIAccessibility.post(notification: .announcement, argument: l10n.t("الصفحة \(done) من \(total)", "Page \(done) of \(total)"))
                            }
                        }
                    }
                }.value
                building = nil
                if Task.isCancelled { try? FileManager.default.removeItem(at: result.url.deletingLastPathComponent()); return }
                outcome = result
                OperationFeedback.selectionChanged()
                resultFocused = true
            } catch is CancellationError {
                building = nil
                announce(l10n.t("أُوقف إنشاء الملف.", "Creating the file was stopped."))
            } catch {
                building = nil
                message = AppViewModel.localized(error, l10n: l10n)
            }
        }
    }

    // MARK: - Result

    private func resultCard(_ outcome: ImagePDFBuilder.Outcome) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("ملف PDF جاهز", "Your PDF is ready"), systemImage: "checkmark.seal.fill")
                .accessibilityFocused($resultFocused)
            Text(summary(outcome))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: l10n.t("تحويل إلى Word", "Convert to Word"), systemImage: "doc.text") {
                handOff(outcome.url, to: .convert)
            }
            SecondaryActionButton(title: l10n.t("ترجمة الملف", "Translate the file"), systemImage: "character.bubble") {
                handOff(outcome.url, to: .translate)
            }
            ShareLink(item: outcome.url) {
                Label(l10n.t("حفظ أو مشاركة", "Save or share"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .tint(BasirPalette.accent)
            SecondaryActionButton(title: l10n.t("معاينة", "Preview"), systemImage: "eye") {
                preview = StablePreviewItem(url: outcome.url)
            }
            SecondaryActionButton(title: l10n.t("تعديل الصور", "Edit the images"), systemImage: "pencil") {
                discardFile(outcome.url)
                self.outcome = nil
            }
        }
        .glassSurface()
    }

    private func summary(_ outcome: ImagePDFBuilder.Outcome) -> String {
        let size = ByteCountFormatter.string(fromByteCount: outcome.bytes, countStyle: .file)
        var text = l10n.t("«\(outcome.url.lastPathComponent)»: \(outcome.pages) صفحة، الحجم \(size).",
                          "“\(outcome.url.lastPathComponent)”: \(outcome.pages) pages, \(size).")
        if outcome.quality < quality {
            text += " " + l10n.t("خُفّضت الجودة ليبقى الملف ضمن حد الرفع.", "The quality was lowered to keep the file within the upload limit.")
        }
        if !outcome.skipped.isEmpty {
            let pages = outcome.skipped.prefix(10).map(String.init).joined(separator: "، ")
            text += " " + l10n.t("تعذرت قراءة الصور: \(pages)، ولم تُضف.", "These images could not be read and were left out: \(pages).")
        }
        return text
    }

    /// The PDF goes to the composer; the images are no longer needed.
    private func handOff(_ url: URL, to operation: OperationKind) {
        handedOff = true
        images.forEach { discard($0.url) }
        images.removeAll()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.routeCreatedFile(url, to: operation, l10n: l10n)
        }
    }

    // MARK: - Housekeeping

    private func close() {
        buildTask?.cancel()
        images.forEach { discard($0.url) }
        if let outcome, !handedOff { discardFile(outcome.url) }
        dismiss()
    }

    /// Removes an image Basir copied into its import area (never a file
    /// elsewhere on the device).
    private func discard(_ url: URL) { viewModel.discardExternalSource(url) }
    private func discardFile(_ url: URL) { viewModel.discardExternalSource(url) }

    private func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.isArabic ? "ar" : "en")
        formatter.dateFormat = "d MMMM yyyy"
        return l10n.t("صور \(formatter.string(from: Date()))", "Images \(formatter.string(from: Date()))")
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// The last page number spoken while building.
private final class SpokenProgress { var last = 0 }

/// A small preview read at thumbnail size, off the main thread.
private struct ImageThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(BasirPalette.background)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(BasirPalette.tertiaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: url) {
            let url = url
            let thumbnail = await Task.detached(priority: .utility) {
                ImagePDFBuilder.downsample(url, maxPixel: 200).map { UIImage(cgImage: $0) }
            }.value
            image = thumbnail
        }
    }
}
