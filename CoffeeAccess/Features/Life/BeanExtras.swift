import SwiftUI
import Vision

/// Three tasting rounds that move the grind, temperature and strength.
struct CalibrationView: View {
    @Environment(AppModel.self) var model
    let beanID: UUID
    @State var round = 1
    @State var taste: Calibration.Taste = .balanced
    @State var body_: Calibration.Body = .right
    @State var advice: Calibration.Advice?
    @State var finished = false

    private var bean: BeanProfile? { model.data.beanProfiles.first { $0.id == beanID } }

    var body: some View {
        Form {
            if let bean {
                Section {
                    Text(L("calibration.intro"))
                    LabeledContent(L("beans.grind"), value: L("beans.grind.value", bean.recommendedGrind))
                    LabeledContent(L("param.temperature"), value: bean.recommendedTemperature.title)
                } header: {
                    Text(L("calibration.round", min(round, 3), 3))
                }
                if finished {
                    Section {
                        Text(L("calibration.done", bean.recommendedGrind)).font(.headline)
                    }
                } else {
                    Section(L("calibration.step1")) {
                        Button(L("calibration.brewTest")) {
                            Task { await model.brew(model.data.recipe(for: .espresso)) }
                        }
                    }
                    Section(L("calibration.step2")) {
                        Picker(L("calibration.taste"), selection: $taste) {
                            ForEach(Calibration.Taste.allCases) { Text($0.title).tag($0) }
                        }
                        Picker(L("calibration.body"), selection: $body_) {
                            ForEach(Calibration.Body.allCases) { Text($0.title).tag($0) }
                        }
                        Button(L("calibration.advise")) {
                            let result = Calibration.advice(taste: taste, body: body_, round: round)
                            advice = result
                            Announcer.shared.announce(Calibration.sentence(result, bean: bean))
                        }
                    }
                    if let advice {
                        Section(L("calibration.step3")) {
                            Text(Calibration.sentence(advice, bean: bean))
                            Button(advice.isBalanced ? L("calibration.finish") : L("calibration.apply")) { apply(advice, to: bean) }
                                .bold()
                        }
                    }
                }
            }
        }
        .tint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("calibration.title"))
    }

    private func apply(_ advice: Calibration.Advice, to bean: BeanProfile) {
        let updated = Calibration.apply(advice, to: bean)
        model.updateData { _ = $0.saveBean(updated) }
        self.advice = nil
        if advice.isBalanced || round >= 3 {
            finished = true
            Announcer.shared.success()
            Announcer.shared.announce(L("calibration.done", updated.recommendedGrind))
        } else {
            round += 1
            taste = .balanced
            body_ = .right
            Announcer.shared.announce(L("calibration.next", round, updated.recommendedGrind))
        }
    }
}

/// How much of the bag is left, on the bean card.
struct BeanStockRow: View {
    @Environment(AppModel.self) var model
    let bean: BeanProfile

    var body: some View {
        if let stock = BeanStock.estimate(for: bean, profiles: model.data.profiles) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("stock.title"), systemImage: "scalemass")
                        .font(.headline)
                    Spacer()
                    Text(L("stock.grams", stock.remainingGrams))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(stock.isLow ? Theme.danger : Theme.accent)
                }
                ProgressView(value: stock.fractionLeft).tint(stock.isLow ? Theme.danger : Theme.accent).accessibilityHidden(true)
                Text(stock.isLow ? L("stock.low", stock.cupsLeft) : L("stock.cups", stock.cupsLeft))
                    .font(.footnote)
                    .foregroundStyle(stock.isLow ? Theme.danger : Theme.textSecondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceRaised))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("stock.title"))
            .accessibilityValue(L("stock.spoken", stock.remainingGrams, stock.cupsLeft))
        } else {
            Text(L("stock.unknown")).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Origins and roasts explained, with the drinks they suit.
struct BeanLibraryView: View {
    var body: some View {
        List {
            Section(L("library.roasts")) {
                ForEach(BeanProfile.Roast.allCases, id: \.self) { roast in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(roast.title).font(.headline)
                        Text(L("library.roast.\(roast.rawValue)")).font(.body).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section(L("library.origins")) {
                ForEach(BeanOrigin.allCases) { origin in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(origin.title).font(.headline)
                        Text(origin.notes).font(.body).foregroundStyle(Theme.textSecondary)
                        Text(L("library.suits", origin.suitedDrinks.map(\.name).joined(separator: L("list.separator"))))
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("library.title"))
    }
}

/// Takes a photo of the bag and reads it on the phone.
struct BagScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onRead: (BagReader.Reading) -> Void
    @State var picking = true
    @State var status = L("bagscan.reading")

    var body: some View {
        VStack(spacing: 16) {
            Text(status).font(.headline).multilineTextAlignment(.center).padding()
            Button(L("action.cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .sheet(isPresented: $picking) {
            ImagePicker { image in
                picking = false
                guard let image else { dismiss(); return }
                Task {
                    let lines = await TextReader.lines(in: image)
                    let reading = BagReader.read(lines)
                    onRead(reading)
                    Announcer.shared.announce(reading.name.map { L("bagscan.found", $0) } ?? L("bagscan.nothing"))
                    dismiss()
                }
            }
            .ignoresSafeArea()
        }
    }
}

enum TextReader {
    /// Recognised lines, top to bottom, in Arabic and English where available.
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                continuation.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

/// The camera (or the photo library where there is no camera).
struct ImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick((info[.originalImage] as? UIImage)?.normalizedOrientation())
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}

extension UIImage {
    /// Redraws the photo upright so text recognition sees it as shown.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
