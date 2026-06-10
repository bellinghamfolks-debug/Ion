import Foundation

actor ConversionEngine {
    typealias ProgressHandler = @Sendable (ConversionProgress) async -> Void

    private let gemini: GeminiClient
    private let store: JobStore

    init(gemini: GeminiClient = GeminiClient(), store: JobStore = .shared) {
        self.gemini = gemini
        self.store = store
    }

    func convertNew(
        sourceURL: URL,
        apiKey: String,
        options: ConversionOptions,
        progress: @escaping ProgressHandler
    ) async throws -> ConversionJobRecord {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let initialExtractor = try PDFPageExtractor(url: sourceURL)
        guard initialExtractor.pageCount > 0 else { throw ConversionEngineError.emptyDocument }
        var record = try await store.createWorkspace(
            sourceURL: sourceURL,
            pageCount: initialExtractor.pageCount,
            options: options
        )
        return try await run(record: &record, apiKey: apiKey, requestedOptions: options, progress: progress)
    }

    func resume(
        record original: ConversionJobRecord,
        apiKey: String,
        options: ConversionOptions,
        progress: @escaping ProgressHandler
    ) async throws -> ConversionJobRecord {
        var record = original
        record.errorMessage = nil
        return try await run(record: &record, apiKey: apiKey, requestedOptions: options, progress: progress)
    }

    private func run(
        record: inout ConversionJobRecord,
        apiKey: String,
        requestedOptions: ConversionOptions,
        progress: @escaping ProgressHandler
    ) async throws -> ConversionJobRecord {
        do {
            let isLegacyWorkspace = record.optionsSnapshot == nil
            let requiresAccuracyUpgrade = (record.formatVersion ?? 0) < 5
            let options = record.optionsSnapshot ?? requestedOptions
            if record.optionsSnapshot == nil {
                record.optionsSnapshot = options
                var warnings = record.warnings ?? []
                warnings.append(L10n.text("تم استئناف مهمة قديمة؛ ثُبتت الإعدادات الحالية لبقية الصفحات."))
                record.warnings = Array(Set(warnings)).sorted()
            }
            record.formatVersion = 5

            let source = try await store.verifySourceIntegrity(for: record)
            let extractor = try PDFPageExtractor(url: source)
            guard extractor.pageCount > 0 else { throw ConversionEngineError.emptyDocument }
            if record.totalPages > 0, record.totalPages != extractor.pageCount {
                throw ConversionEngineError.pageCountChanged(expected: record.totalPages, actual: extractor.pageCount)
            }

            record.totalPages = extractor.pageCount
            record.status = .preparing
            record.updatedAt = Date()
            DiagnosticsLog.shared.record("convert", "START | pages:\(extractor.pageCount) | model:\(options.model) | thinking:\(options.thinkingLevel) | concurrency:\(options.concurrency) | retry:\(options.retryCount) | completedSoFar:\(record.completedPages)")
            try await store.save(record)
            await progress(.init(
                status: .preparing,
                currentPage: record.completedPages,
                totalPages: record.totalPages,
                message: L10n.text("فحص سلامة ملف PDF والنتائج المحفوظة")
            ))

            if requiresAccuracyUpgrade {
                try await store.clearAnalyses(for: record)
                var upgradedWarnings = Set(record.warnings ?? [])
                upgradedWarnings.insert(L10n.text("أُعيد تحليل الصفحات القديمة لأن الإصدار الحالي يضيف التنسيق الغني والخلايا المدمجة والروابط والحواشي وحماية الصفحات الممسوحة."))
                record.warnings = upgradedWarnings.sorted()
                record.completedPages = 0
                record.fallbackPages = []
                record.minimumQualityScore = nil
                record.handwrittenPages = []
                try await store.save(record)
            }

            let existing = try await store.loadAnalyses(for: record)
            var analysesByPage: [Int: PageAnalysis] = [:]
            for analysis in existing {
                analysesByPage[analysis.pageNumber] = analysis
            }

            var fallbackPages = Set(record.fallbackPages ?? [])
            fallbackPages.formUnion(existing.filter { $0.source == .nativeTextFallback || $0.source == .visualPageFallback }.map(\.pageNumber))
            var warnings = Set(record.warnings ?? [])
            for analysis in existing { warnings.formUnion(analysis.warnings) }
            var handwrittenPages = Set(record.handwrittenPages ?? [])
            handwrittenPages.formUnion(existing.filter { $0.contentKind == .handwritten || $0.contentKind == .mixed }.map(\.pageNumber))
            var qualityScores = existing.filter { $0.source != .localBlankPage }.map(\.qualityScore).filter { $0 > 0 }
            if isLegacyWorkspace && !existing.isEmpty {
                warnings.insert(L10n.text("بعض الصفحات حُللت بإصدار أقدم قبل تثبيت إعدادات المهمة."))
            }

            record.completedPages = analysesByPage.count
            record.fallbackPages = fallbackPages.sorted()
            record.warnings = warnings.sorted()
            record.handwrittenPages = handwrittenPages.sorted()
            record.minimumQualityScore = qualityScores.min()
            record.status = .analyzing
            try await store.save(record)

            let pendingIndices = (0..<extractor.pageCount).filter { analysesByPage[$0 + 1] == nil }
            if !pendingIndices.isEmpty {
                await progress(.init(
                    status: .preparing,
                    currentPage: record.completedPages,
                    totalPages: record.totalPages,
                    message: L10n.text("اختبار المفتاح والنموذج بصيغة التحويل الفعلية")
                ))
                _ = try await Self.withRetry(maxRetries: min(2, options.retryCount)) {
                    try await self.gemini.validateKey(apiKey, model: options.model)
                }
                await progress(.init(
                    status: .analyzing,
                    currentPage: record.completedPages,
                    totalPages: record.totalPages,
                    message: L10n.text("نجح اختبار Gemini؛ بدء القراءة الثلاثية عالية الدقة")
                ))
            }
            let concurrency = max(1, min(3, options.concurrency))

            for batchStart in stride(from: 0, to: pendingIndices.count, by: concurrency) {
                try Task.checkCancellation()
                let upperBound = min(batchStart + concurrency, pendingIndices.count)
                let batch = Array(pendingIndices[batchStart..<upperBound])
                var payloads: [PagePayload] = []
                payloads.reserveCapacity(batch.count)

                for index in batch {
                    try Task.checkCancellation()
                    let isProbablyBlank = extractor.isProbablyBlank(at: index)
                    let nativeText = extractor.nativeText(at: index)
                    let longEdge: CGFloat = nativeText.count >= 2_000 ? 3_600 : 3_100
                    let pageImage = isProbablyBlank ? nil : try extractor.highResolutionPageImage(at: index, longEdge: longEdge)
                    let localOCR: LocalOCRReference
                    let detailTiles: [Data]
                    if isProbablyBlank {
                        localOCR = .empty
                        detailTiles = []
                    } else {
                        localOCR = extractor.localOCRReference(at: index, pageImageData: pageImage)
                        detailTiles = pageImage.map { extractor.detailTiles(from: $0) } ?? []
                    }
                    payloads.append(PagePayload(
                        index: index,
                        data: try extractor.pageData(at: index),
                        pageImage: pageImage,
                        detailTiles: detailTiles,
                        nativeText: nativeText,
                        localOCR: localOCR,
                        isProbablyBlank: isProbablyBlank
                    ))
                }

                let outcomes = await withTaskGroup(of: PageTaskOutcome.self, returning: [PageTaskOutcome].self) { group in
                    for payload in payloads {
                        group.addTask { [gemini] in
                            let pageNumber = payload.index + 1
                            do {
                                if payload.isProbablyBlank {
                                    let analysis = Self.blankPage(pageNumber: pageNumber)
                                    return .success(.init(
                                        index: payload.index,
                                        analysis: analysis,
                                        usedFallback: false,
                                        wasLocalBlank: true
                                    ))
                                }

                                let analysis = try await Self.withRetry(maxRetries: options.retryCount) {
                                    let result = try await gemini.analyzePage(
                                        pagePDF: payload.data,
                                        pageImage: payload.pageImage,
                                        detailTiles: payload.detailTiles,
                                        nativeText: payload.nativeText,
                                        localOCR: payload.localOCR,
                                        pageNumber: pageNumber,
                                        apiKey: apiKey,
                                        options: options
                                    )
                                    if result.blocks.allSatisfy({ $0.type == .blank }) {
                                        throw GeminiError.falseBlankPage(pageNumber)
                                    }
                                    return result
                                }
                                return .success(.init(
                                    index: payload.index,
                                    analysis: analysis,
                                    usedFallback: analysis.source == .visualPageFallback || analysis.source == .nativeTextFallback,
                                    wasLocalBlank: false
                                ))
                            } catch is CancellationError {
                                return .failure(.init(pageNumber: pageNumber, message: L10n.text("أُلغي التحويل."), cancelled: true))
                            } catch {
                                return .failure(.init(
                                    pageNumber: pageNumber,
                                    message: error.localizedDescription,
                                    cancelled: false
                                ))
                            }
                        }
                    }

                    var collected: [PageTaskOutcome] = []
                    collected.reserveCapacity(payloads.count)
                    for await outcome in group { collected.append(outcome) }
                    return collected
                }

                var firstFailure: PageTaskFailure?
                var sawCancellation = false
                let sortedOutcomes = outcomes.sorted { $0.pageNumber < $1.pageNumber }
                for outcome in sortedOutcomes {
                    switch outcome {
                    case .success(let success):
                        let analysis = success.analysis
                        analysesByPage[analysis.pageNumber] = analysis
                        try await store.saveAnalysis(analysis, in: record)
                        if success.usedFallback { fallbackPages.insert(analysis.pageNumber) }
                        warnings.formUnion(analysis.warnings)
                        if analysis.contentKind == .handwritten || analysis.contentKind == .mixed {
                            handwrittenPages.insert(analysis.pageNumber)
                        }
                        if analysis.source != .localBlankPage, analysis.qualityScore > 0 {
                            qualityScores.append(analysis.qualityScore)
                        }
                        record.completedPages = analysesByPage.count
                        record.fallbackPages = fallbackPages.sorted()
                        record.warnings = warnings.sorted()
                        record.handwrittenPages = handwrittenPages.sorted()
                        record.minimumQualityScore = qualityScores.min()
                        record.updatedAt = Date()
                        record.status = .analyzing
                        try await store.save(record)

                        let pageMessage: String
                        if analysis.source == .visualPageFallback {
                            pageMessage = L10n.format("حُفظت الصفحة %d كصورة كاملة لعدم تمرير قراءة غير موثوقة", analysis.pageNumber)
                        } else if success.usedFallback {
                            pageMessage = L10n.format("حُفظت الصفحة %d بمسار احتياطي مع تسجيل تحذير", analysis.pageNumber)
                        } else if success.wasLocalBlank {
                            pageMessage = L10n.format("حُفظت الصفحة الفارغة %d بعد تحقق محلي", analysis.pageNumber)
                        } else {
                            pageMessage = L10n.format("اجتازت الصفحة %d القراءة الثلاثية بدرجة %d%%", analysis.pageNumber, Int(analysis.qualityScore * 100))
                        }
                        await progress(.init(
                            status: .analyzing,
                            currentPage: record.completedPages,
                            totalPages: record.totalPages,
                            message: pageMessage
                        ))
                    case .failure(let failure):
                        if failure.cancelled {
                            sawCancellation = true
                        } else if firstFailure == nil {
                            firstFailure = failure
                        }
                    }
                }

                if sawCancellation || Task.isCancelled {
                    throw CancellationError()
                }
                if let firstFailure {
                    throw ConversionEngineError.pageFailed(
                        page: firstFailure.pageNumber,
                        reason: firstFailure.message
                    )
                }
            }

            try Task.checkCancellation()
            record.status = .building
            record.updatedAt = Date()
            try await store.save(record)
            await progress(.init(
                status: .building,
                currentPage: record.totalPages,
                totalPages: record.totalPages,
                message: L10n.text("تركيب النصوص والجداول والصور والتحقق من حزمة Word")
            ))

            let analyses = analysesByPage.values.sorted { $0.pageNumber < $1.pageNumber }
            guard analyses.count == extractor.pageCount else {
                throw ConversionEngineError.incompleteAnalysis(analyses.count, extractor.pageCount)
            }
            let expectedPages = Array(1...extractor.pageCount)
            guard analyses.map(\.pageNumber) == expectedPages else {
                throw ConversionEngineError.pageSequenceInvalid
            }
            if let rejected = analyses.first(where: {
                switch $0.source {
                case .localBlankPage, .visualPageFallback:
                    return false
                case .geminiConsensus:
                    return $0.qualityScore < 0.95 || $0.readingOrderConfidence < 0.95
                case .gemini, .nativeTextFallback:
                    return true
                }
            }) {
                throw ConversionEngineError.savedPageBelowAccuracy(
                    page: rejected.pageNumber,
                    score: rejected.qualityScore
                )
            }

            let outputURL = try Self.uniqueOutputURL(baseName: record.sourceName)
            let temporaryURL = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".building-\(UUID().uuidString).docx")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let builder = DOCXBuilder()
            try builder.build(
                analyses: analyses,
                extractor: extractor,
                options: options,
                outputURL: temporaryURL,
                title: record.sourceName
            )
            try DOCXPackageValidator.validate(url: temporaryURL)
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
            try (outputURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            let outputSHA256 = try await store.fingerprint(of: outputURL)
            let outputByteCount = try await store.byteCount(of: outputURL)
            guard outputByteCount > 0 else { throw JobStoreError.outputMissing }

            record.status = .completed
            record.completedPages = record.totalPages
            record.outputPath = outputURL.path
            record.errorMessage = nil
            record.outputSHA256 = outputSHA256
            record.outputByteCount = outputByteCount
            record.fallbackPages = fallbackPages.sorted()
            record.warnings = warnings.sorted()
            record.handwrittenPages = handwrittenPages.sorted()
            record.minimumQualityScore = qualityScores.min()
            record.updatedAt = Date()
            try await store.save(record)
            DiagnosticsLog.shared.record("convert", "COMPLETE | pages:\(record.totalPages) | fallbackPages:\(record.fallbackPages?.count ?? 0) | minQuality:\(record.minimumQualityScore.map { Int($0 * 100) } ?? -1)% | output:\(outputByteCount / 1024)KB | name:\(outputURL.lastPathComponent)")

            let completionMessage: String
            if let minimum = record.minimumQualityScore {
                completionMessage = L10n.format("اكتمل Word؛ أدنى درجة قبول داخلية بين الصفحات %d%%", Int(minimum * 100))
            } else {
                completionMessage = L10n.text("اكتمل إنشاء ملف Word والتحقق من سلامته")
            }
            await progress(.init(
                status: .completed,
                currentPage: record.totalPages,
                totalPages: record.totalPages,
                message: completionMessage
            ))
            return record
        } catch is CancellationError {
            record.status = .cancelled
            record.errorMessage = L10n.text("أُلغي التحويل. يمكنك استئنافه لاحقًا من السجل.")
            record.updatedAt = Date()
            try? await store.save(record)
            await progress(.init(
                status: .cancelled,
                currentPage: record.completedPages,
                totalPages: record.totalPages,
                message: L10n.text("أُلغي التحويل مع الاحتفاظ بالصفحات المكتملة")
            ))
            throw CancellationError()
        } catch {
            record.status = .failed
            record.errorMessage = error.localizedDescription
            record.updatedAt = Date()
            DiagnosticsLog.shared.record("convert", "FAILED at page \(record.completedPages + 1)/\(record.totalPages) | \(error.localizedDescription)")
            try? await store.save(record)
            await progress(.init(
                status: .failed,
                currentPage: record.completedPages,
                totalPages: record.totalPages,
                message: error.localizedDescription
            ))
            throw error
        }
    }

    private static func blankPage(pageNumber: Int) -> PageAnalysis {
        PageAnalysis(
            pageNumber: pageNumber,
            detectedLanguage: "und",
            direction: .ltr,
            blocks: [DocumentBlock(type: .blank, confidence: 1)],
            source: .localBlankPage,
            warnings: [],
            contentKind: .unknown,
            qualityScore: 1,
            agreementScore: 1,
            verificationPasses: 1
        )
    }

    private static func nativeFallback(
        text: String,
        pageNumber: Int,
        originalError: Error
    ) -> PageAnalysis {
        let direction: TextDirection = XML.containsArabic(text) ? .rtl : .ltr
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let doubleNewlineGroups = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let segments: [String]
        if doubleNewlineGroups.count > 1 {
            segments = doubleNewlineGroups
        } else {
            segments = normalized.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let blocks = (segments.isEmpty ? [normalized] : segments).map {
            DocumentBlock(type: .paragraph, text: $0, confidence: 0.55)
        }
        let warning = L10n.format("الصفحة %d استُخرجت من طبقة النص المحلية بعد تعذر Gemini: %@", pageNumber, originalError.localizedDescription)
        return PageAnalysis(
            pageNumber: pageNumber,
            detectedLanguage: direction == .rtl ? "ar" : "und",
            direction: direction,
            blocks: blocks,
            source: .nativeTextFallback,
            warnings: [warning]
        )
    }

    private static func withRetry<T: Sendable>(
        maxRetries: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                guard attempt < maxRetries, shouldRetry(error) else { throw error }
                attempt += 1
                let serverDelay = (error as? GeminiError)?.retryAfter
                let exponential = min(30.0, pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.8))
                let seconds = min(60.0, max(serverDelay ?? 0, exponential))
                try await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .internationalRoamingOff,
                .dataNotAllowed
            ].contains(urlError.code)
        }
        if let geminiError = error as? GeminiError {
            switch geminiError {
            case .httpStatus(let code, _, _):
                return code == 408 || code == 409 || code == 429 || (500...599).contains(code)
            case .emptyModelOutput,
                 .emptyPageAnalysis,
                 .invalidStructuredOutput,
                 .insufficientCoverage,
                 .excessiveExpansion,
                 .lowTextOverlap,
                 .qualityBelowAcceptance,
                 .falseBlankPage,
                 .incompleteCandidate,
                 .noCandidate:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func uniqueOutputURL(baseName: String) throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ConversionEngineError.outputDirectoryUnavailable
        }
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let clean = sanitize(baseName)
        let convertedSuffix = L10n.text("محوّل")
        var candidate = documents.appendingPathComponent("\(clean) - \(convertedSuffix).docx")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = documents.appendingPathComponent("\(clean) - \(convertedSuffix) \(number).docx")
            number += 1
        }
        return candidate
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let components = name.components(separatedBy: invalid).filter { !$0.isEmpty }
        let result = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? L10n.text("مستند") : String(result.prefix(100))
    }
}

