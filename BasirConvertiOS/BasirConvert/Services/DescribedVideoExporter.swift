import AVFoundation
import Foundation

/// Exports a local video with narration. Freeze frames give each description
/// room to finish, preserving both the original dialogue and every narration word.
enum DescribedVideoExporter {
    @MainActor
    static func export(source: URL, cues: [DescriptionCue], progress: @escaping (Int, Int) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard let originalVideo = try await asset.loadTracks(withMediaType: .video).first else { throw BasirError.invalidResponse("No video track") }
        let originalAudio = try await asset.loadTracks(withMediaType: .audio).first
        let availableAudio: CMTimeRange?
        if let originalAudio { availableAudio = try await originalAudio.load(.timeRange) } else { availableAudio = nil }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let narration = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw BasirError.invalidResponse("Cannot create tracks") }
        video.preferredTransform = try await originalVideo.load(.preferredTransform)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Basir-narration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func insertOriginalAudio(_ range: CMTimeRange, at time: CMTime) throws {
            guard let originalAudio, let availableAudio else { return }
            let clipped = CMTimeRangeGetIntersection(range, otherRange: availableAudio)
            guard clipped.isValid, clipped.duration > .zero else { return }
            try audio.insertTimeRange(clipped, of: originalAudio, at: CMTimeAdd(time, CMTimeSubtract(clipped.start, range.start)))
        }
        var cursor = CMTime.zero
        var destination = CMTime.zero
        let ordered = cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.time >= 0 && Double($0.time) < duration.seconds }.sorted { $0.time < $1.time }
        for (index, cue) in ordered.enumerated() {
            try Task.checkCancellation()
            let position = CMTime(seconds: Double(cue.time), preferredTimescale: 600)
            let chunk = CMTimeSubtract(position, cursor)
            if chunk > .zero {
                let range = CMTimeRange(start: cursor, duration: chunk)
                try video.insertTimeRange(range, of: originalVideo, at: destination)
                try insertOriginalAudio(range, at: destination)
                destination = CMTimeAdd(destination, chunk)
            }
            let speechURL = folder.appendingPathComponent("cue-\(index).m4a")
            let renderer = try AudiobookRenderer(url: speechURL)
            await renderer.append(cue.text)
            renderer.finish()
            let spoken = AVURLAsset(url: speechURL)
            let length = try await spoken.load(.duration)
            guard length.isNumeric, length.seconds > 0,
                  let speechTrack = try await spoken.loadTracks(withMediaType: .audio).first else { throw BasirError.invalidResponse("Narration unavailable") }
            let frameLength = CMTimeMinimum(CMTime(seconds: 0.04, preferredTimescale: 600), CMTimeSubtract(duration, position))
            try video.insertTimeRange(CMTimeRange(start: position, duration: frameLength), of: originalVideo, at: destination)
            video.scaleTimeRange(CMTimeRange(start: destination, duration: frameLength), toDuration: length)
            try narration.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: speechTrack, at: destination)
            destination = CMTimeAdd(destination, length)
            cursor = position
            progress(index + 1, ordered.count)
        }
        let remaining = CMTimeSubtract(duration, cursor)
        if remaining > .zero {
            let range = CMTimeRange(start: cursor, duration: remaining)
            try video.insertTimeRange(range, of: originalVideo, at: destination)
            try insertOriginalAudio(range, at: destination)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw BasirError.invalidResponse("Export unavailable") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Basir-described-\(UUID().uuidString).mp4")
        session.outputURL = output
        session.outputFileType = .mp4
        await withTaskCancellationHandler(operation: { await session.export() }, onCancel: { session.cancelExport() })
        guard session.status == .completed else { try? FileManager.default.removeItem(at: output); throw session.error ?? BasirError.invalidResponse("Video export failed") }
        return output
    }
}
