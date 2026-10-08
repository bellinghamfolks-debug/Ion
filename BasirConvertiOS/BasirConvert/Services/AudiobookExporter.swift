import AVFoundation
import Foundation

/// Turns a document into an audio file (m4a) on the phone, with the same
/// Arabic and English voices the reader uses. Nothing leaves the device.
final class AudiobookRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let format: AVAudioFormat
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private let queue = DispatchQueue(label: "com.basir.audiobook")

    init(url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050,
                                         channels: 1, interleaved: false) else {
            throw BasirError.conversionFailed("Audio format unavailable.")
        }
        self.format = format
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    /// Speaks one passage into the file and returns when it is written.
    func append(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: ReaderContent.speechLanguage(for: trimmed))
        utterance.rate = rate
        let progress = PassageProgress()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            progress.continuation = continuation
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                self.queue.sync {
                    guard !progress.finished else { return }
                    guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                        progress.finish()
                        return
                    }
                    progress.lastBuffer = Date()
                    self.write(pcm)
                }
            }
            // Some iOS versions never send the closing empty buffer; a
            // passage that has been silent for five seconds is finished.
            watch(progress)
        }
        writeSilence(seconds: 0.35)
    }

    private func watch(_ progress: PassageProgress) {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard !progress.finished else { return }
            if Date().timeIntervalSince(progress.lastBuffer) > 5 { progress.finish() } else { self?.watch(progress) }
        }
    }

    /// Closes the file so it can be shared.
    func finish() {
        queue.sync {
            converter = nil
            file = nil
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, output.frameLength > 0 { try? file.write(from: output) }
    }

    private func writeSilence(seconds: Double) {
        queue.sync {
            guard let file,
                  let silence = AVAudioPCMBuffer(pcmFormat: format,
                                                 frameCapacity: AVAudioFrameCount(format.sampleRate * seconds)) else { return }
            silence.frameLength = silence.frameCapacity
            try? file.write(from: silence)
        }
    }
}

/// State of one passage being written; touched only on the renderer's queue.
private final class PassageProgress: @unchecked Sendable {
    var finished = false
    var lastBuffer = Date()
    var continuation: CheckedContinuation<Void, Never>?

    func finish() {
        guard !finished else { return }
        finished = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class AudiobookExporter: ObservableObject {
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var resultURL: URL?
    @Published private(set) var failed = false
    @Published private(set) var running = false
    private var task: Task<Void, Never>?

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    func start(passages: [String], title: String) {
        guard !running else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Audiobooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        let url = directory.appendingPathComponent("\(safeTitle).m4a")
        try? FileManager.default.removeItem(at: url)
        let items = passages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        total = items.count
        done = 0
        failed = false
        resultURL = nil
        running = true
        task = Task {
            do {
                let renderer = try AudiobookRenderer(url: url)
                for passage in items {
                    if Task.isCancelled { break }
                    await renderer.append(passage)
                    done += 1
                }
                renderer.finish()
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    resultURL = url
                }
            } catch {
                failed = true
            }
            running = false
        }
    }

    func cancel() {
        task?.cancel()
    }
}