private struct PagePayload: Sendable {
    let index: Int
    let data: Data
    let pageImage: Data?
    let detailTiles: [Data]
    let nativeText: String
    let localOCR: LocalOCRReference
    let isProbablyBlank: Bool
}

private struct PageTaskSuccess: Sendable {
    let index: Int
    let analysis: PageAnalysis
    let usedFallback: Bool
    let wasLocalBlank: Bool
}

private struct PageTaskFailure: Sendable {
    let pageNumber: Int
    let message: String
    let cancelled: Bool
}

private enum PageTaskOutcome: Sendable {
    case success(PageTaskSuccess)
    case failure(PageTaskFailure)

    var pageNumber: Int {
        switch self {
        case .success(let success): return success.analysis.pageNumber
        case .failure(let failure): return failure.pageNumber
        }
    }
}

enum ConversionEngineError: LocalizedError {
    case emptyDocument
    case pageCountChanged(expected: Int, actual: Int)
    case incompleteAnalysis(Int, Int)
    case pageSequenceInvalid
    case pageFailed(page: Int, reason: String)
    case savedPageBelowAccuracy(page: Int, score: Double)
    case outputDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return L10n.text("ملف PDF لا يحتوي على صفحات.")
        case .pageCountChanged(let expected, let actual):
            return L10n.format("تغير عدد صفحات النسخة المحلية من %d إلى %d، لذلك أُوقف الاستئناف لحماية النتيجة.", expected, actual)
        case .incompleteAnalysis(let completed, let total):
            return L10n.format("اكتمل تحليل %d صفحة فقط من أصل %d.", completed, total)
        case .pageSequenceInvalid:
            return L10n.text("نتائج الصفحات المحفوظة غير متسلسلة، لذلك أُوقف إنشاء Word لتجنب إسقاط صفحة أو تكرارها.")
        case .pageFailed(let page, let reason):
            return L10n.format("تعذر إكمال الصفحة %d. حُفظت الصفحات الأخرى المكتملة ويمكن الاستئناف لاحقًا. السبب: %@", page, reason)
        case .savedPageBelowAccuracy(let page, let score):
            return L10n.format("نتيجة الصفحة %d المحفوظة لا تحقق بوابة القبول 95%%؛ درجتها %d%%. يجب إعادة تحليلها قبل إنشاء Word.", page, Int(score * 100))
        case .outputDirectoryUnavailable:
            return L10n.text("تعذر الوصول إلى مجلد المستندات لحفظ ملف Word.")
        }
    }
}
