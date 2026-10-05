import SwiftUI
import VisionKit

/// Reads the machine's touchscreen aloud through the camera, so menus that
/// exist only on the machine (descaling, filter, language) can be followed.
/// Text recognition runs on the device; nothing is uploaded.
struct MachineScreenReaderView: View {
    @State var lines: [String] = []
    @State var paused = false
    @State var lastSpoken: Set<String> = []

    private var supported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            if supported {
                LiveTextScanner(paused: paused) { recognized in
                    update(with: recognized)
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel(L("reader.camera"))
                .accessibilityHint(L("reader.camera.hint"))
            } else {
                ContentUnavailableView(L("reader.unsupported"), systemImage: "camera.badge.ellipsis",
                                       description: Text(L("reader.unsupported.detail")))
            }
            controls
        }
        .screenBackground()
        .navigationTitle(L("reader.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lines.isEmpty ? L("reader.empty") : L("reader.found", lines.count))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !lines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines, id: \.self) { line in
                            Text(line).font(.body).foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            HStack(spacing: 12) {
                Button(paused ? L("reader.resume") : L("reader.pause")) { paused.toggle() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("reader.readAll")) {
                    Announcer.shared.announce(lines.joined(separator: L("sentence.separator")), priority: .high)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(lines.isEmpty)
            }
            Text(L("reader.tip"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .background(Theme.surface)
    }

    /// Announces only lines that are new since the last frames, so moving
    /// the camera across the screen reads each item once.
    private func update(with recognized: [String]) {
        let cleaned = recognized
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
        lines = cleaned
        let fresh = cleaned.filter { !lastSpoken.contains($0) }
        guard !fresh.isEmpty, !paused else { return }
        lastSpoken.formUnion(fresh)
        if lastSpoken.count > 60 { lastSpoken = Set(cleaned) }
        Announcer.shared.announce(fresh.joined(separator: L("sentence.separator")))
    }
}

/// Wraps VisionKit's live text scanner.
struct LiveTextScanner: UIViewControllerRepresentable {
    let paused: Bool
    let onText: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let languages = DataScannerViewController.supportedTextRecognitionLanguages
            .filter { $0.hasPrefix("ar") || $0.hasPrefix("en") }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: languages)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onText = onText
        if paused, scanner.isScanning {
            scanner.stopScanning()
        } else if !paused, !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: ([String]) -> Void
        private var lastEmit = Date.distantPast

        init(onText: @escaping ([String]) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emit(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emit(allItems)
        }

        private func emit(_ items: [RecognizedItem]) {
            // Throttle so VoiceOver is not flooded while the camera moves.
            guard Date().timeIntervalSince(lastEmit) > 1.2 else { return }
            lastEmit = Date()
            let texts = items.compactMap { item -> (String, CGFloat)? in
                if case .text(let text) = item { return (text.transcript, text.bounds.topLeft.y) }
                return nil
            }
            onText(texts.sorted { $0.1 < $1.1 }.map(\.0))
        }
    }
}
