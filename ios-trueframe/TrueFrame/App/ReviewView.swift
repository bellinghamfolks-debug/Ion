import SwiftUI
import CoreGraphics

struct ReviewView: View {
    let image: CGImage
    let capturedLevel: LevelReading
    let analysis: FrameAnalysis?

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var angle: Double
    @State private var step: Double = 1.0
    @State private var corrected: CGImage?
    @State private var provenance: EditingProvenance?
    @State private var report = ""
    @State private var ocrText = ""
    @State private var status = ""
    @State private var stillImageAnalyzed = false

    private let processor = GeometricImageProcessor()
    private let library = PhotoLibraryManager()
    private let ocr = OCRManager()
    private let horizonAnalyzer = VisualHorizonAnalyzer()

    init(image: CGImage, capturedLevel: LevelReading, analysis: FrameAnalysis?) {
        self.image = image
        self.capturedLevel = capturedLevel
        self.analysis = analysis

        let initialAngle: Double
        if let visual = analysis?.visualHorizonDegrees,
           (analysis?.visualHorizonConfidence ?? 0) >= 0.65 {
            initialAngle = visual
        } else {
            initialAngle = capturedLevel.rollDegrees
        }
        _angle = State(initialValue: initialAngle)
    }

    private var quality: QualityScore {
        QualityScore.from(analysis ?? FrameAnalysis(level: capturedLevel))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    imageCard
                    reportCard(settings.t("Quality Report"),
                               quality.spokenReport(languageCode: settings.effectiveCode))
                    straightenControls

                    Button {
                        applyCorrection()
                    } label: {
                        Label(settings.t("Fix alignment"), systemImage: "rotate.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint(settings.t("Rotates to level and crops the empty corners. No generative editing."))

                    if !report.isEmpty {
                        reportCard(settings.t("Before and After"), report)
                    }

                    if let provenance {
                        Text(AuthenticityGuard(policy: provenance.policy).safeStatement)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        readText()
                    } label: {
                        Label(settings.t("Read text"), systemImage: "text.viewfinder")
                    }
                    .buttonStyle(.bordered)

                    if !ocrText.isEmpty {
                        reportCard(settings.t("Recognized Text"), ocrText)
                    }

                    Button {
                        save()
                    } label: {
                        Label(settings.t("Save corrected copy"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(corrected == nil)
                    .accessibilityHint(settings.t("Saves a new copy. Your original is never changed."))

                    if !status.isEmpty {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(settings.t("Review"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.t("Done")) { dismiss() }
                }
            }
            .onAppear { analyzeStillImageIfNeeded() }
        }
    }

    private var imageCard: some View {
        Image(decorative: corrected ?? image, scale: 1, orientation: .up)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 360)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel(corrected == nil
                                ? settings.t("Captured photo")
                                : settings.t("Corrected photo"))
    }

    private var straightenControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.t("Rotation angle"))
                    .font(.headline)
                Spacer()
                Text("\(String(format: "%.1f", angle))°")
                    .font(.headline.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(settings.t("Rotation angle"))
            .accessibilityValue("\(String(format: "%.1f", angle))°")

            HStack(spacing: 16) {
                Button { angle -= step } label: {
                    Image(systemName: "minus.circle.fill").font(.largeTitle)
                }
                .accessibilityLabel(settings.t("Decrease angle"))

                Picker(settings.t("Step"), selection: $step) {
                    Text("0.5°").tag(0.5)
                    Text("1°").tag(1.0)
                    Text("5°").tag(5.0)
                }
                .pickerStyle(.segmented)

                Button { angle += step } label: {
                    Image(systemName: "plus.circle.fill").font(.largeTitle)
                }
                .accessibilityLabel(settings.t("Increase angle"))
            }

            Button(settings.t("Snap to level")) {
                if let visual = analysis?.visualHorizonDegrees,
                   (analysis?.visualHorizonConfidence ?? 0) >= 0.65 {
                    angle = visual
                } else {
                    angle = capturedLevel.rollDegrees
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reportCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }

    private func analyzeStillImageIfNeeded() {
        guard !stillImageAnalyzed else { return }
        stillImageAnalyzed = true

        // Imported photos have no CoreMotion reading. Use Vision horizon
        // detection once so the correction button starts with a meaningful
        // automatic angle instead of always defaulting to zero.
        guard analysis == nil else { return }

        let source = image
        DispatchQueue.global(qos: .userInitiated).async {
            let reading = horizonAnalyzer.analyze(source)
            guard let reading, reading.confidence >= 0.65 else { return }
            DispatchQueue.main.async {
                angle = reading.degrees
                status = settings.isArabic
                    ? "تم اكتشاف ميل بصري قدره \(String(format: "%.1f", abs(reading.degrees))) درجة."
                    : "Detected a visual tilt of \(String(format: "%.1f", abs(reading.degrees))) degrees."
            }
        }
    }

    private func applyCorrection() {
        let plan = CorrectionPlan(
            rollDegrees: angle,
            cropNormalized: CropSolver.safeAspectCrop(
                imageSize: CGSize(width: image.width, height: image.height),
                degrees: angle
            ),
            horizonConfidence: analysis?.visualHorizonConfidence ?? (analysis == nil ? 0.65 : 0.4)
        )

        do {
            let output = try processor.correct(image, plan: plan)
            corrected = output.image
            provenance = output.provenance
            report = BeforeAfterReport(original: plan,
                                       provenance: output.provenance)
                .spoken(languageCode: settings.effectiveCode)
            status = settings.isArabic
                ? "تم تطبيق التصحيح الهندسي فقط."
                : "Geometric correction applied."
        } catch {
            status = settings.t("Could not correct this photo.")
        }
    }

    private func readText() {
        status = settings.t("Reading text…")
        ocr.recognize(corrected ?? image) { text, _ in
            ocrText = text.isEmpty ? settings.t("No text found.") : text
            status = ""
        }
    }

    private func save() {
        guard let corrected, let provenance else { return }
        status = settings.t("Saving…")
        library.saveCorrectedCopy(corrected, provenance: provenance) { result in
            switch result {
            case .success:
                status = settings.t("Saved a corrected copy. Original preserved.")
            case .failure:
                status = settings.t("Save failed.")
            }
        }
    }
}
