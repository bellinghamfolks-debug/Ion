import Foundation

actor ConversionEngine {
    typealias ProgressHandler = @Sendable (ConversionProgress) -> Void

    func convert(
        sourceURL: URL,
        outputURL: URL,
        options: ConversionOptions,
        configuration: ServerConfiguration,
        requestID: String,
        progress: @escaping ProgressHandler,
        logger: DiagnosticLogger,
        checkpointDirectory: URL? = nil
    ) async throws -> ConversionOutcome {
        guard configuration.isConfigured else { throw BasirError.notConfigured }
        try Task.checkCancellation()
        progress(.init(current: 0, total: 0, stage: .preparing,
                       detail: sourceURL.lastPathComponent))
        return try await ProxyClient(configuration: configuration).convert(
            sourceURL: sourceURL,
            outputURL: outputURL,
            options: options,
            requestID: requestID,
            progress: progress,
            logger: logger
        )
    }
}

