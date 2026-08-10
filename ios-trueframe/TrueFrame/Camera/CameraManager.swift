import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO

/// Owns the AVCaptureSession: streams preview frames (throttled) to the analysis
/// pipeline and captures full-resolution photos. All processing is on-device.
public final class CameraManager: NSObject, ObservableObject {

    public let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.trueframe.session")
    private let videoQueue = DispatchQueue(label: "com.trueframe.video")

    /// Called on `videoQueue` for each sampled preview frame (luma-friendly
    /// 420f buffer). Analyzers read the Y plane directly.
    public var onFrame: ((CVPixelBuffer) -> Void)?
    /// Called on the main queue with the captured photo (already orientation-
    /// corrected) and its metadata.
    public var onPhoto: ((CGImage?, [String: Any]?) -> Void)?

    @Published public private(set) var isRunning = false
    @Published public private(set) var authorized = false

    private var frameCounter = 0
    /// Analyze ~every 3rd frame (adaptive sampling; ~10 Hz at 30 fps).
    public var analyzeEveryNthFrame = 3

    public func requestAccessAndConfigure() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async { self.authorized = granted }
            guard granted else { return }
            self.sessionQueue.async { self.configure() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        // Input: wide rear camera by default.
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        // Preview frames as biplanar 420f so the Y plane is ready-made luma.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
    }

    public func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    public func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    public func capturePhoto() {
        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        frameCounter &+= 1
        guard frameCounter % analyzeEveryNthFrame == 0 else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.onPhoto?(nil, nil) }
            return
        }
        let src = CGImageSourceCreateWithData(data as CFData, nil)
        let cg = src.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        let meta = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
        DispatchQueue.main.async { self.onPhoto?(cg, meta) }
    }
}
