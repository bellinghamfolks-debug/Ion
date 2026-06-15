import SwiftUI
import PhotosUI
import Combine

struct WalkingModeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var lastDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("walking_auto_reopen") private var autoReopen = false
    @StateObject private var tts = SpeechSynthesizer.shared
    @State private var ttsSubscription: AnyCancellable?
    @State private var openPickerAfterTts = false
    @State private var showCamera = false

    var body: some View {
        BasirScreen {
            BasirStatusBanner(
                text: L10n.t(
                    "التقط صورة ثابتة لما أمامك. قد يتأخر الوصف أو يخطئ، لذلك استخدم العصا أو وسيلة التنقل المعتادة ولا تعتمد عليه لعبور الطرق أو الدرج.",
                    "Capture a steady image of what is ahead. The description may be delayed or wrong, so keep using your cane or usual mobility aid and never rely on it for roads or stairs."
                ),
                tone: .warning,
                title: L10n.t("نظرة مساندة وليست وسيلة تنقل", "An assistive glance, not a mobility tool")
            )

            if isLoading {
                BasirStatusBanner(
                    text: L10n.t("جاري فحص الصورة. سيُنطق الوصف فور اكتماله.",
                                 "Checking the image. The description will be spoken when ready."),
                    tone: .info
                )
            }

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if !lastDescription.isEmpty {
                BasirResultCard(title: L10n.t("آخر وصف", "Latest description"), text: lastDescription) {
                    Button {
                        tts.speak(lastDescription, utteranceId: "walking-replay")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(BasirIconButtonStyle())
                    .accessibilityLabel(L10n.t("إعادة قراءة الوصف", "Read description again"))
                }
            }

            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 34, weight: .semibold))
                        Text(L10n.t("التقاط ووصف ما أمامي", "Capture and describe what is ahead"))
                    }
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            if CameraPicker.isAvailable {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة موجودة", "Choose an existing image"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirSecondaryButtonStyle())
                .disabled(isLoading)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.t("اختيار صورة موجودة", "Choose an existing image"),
                          systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isLoading)
            }

            Toggle(isOn: $autoReopen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("فتح الكاميرا بعد انتهاء الوصف", "Open the camera after each description"))
                        .font(.body.weight(.medium))
                    Text(L10n.t("مفيد لالتقاط صورة جديدة دون العودة إلى الزر في كل مرة.",
                                 "Useful for taking another image without returning to the button each time."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .basirCardSurface()
        }
        .navigationTitle(L10n.t("نظرة سريعة أمامك", "Quick look ahead"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { Task { await describe(rawData: data) } }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            ttsSubscription = tts.didFinish.sink { id in
                guard id == "walking" else { return }
                if autoReopen && openPickerAfterTts && CameraPicker.isAvailable {
                    openPickerAfterTts = false
                    showCamera = true
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await describe(rawData: data)
                }
            }
        }
    }

    private func describe(rawData data: Data) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        ProcessingFeedback.start()
        defer { isLoading = false }

        do {
            guard let compressed = await Task.detached(priority: .userInitiated, operation: {
                ImagePreprocessor.jpeg(from: data)
            }).value else {
                throw GeminiError.decode("image could not be prepared safely")
            }
            lastDescription = try await AiProviderFactory.current().ask(
                task: .walkingSnapshot,
                input: "",
                instruction: GeminiPrompts.walkingSnapshotInstruction,
                language: BasirSettings.shared.language,
                imageData: compressed,
                mimeType: "image/jpeg"
            )
            ProcessingFeedback.done()
            openPickerAfterTts = autoReopen
            tts.speak(lastDescription, utteranceId: "walking")
            ArchiveStore.shared.appendLog(type: "walking", content: lastDescription)
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            ProcessingFeedback.failed()
        }
    }
}
