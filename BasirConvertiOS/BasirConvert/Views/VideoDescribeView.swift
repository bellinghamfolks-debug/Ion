import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Video description: a video from the album or a YouTube link, up to an
/// hour, described for listening — what it is, its chapters with their
/// times, the scenes, the text on screen and who says what — then asked
/// questions.
struct VideoDescribeView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = VideoCenter.shared.runner
    @State private var link = ""
    @State private var showAlbum = false
    @State private var importing = false
    @State private var openEntry: VideoLibrary.Entry?
    @State private var entries: [VideoLibrary.Entry] = []
    @State private var linkError: String?
    /// A YouTube link shared into Basir from another app.
    var initialLink: String? = nil
    /// Describe `initialLink` at once: the person shared it to have it described.
    var startAtOnce = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    switch runner.phase {
                    case .preparing, .uploading, .working:
                        progressCard
                    case .finished(let id):
                        if let entry = VideoLibrary.entries().first(where: { $0.id == id }) {
                            finishedCard(entry)
                        }
                        choices
                    case .failed(let message):
                        InlineMessage(text: message, isError: true)
                        choices
                    case .idle:
                        choices
                    }
                    if !entries.isEmpty { library }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(l10n.t("وصف الفيديو", "Video description"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
            .navigationDestination(isPresented: Binding(get: { openEntry != nil },
                                                        set: { if !$0 { openEntry = nil } })) {
                if let openEntry { VideoResultView(entry: openEntry) }
            }
        }
        .escapeToDismiss { dismiss() }
        .sheet(isPresented: $showAlbum) {
            VideoLibraryPicker { url, title in
                showAlbum = false
                importing = false
                if let url { runner.start(.file(url, title: title), configuration: settings.configuration, l10n: l10n) }
            } onLoading: {
                importing = true
            }
            .ignoresSafeArea()
        }
        .onAppear {
            VideoCenter.shared.screenVisible = true
            VideoCenter.shared.hasUnseenResult = false
            runner.resumeIfNeeded(configuration: settings.configuration, l10n: l10n)
            entries = VideoLibrary.entries()
            if let initialLink, !runner.isBusy {
                link = initialLink
                if startAtOnce { describeLink() }
            }
        }
        .onDisappear { VideoCenter.shared.screenVisible = false }
        .onChange(of: runner.phase) { phase in
            if case .finished(let id) = phase {
                entries = VideoLibrary.entries()
                openEntry = entries.first { $0.id == id }
            }
        }
    }

    // MARK: Choosing a video

    private var choices: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.l) {
            Text(l10n.t("اختر فيديو من ألبومك أو الصق رابط YouTube، مدته حتى ساعة. يشاهده بصير ويصفه لك: عمّ يتحدث، وفصوله بأوقاتها، وما يظهر في كل مشهد، والنصوص على الشاشة، ومن يتكلم. ثم اسأله ما تريد عن الفيديو.",
                        "Choose a video from your album or paste a YouTube link, up to an hour long. Basir watches it and describes it for you: what it's about, its chapters with their times, what appears in each scene, the text on screen, and who speaks. Then ask it anything about the video."))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: l10n.t("اختر فيديو من الألبوم", "Choose a video from the album"),
                                systemImage: "film.stack") { showAlbum = true }
            if importing {
                ProgressView(l10n.t("جارٍ إحضار الفيديو من الألبوم…", "Getting the video from the album…"))
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                Text(l10n.t("أو رابط YouTube", "Or a YouTube link"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TextField(l10n.t("الصق رابط الفيديو هنا", "Paste the video link here"), text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.go)
                    .onSubmit { describeLink() }
                AdaptiveStack {
                    // The system paste button reads the clipboard without asking each time.
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first }
                    }
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    CardActionButton(title: l10n.t("صِف الفيديو", "Describe the video"), systemImage: "play.rectangle",
                                     prominent: true) { describeLink() }
                }
                if let linkError { InlineMessage(text: linkError, isError: true) }
                Text(l10n.t("يعمل مع فيديوهات YouTube العامة فقط.", "Works with public YouTube videos only."))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.secondaryText)
            }
            .glassSurface()
        }
    }

    private func describeLink() {
        guard let url = YouTubeLink.watchURL(from: link) else {
            linkError = l10n.t("هذا ليس رابط فيديو من YouTube. انسخ الرابط من زر «مشاركة» في YouTube ثم الصقه هنا.",
                               "This isn't a YouTube video link. Copy the link from YouTube's Share button, then paste it here.")
            UIAccessibility.post(notification: .announcement, argument: linkError ?? "")
            return
        }
        linkError = nil
        runner.start(.youtube(url), configuration: settings.configuration, l10n: l10n)
    }

    // MARK: Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            switch runner.phase {
            case .preparing(let value):
                Text(l10n.t("جارٍ تجهيز الفيديو", "Preparing the video")).font(.headline)
                ProgressView(value: value)
                Text(l10n.t("يصغّر بصير الفيديو على جهازك ليُرسل أسرع: \(Int(value * 100))٪",
                            "Basir makes the video smaller on your iPhone so it sends faster: \(Int(value * 100))%"))
                    .font(.footnote)
                Text(l10n.t("أبقِ بصير مفتوحًا حتى ينتهي الإرسال.", "Keep Basir open until sending finishes."))
                    .font(.footnote)
            case .uploading(let value):
                Text(l10n.t("جارٍ إرسال الفيديو", "Sending the video")).font(.headline)
                ProgressView(value: value)
                Text(l10n.t("\(Int(value * 100))٪. أبقِ بصير مفتوحًا حتى ينتهي الإرسال.",
                            "\(Int(value * 100))%. Keep Basir open until sending finishes."))
                    .font(.footnote)
            case .working(let detail, let done, let total):
                Text(detail).font(.headline)
                if total > 0 { ProgressView(value: Double(done), total: Double(total)) } else { ProgressView() }
                Text(l10n.t("يمكنك الانتقال إلى تطبيق آخر، وسيصلك إشعار عند الانتهاء.",
                            "You can switch to another app; you'll be notified when it's done."))
                    .font(.footnote)
            default:
                EmptyView()
            }
            CardActionButton(title: l10n.t("إيقاف", "Stop"), systemImage: "stop.circle") { runner.cancel() }
        }
        .accessibilityElement(children: .contain)
        .glassSurface()
    }

    private func finishedCard(_ entry: VideoLibrary.Entry) -> some View {
        CardActionButton(title: l10n.t("افتح وصف «\(entry.title)»", "Open the description of “\(entry.title)”"),
                         systemImage: "text.below.photo", prominent: true) { openEntry = entry }
    }

    // MARK: Earlier descriptions

    private var library: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("فيديوهات وصفها بصير", "Videos Basir described"))
            ForEach(entries) { entry in
                Button { openEntry = entry } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(.headline)
                        Text(l10n.t("المدة \(VideoDescription.clock(entry.durationSeconds))",
                                    "Length \(VideoDescription.clock(entry.durationSeconds))"))
                            .font(.footnote)
                            .foregroundStyle(BasirPalette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(BasirSpacing.m)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityAction(named: l10n.t("حذف", "Delete")) {
                    VideoLibrary.remove(entry.id)
                    entries = VideoLibrary.entries()
                }
            }
        }
    }
}

