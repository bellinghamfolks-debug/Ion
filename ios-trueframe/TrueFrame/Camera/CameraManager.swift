import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import UIKit

/// Owns the AVCaptureSession, preview frames, and still-photo capture.
/// All session mutations happen on `sessionQueue` so capture can never race
/// permission resolution or session configuration.
public final class CameraManager: NSObject, ObservableObject {

    public let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.trueframe.session")
    private let videoQueue = DispatchQueue(label: "com.trueframe.video")

    public var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation) -> Void)?
    public var onPhoto: ((CGImage?, [String: Any]?) -> Void)?

    @Published public private(set) var isRunning = false
    @Published public private(set) var authorized = false
    @Published public private(set) var isCaptureReady = false
    @Published public private(set) var lastErrorMessage: String?

    private var frameCounter = 0
    public var analyzeEveryNthFrame = 3

    private var configured = false
    private var captureInFlight = false

    private let orientationLock = NSLock()
    private var cachedDeviceOrientation: UIDeviceOrientation = .portrait
    private var orientationObserver: NSObjectProtocol?

    public override init() {
        super.init()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateCachedDeviceOrientation()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCachedDeviceOrientation()
        }
    }

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    public func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            publishAuthorization(true)
            sessionQueue.async { [weak self] in
                guard let self else { return }
                guard self.configureIfNeeded() else { return }
                self.startRunning()
            }

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.publishAuthorization(granted)
                guard granted else {
                    self.publishFailure("Camera access is required to take photos.")
                    return
                }
                self.sessionQueue.async {
                    guard self.configureIfNeeded() else { return }
                    self.startRunning()
                }
            }

        default:
            publishAuthorization(false)
            publishFailure("Camera access is disabled. Enable it in Settings.")
        }
    }

    private func startRunning() {
        guard configured else {
            publishFailure("Camera setup is incomplete.")
            return
        }
        guard !session.isRunning else {
            publishReadiness()
            return
        }

        session.startRunning()
        let running = session.isRunning
        DispatchQueue.main.async {
            self.isRunning = running
            self.lastErrorMessage = running ? nil : "The camera could not start."
        }
        publishReadiness()
    }

    /// Configures the session transactionally. `configured` becomes true only
    /// after the input and both outputs are installed successfully.
    @discardableResult
    private func configureIfNeeded() -> Bool {
        if configured { return true }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            publishFailure("No rear camera is available.")
            return false
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            publishFailure("The camera could not be opened.")
            return false
        }

        session.beginConfiguration()
        var addedInput = false
        var addedVideoOutput = false
        var addedPhotoOutput = false

        func rollback() {
            if addedPhotoOutput { session.removeOutput(photoOutput) }
            if addedVideoOutput { session.removeOutput(videoOutput) }
            if addedInput { session.removeInput(input) }
            session.commitConfiguration()
        }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard session.canAddInput(input) else {
            rollback()
            publishFailure("The camera input is unavailable.")
            return false
        }
        session.addInput(input)
        addedInput = true

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            rollback()
            publishFailure("Live camera analysis is unavailable.")
            return false
        }
        session.addOutput(videoOutput)
        addedVideoOutput = true

        guard session.canAddOutput(photoOutput) else {
            rollback()
            publishFailure("Photo capture is unavailable.")
            return false
        }
        session.addOutput(photoOutput)
        addedPhotoOutput = true

        // A request must not ask for a higher prioritization than the output
        // allows. Explicitly enabling quality avoids device-dependent crashes.
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()
        configured = true
        publishFailure(nil)
        publishReadiness()
        return true
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.captureInFlight = false
            DispatchQueue.main.async {
                self.isRunning = false
                self.isCaptureReady = false
            }
        }
    }

    /// Safe no-throw capture entry point. Calls made before the camera is ready
    /// are rejected gracefully instead of being forwarded to AVFoundation.
    public func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configured,
                  self.session.isRunning,
                  self.session.outputs.contains(where: { $0 === self.photoOutput }),
                  let connection = self.photoOutput.connection(with: .video),
                  connection.isEnabled,
                  !self.captureInFlight else {
                self.publishFailure("The camera is not ready yet.")
                DispatchQueue.main.async { self.onPhoto?(nil, nil) }
                return
            }

            self.captureInFlight = true
            self.publishReadiness()
            self.applyCaptureOrientation(to: connection)

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func updateCachedDeviceOrientation() {
        let orientation = UIDevice.current.orientation
        guard orientation == .portrait
                || orientation == .portraitUpsideDown
                || orientation == .landscapeLeft
                || orientation == .landscapeRight else {
            return
        }
        orientationLock.lock()
        cachedDeviceOrientation = orientation
        orientationLock.unlock()
    }

    private func currentDeviceOrientation() -> UIDeviceOrientation {
        orientationLock.lock()
        let value = cachedDeviceOrientation
        orientationLock.unlock()
        return value
    }

    private func currentVisionOrientation() -> CGImagePropertyOrientation {
        switch currentDeviceOrientation() {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }

    private func applyCaptureOrientation(to connection: AVCaptureConnection) {
        guard connection.isVideoOrientationSupported else { return }
        switch currentDeviceOrientation() {
        case .portrait:
            connection.videoOrientation = .portrait
        case .portraitUpsideDown:
            connection.videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            connection.videoOrientation = .landscapeRight
        case .landscapeRight:
            connection.videoOrientation = .landscapeLeft
        default:
            connection.videoOrientation = .portrait
        }
    }

    private func publishAuthorization(_ value: Bool) {
        DispatchQueue.main.async { self.authorized = value }
    }

    private func publishFailure(_ message: String?) {
        DispatchQueue.main.async {
            self.lastErrorMessage = message
            if message != nil { self.isCaptureReady = false }
        }
    }

    private static func makeOrientationCorrectedImage(
        from source: CGImageSource,
        metadata: [String: Any]?
    ) -> CGImage? {
        let width = (metadata?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let height = (metadata?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        let maxPixelSize = max(width, height)

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if maxPixelSize > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func publishReadiness() {
        let ready = configured
            && session.isRunning
            && session.outputs.contains(where: { $0 === photoOutput })
            && (photoOutput.connection(with: .video)?.isEnabled == true)
            && !captureInFlight

        DispatchQueue.main.async {
            self.isCaptureReady = ready
            if ready { self.lastErrorMessage = nil }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        frameCounter &+= 1
        let stride = max(1, analyzeEveryNthFrame)
        guard frameCounter % stride == 0 else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer, currentVisionOrientation())
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            publishFailure("Capture failed. Try again.")
            DispatchQueue.main.async { self.onPhoto?(nil, nil) }
            return
        }

        let src = CGImageSourceCreateWithData(data as CFData, nil)
        let meta = src.flatMap {
            CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any]
        }
        let cg = src.flatMap { source in
            Self.makeOrientationCorrectedImage(from: source, metadata: meta)
        }

        guard cg != nil else {
            publishFailure("The captured image could not be decoded.")
            DispatchQueue.main.async { self.onPhoto?(nil, meta) }
            return
        }

        publishFailure(nil)
        DispatchQueue.main.async { self.onPhoto?(cg, meta) }
    }
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                            error: Error?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureInFlight = false
            self.publishReadiness()
        }
        if error != nil {
            publishFailure("Capture failed. Try again.")
        }
    }

}
