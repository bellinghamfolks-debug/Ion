import Foundation
import CoreImage
import CoreGraphics

/// Deterministic, non-generative geometric correction. Given a source image and
/// a `CorrectionPlan`, it rotates to level and crops away the empty corners so
/// that every output pixel comes from the source (aside from normal
/// interpolation). It NEVER synthesizes content, and routes each step through
/// `AuthenticityGuard`.
public struct GeometricImageProcessor {

    public struct Output {
        public let image: CGImage
        public let provenance: EditingProvenance
    }

    public enum ProcessingError: Error { case renderFailed, emptyImage }

    private let guardPolicy: AuthenticityGuard
    private let context: CIContext

    public init(guard authenticityGuard: AuthenticityGuard = AuthenticityGuard(),
                context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.guardPolicy = authenticityGuard
        self.context = context
    }

    /// Apply `plan` to `source`. Default behavior: rotate, then crop the empty
    /// corners (never expand the canvas / invent scenery).
    public func correct(_ source: CGImage, plan: CorrectionPlan) throws -> Output {
        let w0 = source.width, h0 = source.height
        guard w0 > 0, h0 > 0 else { throw ProcessingError.emptyImage }

        var ops: [ImageOperationKind] = []
        var ci = CIImage(cgImage: source)
        let ext = ci.extent
        let center = CGPoint(x: ext.midX, y: ext.midY)

        // --- Rotation (level the horizon) ---
        let angleRad = -plan.rollDegrees * .pi / 180     // rotate opposite the tilt
        if abs(plan.rollDegrees) > 0.02 {
            try guardPolicy.authorize(.rotate)
            var t = CGAffineTransform(translationX: center.x, y: center.y)
            t = t.rotated(by: angleRad)
            t = t.translatedBy(x: -center.x, y: -center.y)
            ci = ci.transformed(by: t)
            ops.append(.rotate)
            ops.append(.horizonLevel)
        }

        // --- Crop to the largest region containing only source pixels ---
        let (wr, hr) = CropSolver.largestInscribed(w0: Double(w0), h0: Double(h0), angle: angleRad)
        var cropRect = CGRect(x: center.x - wr / 2, y: center.y - hr / 2, width: wr, height: hr)
        // Honor an explicit tighter crop from the plan (already normalized to the
        // ORIGINAL image); intersect so we never exceed the valid region.
        if plan.cropNormalized != .full {
            let planRect = CGRect(
                x: ext.origin.x + CGFloat(plan.cropNormalized.x) * ext.width,
                y: ext.origin.y + CGFloat(1 - plan.cropNormalized.y - plan.cropNormalized.height) * ext.height,
                width: CGFloat(plan.cropNormalized.width) * ext.width,
                height: CGFloat(plan.cropNormalized.height) * ext.height)
            cropRect = cropRect.intersection(planRect)
        }
        if abs(plan.rollDegrees) > 0.02 || plan.cropNormalized != .full {
            try guardPolicy.authorize(.crop)
            ci = ci.cropped(to: cropRect)
            ops.append(.crop)
        }
        guard !ci.extent.isEmpty, ci.extent.isFinite else { throw ProcessingError.emptyImage }

        guard let out = context.createCGImage(ci, from: ci.extent) else { throw ProcessingError.renderFailed }

        // --- Provenance: what actually happened, for the audit record ---
        let cropNorm = CropSolver.largestValidCrop(imageSize: CGSize(width: w0, height: h0), degrees: plan.rollDegrees)
        let provenance = EditingProvenance(
            policy: guardPolicy.policy,
            rotationDegrees: plan.rollDegrees,
            perspectiveVerticalDegrees: 0,
            perspectiveHorizontalDegrees: 0,
            cropRectNormalized: cropNorm,
            croppedAreaFraction: CropSolver.croppedAreaFraction(cropNorm),
            appliedOperations: ops,
            aiAnalysisPerformed: false,
            generativeModelAlteredPixels: false)     // guaranteed by policy + guard
        return Output(image: out, provenance: provenance)
    }

    /// Perspective (keystone) correction from four detected corner points, in
    /// source pixel coordinates (top-left origin). Used by Document / rectangle
    /// modes. Still non-generative: it only re-samples existing pixels.
    public func correctPerspective(_ source: CGImage,
                                   topLeft: CGPoint, topRight: CGPoint,
                                   bottomLeft: CGPoint, bottomRight: CGPoint) throws -> CGImage {
        try guardPolicy.authorize(.perspectiveCorrect)
        let h = CGFloat(source.height)
        // CoreImage uses a bottom-left origin; flip the incoming y coordinates.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: h - p.y) }
        let ci = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { throw ProcessingError.renderFailed }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: flip(topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: flip(topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: flip(bottomLeft)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: flip(bottomRight)), forKey: "inputBottomRight")
        guard let outCI = filter.outputImage,
              let out = context.createCGImage(outCI, from: outCI.extent) else {
            throw ProcessingError.renderFailed
        }
        return out
    }
}
