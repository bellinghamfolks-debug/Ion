import Foundation
import CoreImage
import CoreGraphics

/// Deterministic, non-generative geometric correction.
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

    public func correct(_ source: CGImage,
                        plan: CorrectionPlan) throws -> Output {
        let sourceWidth = source.width
        let sourceHeight = source.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ProcessingError.emptyImage
        }

        var operations: [ImageOperationKind] = []
        var image = CIImage(cgImage: source)
        let originalExtent = image.extent
        let center = CGPoint(x: originalExtent.midX, y: originalExtent.midY)

        let angleRadians = -plan.rollDegrees * .pi / 180
        if abs(plan.rollDegrees) > 0.02 {
            try guardPolicy.authorize(.rotate)
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
            transform = transform.rotated(by: angleRadians)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: transform)
            operations.append(.rotate)
            operations.append(.horizonLevel)
        }

        let validSize = CropSolver.largestInscribed(
            w0: Double(sourceWidth),
            h0: Double(sourceHeight),
            angle: angleRadians
        )
        var cropRect = CGRect(x: center.x - validSize.w / 2,
                              y: center.y - validSize.h / 2,
                              width: validSize.w,
                              height: validSize.h)

        if plan.cropNormalized != .full {
            let plannedRect = CGRect(
                x: originalExtent.origin.x + CGFloat(plan.cropNormalized.x) * originalExtent.width,
                y: originalExtent.origin.y
                    + CGFloat(1 - plan.cropNormalized.y - plan.cropNormalized.height) * originalExtent.height,
                width: CGFloat(plan.cropNormalized.width) * originalExtent.width,
                height: CGFloat(plan.cropNormalized.height) * originalExtent.height
            )
            cropRect = cropRect.intersection(plannedRect)
        }

        if abs(plan.rollDegrees) > 0.02 || plan.cropNormalized != .full {
            try guardPolicy.authorize(.crop)
            guard !cropRect.isNull, !cropRect.isEmpty else {
                throw ProcessingError.emptyImage
            }
            image = image.cropped(to: cropRect)
            operations.append(.crop)
        }

        guard !image.extent.isEmpty, !image.extent.isInfinite else {
            throw ProcessingError.emptyImage
        }
        guard let rendered = context.createCGImage(image, from: image.extent) else {
            throw ProcessingError.renderFailed
        }

        let actualCrop = plan.cropNormalized != .full
            ? plan.cropNormalized
            : CropSolver.largestValidCrop(
                imageSize: CGSize(width: sourceWidth, height: sourceHeight),
                degrees: plan.rollDegrees
            )

        let provenance = EditingProvenance(
            policy: guardPolicy.policy,
            rotationDegrees: plan.rollDegrees,
            perspectiveVerticalDegrees: 0,
            perspectiveHorizontalDegrees: 0,
            cropRectNormalized: actualCrop,
            croppedAreaFraction: CropSolver.croppedAreaFraction(actualCrop),
            appliedOperations: operations,
            aiAnalysisPerformed: false,
            generativeModelAlteredPixels: false
        )

        return Output(image: rendered, provenance: provenance)
    }

    public func correctPerspective(_ source: CGImage,
                                   topLeft: CGPoint,
                                   topRight: CGPoint,
                                   bottomLeft: CGPoint,
                                   bottomRight: CGPoint) throws -> CGImage {
        try guardPolicy.authorize(.perspectiveCorrect)
        let height = CGFloat(source.height)

        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: height - point.y)
        }

        let image = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw ProcessingError.renderFailed
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: flip(topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: flip(topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: flip(bottomLeft)), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: flip(bottomRight)), forKey: "inputBottomRight")

        guard let output = filter.outputImage,
              let rendered = context.createCGImage(output, from: output.extent) else {
            throw ProcessingError.renderFailed
        }
        return rendered
    }
}
