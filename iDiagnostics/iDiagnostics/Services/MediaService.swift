import SwiftUI
import AVFoundation
import UIKit

// MARK: - Shared permission state

/// A simple, UI-friendly permission state shared by the media controllers.
enum MediaPermission: Equatable {
    case undetermined
    case granted
    case denied
}

/// Opens the app's page in the system Settings so the user can flip a denied
/// permission. Used by the "افتح الإعدادات" buttons across the media tests.
@MainActor
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

// MARK: - Reusable permission-denied guidance

/// A friendly, adaptive card shown when a capture permission is denied. Gives an
/// honest Arabic explanation plus a direct shortcut to Settings.
struct PermissionDeniedCard: View {
    let systemImage: String
    let message: String

    var body: some View {
        Card {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                PrimaryButton(title: "افتح الإعدادات", systemImage: "gearshape.fill") {
                    openAppSettings()
                }
                .accessibilityHint("يفتح إعدادات التطبيق لتفعيل الإذن")
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Camera

/// Owns the capture session for the camera test: front/back switching, torch
/// control on the back camera, and permission handling. UIKit / published state
/// lives on the main actor; heavy session work hops to a private serial queue.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum CameraSide: Equatable { case front, back }

    /// The live session the preview layer renders. Non-isolated so it can be
    /// safely captured into the session queue closures.
    nonisolated let session = AVCaptureSession()

    @Published private(set) var permission: MediaPermission
    @Published private(set) var side: CameraSide = .back
    @Published private(set) var hasTorch = false
    @Published private(set) var torchOn = false
    @Published private(set) var isRunning = false

    private let sessionQueue = DispatchQueue(label: "com.idiagnostics.camera.session")
    private var currentInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var configured = false

    override init() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:            permission = .granted
        case .denied, .restricted:   permission = .denied
        default:                     permission = .undetermined
        }
        super.init()
    }

    /// Asks for camera access (or reflects an existing decision), then starts.
    func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.start() }
                }
            }
        default:
            permission = .denied
        }
    }

    private func start() {
        if !configured {
            configured = true
            configureSession(for: side)
        }
        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
            Task { @MainActor in self.isRunning = true }
        }
    }

    /// Stops the session and turns off the torch. Call when leaving the screen.
    func stop() {
        setTorch(false)
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
            Task { @MainActor in self.isRunning = false }
        }
    }

    /// Flips between the front and back cameras with a smooth reconfiguration.
    func toggleSide() {
        let newSide: CameraSide = (side == .back) ? .front : .back
        if newSide == .front { setTorch(false) }
        side = newSide
        configureSession(for: newSide)
    }

    private func configureSession(for side: CameraSide) {
        let position: AVCaptureDevice.Position = (side == .back) ? .back : .front
        let session = self.session
        let previousInput = currentInput
        sessionQueue.async {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: position)
            guard let device = discovery.devices.first,
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            session.beginConfiguration()
            session.sessionPreset = .high
            if let previousInput { session.removeInput(previousInput) }
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()

            Task { @MainActor in
                self.currentInput = input
                self.currentDevice = device
                self.hasTorch = (side == .back) && device.hasTorch
                self.torchOn = false
            }
        }
    }

    /// Toggles the back-camera torch. No-ops when the device has no torch.
    func toggleTorch() { setTorch(!torchOn) }

    private func setTorch(_ on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
        torchOn = on
    }
}

/// A thin `UIViewRepresentable` wrapper around `AVCaptureVideoPreviewLayer`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe: layerClass guarantees the backing layer type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Microphone

/// Records a short clip and plays it back so the user can verify the mic. The
/// specific physical mic (primary vs. secondary) is chosen by the system and is
/// not individually selectable through public API.
@MainActor
final class MicrophoneController: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum Phase: Equatable { case idle, recording, playing, finished }

    @Published private(set) var permission: MediaPermission = .undetermined
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0          // 0…1 metering, for UI feedback

    private let recordDuration: TimeInterval = 3
    private let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("idiagnostics-mic-test.m4a")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var stopWorkItem: DispatchWorkItem?

    /// Requests record permission using the newest API available on the OS.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        let handler: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                self?.permission = granted ? .granted : .denied
                completion(granted)
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handler)
        }
    }

    /// Requests permission if needed, then records for ~3s and auto-plays.
    func recordThenPlay() {
        requestPermission { [weak self] granted in
            guard granted else { return }
            self?.beginRecording()
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record(forDuration: recordDuration)
            self.recorder = recorder
            phase = .recording
            startMetering()

            let work = DispatchWorkItem { [weak self] in self?.finishRecording() }
            stopWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + recordDuration + 0.1, execute: work)
        } catch {
            phase = .idle
        }
    }

    private func finishRecording() {
        recorder?.stop()
        stopMetering()
        playRecording()
    }

    private func playRecording() {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            self.player = player
            phase = .playing
            player.play()
        } catch {
            phase = .finished
        }
    }

    private func startMetering() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)      // dB, -160…0
                self.level = max(0, min(1, (power + 60) / 60))
            }
        }
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
    }

    func cancel() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        recorder?.stop()
        player?.stop()
        stopMetering()
        phase = .idle
    }

    // AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.phase = .finished }
    }
}

// MARK: - Speaker

/// Plays a clear sine-wave test tone routed to the loud speaker. Note: iOS does
/// not publicly expose selecting the individual top vs. bottom speaker, so the
/// test exercises the loud speaker as routed by the system.
@MainActor
final class SpeakerController: ObservableObject {
    @Published private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var attached = false

    private let frequency: Double = 660      // pleasant mid tone within 440–880 Hz
    private let duration: Double = 1.5

    /// Routes audio to the loud speaker and plays the test tone once.
    func playTestTone() {
        guard !isPlaying else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // `.playback` already routes to the loud speaker (absent headphones).
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
            // Best-effort explicit routing; harmless if the category disallows it.
            try? audioSession.overrideOutputAudioPort(.speaker)

            if !attached {
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode,
                               format: engine.mainMixerNode.outputFormat(forBus: 0))
                attached = true
            }

            guard let buffer = makeToneBuffer() else { return }
            if !engine.isRunning { try engine.start() }

            isPlaying = true
            playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor in self?.isPlaying = false }
            }
            playerNode.play()
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        isPlaying = false
    }

    /// Synthesises a mono sine-wave PCM buffer with a short fade in/out to avoid
    /// clicks at the boundaries.
    private func makeToneBuffer() -> AVAudioPCMBuffer? {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        let fade = Int(sampleRate * 0.02)                 // 20 ms ramps
        let total = Int(frameCount)
        guard let channelData = buffer.floatChannelData else { return nil }

        for frame in 0..<total {
            let theta = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
            var sample = Float(sin(theta)) * 0.5          // −6 dB headroom
            if frame < fade {
                sample *= Float(frame) / Float(fade)
            } else if frame > total - fade {
                sample *= Float(total - frame) / Float(fade)
            }
            for channel in 0..<channels {
                channelData[channel][frame] = sample
            }
        }
        return buffer
    }
}