/// One description: listen to it all, move by chapter, and ask questions.
struct VideoResultView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    let entry: VideoLibrary.Entry
    @State private var video: VideoDescription?
    @State private var question = ""
    @State private var answers: [(question: String, answer: String)] = []
    @State private var asking = false
    @State private var askError: String?
    @State private var reading = false
    @State private var watching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BasirSpacing.l) {
                if let video {
                    header(video)
                    ask(video)
                    if !video.chapters.isEmpty { chapters(video) } else { scenes(video.scenes) }
                    if !video.onScreenText.isEmpty { screenText(video) }
                    if !video.speech.isEmpty { speech(video) }
                } else {
                    InlineMessage(text: l10n.t("تعذّر فتح هذا الوصف.", "This description could not be opened."), isError: true)
                }
            }
            .appScreenContent()
        }
        .background(BasirPalette.background.ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { video = VideoLibrary.description(for: entry.id) }
        .fullScreenCover(isPresented: $watching) {
            if let video {
                VideoWatchView(video: video, localURL: localVideo, youtubePage: youtubePage, arabic: l10n.isArabic)
                    .environmentObject(l10n)
            }
        }
        .fullScreenCover(isPresented: $reading) {
            if let video {
                DocumentReaderView(title: entry.title, blocks: VideoReaderBlocks.blocks(video, arabic: l10n.isArabic))
                    .environmentObject(l10n)
                    .environmentObject(settings)
            }
        }
    }

    private var localVideo: URL? {
        guard entry.hasLocalVideo == true, let url = VideoLibrary.mediaURL(for: entry.id),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// YouTube's player, served from Basir's own address (YouTube asks embedding pages to identify themselves).
    private var youtubePage: URL? {
        guard let link = entry.youtubeURL, let id = URLComponents(string: link)?.queryItems?.first(where: { $0.name == "v" })?.value,
              let base = settings.configuration.secureBaseURL else { return nil }
        return base.appendingPathComponent("embed/youtube/\(id)")
    }

    private var canWatch: Bool { localVideo != nil || youtubePage != nil }

    private func header(_ video: VideoDescription) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            if !video.oneLine.isEmpty {
                Text(video.oneLine).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Text([l10n.t("المدة \(VideoDescription.clock(video.durationSeconds))", "Length \(VideoDescription.clock(video.durationSeconds))"),
                  video.kind, video.setting].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
            if !video.summary.isEmpty {
                Text(video.summary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if video.isPartial {
                InlineMessage(text: l10n.t("لم يتمكن بصير من وصف جزء من الفيديو، والباقي موصوف أدناه.",
                                           "Basir couldn't describe part of the video; the rest is described below."),
                              isError: false)
            }
            if canWatch {
                PrimaryActionButton(title: l10n.t("شاهد مع الوصف", "Watch with description"),
                                    systemImage: "play.rectangle.fill") { watching = true }
            }
            CardActionButton(title: l10n.t("اسمع الوصف كاملًا", "Hear the whole description"),
                             systemImage: "speaker.wave.2.fill", prominent: !canWatch) { reading = true }
        }
        .glassSurface()
    }

    private func ask(_ video: VideoDescription) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("اسأل عن الفيديو", "Ask about the video"))
            TextField(l10n.t("مثال: ماذا كان مكتوبًا على اللوحة؟", "For example: what was written on the sign?"),
                      text: $question, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            CardActionButton(title: l10n.t("اسأل", "Ask"), systemImage: "questionmark.bubble", prominent: true) {
                send(video)
            }
            .disabled(asking || question.trimmingCharacters(in: .whitespaces).count < 2)
            if asking {
                ProgressView(l10n.t("بصير يبحث عن الإجابة…", "Basir is looking for the answer…")).frame(maxWidth: .infinity)
            }
            if let askError { InlineMessage(text: askError, isError: true) }
            ForEach(Array(answers.enumerated().reversed()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.question).font(.subheadline.weight(.semibold)).foregroundStyle(BasirPalette.secondaryText)
                    Text(item.answer).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .glassSurface()
    }

    private func send(_ video: VideoDescription) {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard asked.count >= 2, !asking else { return }
        asking = true
        askError = nil
        Task {
            do {
                let answer = try await ProxyClient(configuration: settings.configuration).askVideo(
                    question: asked, language: l10n.isArabic ? "ar" : "en", description: video,
                    youtubeURL: entry.youtubeURL, jobID: entry.serverJobID)
                answers.append((asked, answer.answer))
                question = ""
                UIAccessibility.post(notification: .announcement, argument: answer.answer)
            } catch {
                askError = DocumentAssistant.message(for: error, l10n: l10n)
            }
            asking = false
        }
    }

    private func chapters(_ video: VideoDescription) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            SectionHeading(title: l10n.t("الفصول", "Chapters"))
            ForEach(video.chapters) { chapter in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: BasirSpacing.s) {
                        if !chapter.description.isEmpty { Text(chapter.description).fixedSize(horizontal: false, vertical: true) }
                        ForEach(video.scenes(in: chapter)) { sceneRow($0) }
                    }
                    .padding(.top, BasirSpacing.s)
                } label: {
                    Text("\(VideoDescription.clock(chapter.start))  \(chapter.title)")
                        .font(.headline)
                        .accessibilityLabel("\(chapter.title)، \(VideoDescription.spokenTime(chapter.start, arabic: l10n.isArabic))")
                }
                .padding(BasirSpacing.m)
                .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func scenes(_ scenes: [VideoDescription.Scene]) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("المشاهد", "Scenes"))
            ForEach(scenes) { sceneRow($0) }
        }
    }

    private func sceneRow(_ scene: VideoDescription.Scene) -> some View {
        Text("\(VideoDescription.clock(scene.start))  \(scene.description)")
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(VideoDescription.spokenTime(scene.start, arabic: l10n.isArabic)): \(scene.description)")
    }

    private func screenText(_ video: VideoDescription) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("النصوص على الشاشة", "Text on screen"))
            ForEach(video.onScreenText) { item in
                Text("\(VideoDescription.clock(item.time))  «\(item.text)»")
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel("\(VideoDescription.spokenTime(item.time, arabic: l10n.isArabic)): \(item.text)")
            }
        }
    }

    private func speech(_ video: VideoDescription) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            SectionHeading(title: l10n.t("الكلام", "Speech"))
            ForEach(video.speech) { line in
                let who = line.speaker.isEmpty ? "" : "\(line.speaker): "
                Text("\(VideoDescription.clock(line.time))  \(who)\(line.summary)")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(VideoDescription.spokenTime(line.time, arabic: l10n.isArabic)): \(who)\(line.summary)")
            }
        }
    }
}

/// The album, videos only, one at a time. The chosen video is copied into
/// Basir (iOS deletes its own copy when the picker closes).
struct VideoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (URL?, String) -> Void
    let onLoading: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoLibraryPicker
        init(parent: VideoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onPick(nil, "")
                return
            }
            parent.onLoading()
            let parent = self.parent
            let title = provider.suggestedName ?? ""
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { file, _ in
                var copy: URL?
                if let file {
                    let target = FileManager.default.temporaryDirectory
                        .appendingPathComponent("basir-picked-\(UUID().uuidString).\(file.pathExtension.isEmpty ? "mov" : file.pathExtension)")
                    if (try? FileManager.default.copyItem(at: file, to: target)) != nil { copy = target }
                }
                DispatchQueue.main.async { parent.onPick(copy, title) }
            }
        }
    }
}
