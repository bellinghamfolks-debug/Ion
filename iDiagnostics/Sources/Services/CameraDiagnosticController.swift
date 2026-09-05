import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

enum MediaPermissionState: Equatable {
    case undetermined
    case requesting
    case granted
    case denied
}

enum CameraSide: String, Hashable {
    case back
    case front

    var titleAr: String { self == .back ? "الخلفية" : "الأمامية" }
    var position: AVCaptureDevice.Position { self == .back ? .back : .front }
}

final class CameraDiagnosticController: ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var permission: MediaPermissionState = .undetermined
    @Published private(set) var side: CameraSide = .back
    @Published private(set) var hasTorch = false
    @Published private(set) var torchOn = false
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.bellinghamfolks.idiagnostics.camera")
    private var activeDevice: AVCaptureDevice?
    private var configured = false

    init() {
        refreshPermission()
    }

    func requestAccessAndStart() {
        errorMessage = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
            configureAndStart(side: side)
        case .notDetermined:
            permission = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.configureAndStart(side: self.side) }
                }
            }
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            permission = .denied
        }
    }

    func switchCamera() {
        let newSide: CameraSide = side == .back ? .front : .back
        side = newSide
        setTorch(false)
        guard permission == .granted else { return }
        configureAndStart(side: newSide)
    }

    func setTorch(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if enabled {
                    try device.setTorchModeOn(level: min(0.6, AVCaptureDevice.maxAvailableTorchLevel))
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.torchOn = enabled }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "تعذر تشغيل الفلاش: \(error.localizedDescription)"
                    self.torchOn = false
                }
            }
        }
    }

    func stop() {
        setTorch(false)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = .granted
        case .notDetermined: permission = .undetermined
        case .denied, .restricted: permission = .denied
        @unknown default: permission = .denied
        }
    }

    private func configureAndStart(side: CameraSide) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configure(side: side)
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.configured = true
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func configure(side: CameraSide) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: side.position) else {
            throw CameraDiagnosticError.cameraUnavailable(side.titleAr)
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        for existing in session.inputs { session.removeInput(existing) }
        guard session.canAddInput(input) else {
            throw CameraDiagnosticError.cannotConfigure
        }
        session.addInput(input)
        activeDevice = device

        DispatchQueue.main.async { [weak self] in
            self?.hasTorch = side == .back && device.hasTorch
            self?.torchOn = false
        }
    }
}

enum CameraDiagnosticError: LocalizedError {
    case cameraUnavailable(String)
    case cannotConfigure

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable(let side): return "الكاميرا \(side) غير متاحة على هذا الجهاز."
        case .cannotConfigure: return "تعذر إعداد جلسة الكاميرا بأمان."
        }
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer?.session !== session {
            uiView.previewLayer?.session = session
        }
    }
}
