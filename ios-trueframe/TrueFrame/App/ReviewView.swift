import SwiftUI
import CoreGraphics

/// Post-capture review: an accessible quality report, one-tap non-generative
/// "Fix alignment", a text before/after, OCR, and "Save corrected copy".
struct ReviewView: View {
    let image: CGImage
    let capturedLevel: LevelReading
    let analysis: FrameAnalysis?
    @Environment(\.dismiss) private var dismiss

    @State private var corrected: CGImage?
    @State private var provenance: EditingProvenance?
    @State private var report: String = ""
    @State private var ocrText: String = ""
    @State private var status: String = ""

    private let processor = GeometricImageProcessor()
    private let library = PhotoLibraryManager()
    private let ocr = OCRManager()

    private var quality: QualityScore {
        QualityScore.from(analysis ?? FrameAnalysis(level: capturedLevel))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(decorative: corrected ?? image, scale: 1, orientation: .up)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 320)
                        .accessibilityLabel(corrected == nil ? "Captured photo" : "Corrected photo")

                    reportCard("Quality Report", quality.spokenReport)

                    Button("Fix alignment") { fixAlignment() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityHint("Rotates to level and crops the empty corners. No generative editing.")

                    if !report.isEmpty { reportCard("Before and After", report) }
                    if let p = provenance {
                        Text(AuthenticityGuard(policy: p.policy).safeStatement)
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityLabel(AuthenticityGuard(policy: p.policy).safeStatement)
                    }

                    Button("Read text") { readText() }.buttonStyle(.bordered)
                    if !ocrText.isEmpty { reportCard("Recognized Text", ocrText) }

                    Button("Save corrected copy") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(corrected == nil)
                        .accessibilityHint("Saves a new copy. Your original is never changed.")

                    if !status.isEmpty {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding()
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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

    private func fixAlignment() {
        let plan = CorrectionPlan(
            rollDegrees: capturedLevel.rollDegrees,
            cropNormalized: CropSolver.safeAspectCrop(
                imageSize: CGSize(width: image.width, height: image.height),
                degrees: capturedLevel.rollDegrees),
            horizonConfidence: analysis == nil ? 0.4 : 0.7)
        do {
            let out = try processor.correct(image, plan: plan)
            corrected = out.image
            provenance = out.provenance
            report = BeforeAfterReport(original: plan, provenance: out.provenance).spoken
            status = "Alignment fixed. \(out.provenance.generativeDisclosure)"
        } catch {
            status = "Could not correct this photo: \(error)"
        }
    }

    private func readText() {
        status = "Reading text…"
        ocr.recognize(corrected ?? image) { text, _ in
            ocrText = text.isEmpty ? "No text found." : text
            status = ""
        }
    }

    private func save() {
        guard let cg = corrected, let p = provenance else { return }
        status = "Saving…"
        library.saveCorrectedCopy(cg, provenance: p) { result in
            switch result {
            case .success: status = "Saved a corrected copy. Original preserved."
            case .failure(let e): status = "Save failed: \(e)"
            }
        }
    }
}
