import SwiftUI
import CoreGraphics

/// Post-capture / post-import review: an accessible quality report, an
/// accessible MANUAL straighten control, one-tap non-generative correction, a
/// text before/after, OCR, and "Save corrected copy".
struct ReviewView: View {
    let image: CGImage
    let capturedLevel: LevelReading
    let analysis: FrameAnalysis?

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var angle: Double
    @State private var step: Double = 1.0
    @State private var corrected: CGImage? = nil
    @State private var provenance: EditingProvenance? = nil
    @State private var report: String = ""
    @State private var ocrText: String = ""
    @State private var status: String = ""

    private let processor = GeometricImageProcessor()
    private let library = PhotoLibraryManager()
    private let ocr = OCRManager()

    init(image: CGImage, capturedLevel: LevelReading, analysis: FrameAnalysis?) {
        self.image = image
        self.capturedLevel = capturedLevel
        self.analysis = analysis
        _angle = State(initialValue: capturedLevel.rollDegrees)
    }

    private var quality: QualityScore {
        QualityScore.from(analysis ?? FrameAnalysis(level: capturedLevel))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(decorative: corrected ?? image, scale: 1, orientation: .up)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 300)
                        .accessibilityLabel(corrected == nil ? settings.t("Captured photo") : settings.t("Corrected photo"))

                    reportCard(settings.t("Quality Report"), quality.spokenReport)

                    straightenControls

                    Button(settings.t("Fix alignment")) { applyCorrection() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityHint(settings.t("Rotates to level and crops the empty corners. No generative editing."))

                    if !report.isEmpty { reportCard(settings.t("Before and After"), report) }
                    if let p = provenance {
                        Text(AuthenticityGuard(policy: p.policy).safeStatement)
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Button(settings.t("Read text")) { readText() }.buttonStyle(.bordered)
                    if !ocrText.isEmpty { reportCard(settings.t("Recognized Text"), ocrText) }

                    Button(settings.t("Save corrected copy")) { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(corrected == nil)
                        .accessibilityHint(settings.t("Saves a new copy. Your original is never changed."))

                    if !status.isEmpty {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding()
            }
            .navigationTitle(settings.t("Review"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(settings.t("Done")) { dismiss() } }
            }
        }
    }

    // Accessible manual rotation: stepper with a configurable step and a
    // "snap to level" that jumps to the device roll measured at capture.
    private var straightenControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(settings.t("Rotation angle")): \(String(format: "%.1f", angle))°")
                .font(.headline)
                .accessibilityLabel(settings.t("Rotation angle"))
                .accessibilityValue(String(format: "%.1f degrees", angle))
            HStack {
                Button { angle -= step } label: { Image(systemName: "minus.circle.fill").font(.title) }
                    .accessibilityLabel(settings.t("Decrease angle"))
                Spacer()
                Picker(settings.t("Step"), selection: $step) {
                    Text("0.5°").tag(0.5); Text("1°").tag(1.0); Text("5°").tag(5.0)
                }.pickerStyle(.segmented).frame(maxWidth: 220)
                Spacer()
                Button { angle += step } label: { Image(systemName: "plus.circle.fill").font(.title) }
                    .accessibilityLabel(settings.t("Increase angle"))
            }
            Button(settings.t("Snap to level")) { angle = capturedLevel.rollDegrees }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func reportCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }

    private func applyCorrection() {
        let plan = CorrectionPlan(
            rollDegrees: angle,
            cropNormalized: CropSolver.safeAspectCrop(
                imageSize: CGSize(width: image.width, height: image.height), degrees: angle),
            horizonConfidence: analysis == nil ? 0.4 : 0.7)
        do {
            let out = try processor.correct(image, plan: plan)
            corrected = out.image
            provenance = out.provenance
            report = BeforeAfterReport(original: plan, provenance: out.provenance).spoken
            status = "\(settings.t("Fix alignment")). \(out.provenance.generativeDisclosure)"
        } catch {
            status = "Could not correct this photo: \(error)"
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
        guard let cg = corrected, let p = provenance else { return }
        status = settings.t("Saving…")
        library.saveCorrectedCopy(cg, provenance: p) { result in
            switch result {
            case .success: status = settings.t("Saved a corrected copy. Original preserved.")
            case .failure(let e): status = "Save failed: \(e)"
            }
        }
    }
}
