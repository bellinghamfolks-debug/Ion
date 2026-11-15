import Foundation

/// Conversion succeeded remotely. Preserve its identity even when local saving fails.
struct ReadyResultDownloadError: LocalizedError {
    let jobID: String
    let cause: Error
    var errorDescription: String? { "The result is ready on the server; downloading or saving it needs another attempt." }
}

enum ReadyResultRetry {
    static func shouldRetry(_ error: Error, status: Int?) -> Bool {
        if error is CancellationError { return false }
        if let status, !(200..<300).contains(status) {
            return [408, 425, 429, 500, 502, 503, 504].contains(status)
        }
        if let url = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                    .cannotDecodeContentData].contains(url.code)
        }
        if let basir = error as? BasirError {
            switch basir {
            case .checksumMismatch, .invalidServerContentType: return true
            default: return false
            }
        }
        return false
    }

    static func delay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        min(30, max(1, retryAfter ?? pow(2, Double(min(4, max(0, attempt)))) * 2))
    }
}
