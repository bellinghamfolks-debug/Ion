import Foundation
import UIKit

/// Files arriving from the share sheet, Files, or Basir's own tools,
/// staged and routed to conversion or translation.
extension AppViewModel {
    func importSharedInbox() {
        Task { [weak self] in
            do {
                let urls = try await Task.detached(priority: .utility) { try SharedInbox.takeAll() }.value
                guard !urls.isEmpty, let self, let l10n = self.l10n else { return }
                self.receiveAlreadyStagedExternalURLs(urls, l10n: l10n)
            } catch {
                DiagnosticLogger.recordGlobal("IMPORT shared-inbox failed type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                self?.externalImportError = error.localizedDescription
            }
        }
    }

    func receiveExternalURL(_ url: URL, l10n: L10n) {
        receiveExternalURLs([url], l10n: l10n)
    }

    func receiveExternalURLs(_ urls: [URL], l10n: L10n) {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
            externalImportError = l10n.t(
                "هذا الرابط غير مدعوم. شارك الملف أو الصورة نفسها مع بصير.",
                "This link is not supported. Share the file or image itself with Basir."
            )
            return
        }
        let supported = urls.filter { !SupportedInput.operations(for: $0).isEmpty }
        guard supported.count == urls.count else {
            externalImportError = l10n.t(
                "بعض الملفات بصيغة غير مدعومة. اختر PDF أو Word أو PowerPoint أو صورة أو تسجيلًا صوتيًا مدعومًا.",
                "Some files use an unsupported format. Choose a PDF, Word document, presentation, supported image, or audio recording."
            )
            return
        }

        externalImportTask?.cancel()
        externalImportError = nil
        externalImportTask = Task { [weak self] in
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try supported.map { try FileAccess.stageExternalSource($0).source }
                }.value
                guard let self else { return }
                self.externalImportTask = nil
                self.receiveAlreadyStagedExternalURLs(staged, l10n: l10n)
            } catch is CancellationError {
                return
            } catch {
                DiagnosticLogger.recordGlobal("IMPORT staging failed type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                self?.externalImportTask = nil
                self?.externalImportError = Self.localized(error, l10n: l10n)
            }
        }
    }

    func receiveAlreadyStagedExternalURLs(_ urls: [URL], l10n: L10n) {
        guard !urls.isEmpty else { return }
        let operationSets = urls.map(SupportedInput.operations)
        let common = operationSets.dropFirst().reduce(operationSets[0]) { $0.intersection($1) }
        guard !common.isEmpty else {
            urls.forEach(discardExternalSource)
            externalImportError = l10n.t(
                "لا يمكن تنفيذ المهمة نفسها على جميع الملفات المحددة. اختر ملفات مناسبة للتحويل معًا أو للترجمة معًا.",
                "These files cannot be processed together. Select files that all support conversion, or files that all support translation."
            )
            return
        }
        if common.count == 1, let operation = common.first {
            route(stagedURLs: urls, to: operation, l10n: l10n)
        } else {
            externalImportBatch = ExternalImportBatch(id: UUID(), urls: urls, operations: common)
            UIAccessibility.post(
                notification: .announcement,
                argument: l10n.t(
                    "الملفات المستلمة: \(urls.count). اختر التحويل أو الترجمة.",
                    "Files received: \(urls.count). Choose conversion or translation."
                )
            )
        }
    }

    func routeExternalImport(to operation: OperationKind, l10n: L10n) {
        if let batch = externalImportBatch, batch.operations.contains(operation) {
            externalImportBatch = nil
            route(stagedURLs: batch.urls, to: operation, l10n: l10n)
            return
        }
        guard let candidate = externalImportCandidate,
              candidate.operations.contains(operation) else { return }
        externalImportCandidate = nil
        route(stagedURLs: [candidate.url], to: operation, l10n: l10n)
    }

    func cancelExternalImport() {
        externalImportTask?.cancel()
        externalImportTask = nil
        externalImportBatch?.urls.forEach(discardExternalSource)
        if let candidate = externalImportCandidate { discardExternalSource(candidate.url) }
        externalImportBatch = nil
        externalImportCandidate = nil
    }

    func consumeRoutedExternalDocument(id: UUID) {
        guard routedExternalDocument?.id == id else { return }
        routedExternalDocument = nil
    }

    func consumeRoutedExternalBatch(id: UUID) {
        guard routedExternalBatch?.id == id else { return }
        routedExternalBatch = nil
    }

    func discardExternalSource(_ url: URL) {
        FileAccess.removeExternalImportDirectory(url.deletingLastPathComponent())
    }

    func clearExternalImportError() { externalImportError = nil }

    /// A file Basir made itself (for example a PDF from images), already in
    /// the app's import area, handed to the composer for this operation.
    func routeCreatedFile(_ url: URL, to operation: OperationKind, l10n: L10n) {
        route(stagedURLs: [url], to: operation, l10n: l10n)
    }

    func route(stagedURLs: [URL], to operation: OperationKind, l10n: L10n) {
        if let first = stagedURLs.first, stagedURLs.count == 1 {
            routedExternalDocument = RoutedExternalDocument(id: UUID(), url: first, operation: operation)
            routedExternalBatch = nil
        } else {
            routedExternalBatch = RoutedExternalBatch(id: UUID(), urls: stagedURLs, operation: operation)
            routedExternalDocument = nil
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: operation == .convert
                ? l10n.t("الملفات الجاهزة للتحويل: \(stagedURLs.count).", "Files ready for conversion: \(stagedURLs.count).")
                : l10n.t("الملفات الجاهزة للترجمة: \(stagedURLs.count).", "Files ready for translation: \(stagedURLs.count).")
        )
    }
}
