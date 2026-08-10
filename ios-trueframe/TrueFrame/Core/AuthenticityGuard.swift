import Foundation

/// Central gatekeeper that prevents accidental generative processing in
/// protected workflows, and records exactly what was done to an image.
///
/// Every image operation is routed through `authorize(_:)` before it runs. In
/// `.authenticitySafe` mode a generative operation is a programmer error and is
/// refused (and, in DEBUG, trapped) — the app cannot silently synthesize pixels.
public struct AuthenticityGuard {

    public let policy: ProcessingPolicy

    public init(policy: ProcessingPolicy = .authenticitySafe) {
        self.policy = policy
    }

    public enum Violation: Error, CustomStringConvertible {
        case generativeInProtectedMode(ImageOperationKind)
        case tonalInAuthenticitySafe(ImageOperationKind)

        public var description: String {
            switch self {
            case .generativeInProtectedMode(let k):
                return "Blocked generative operation \(k.rawValue) in \(ProcessingPolicy.authenticitySafe.rawValue) mode."
            case .tonalInAuthenticitySafe(let k):
                return "Blocked non-geometric operation \(k.rawValue) in authenticity-safe mode."
            }
        }
    }

    /// Throws if `kind` is not permitted under the current policy. Callers in a
    /// protected workflow treat a throw as fatal — the app refuses to produce a
    /// synthesized image rather than silently doing so.
    public func authorize(_ kind: ImageOperationKind) throws {
        if kind.isGenerative && !policy.allowsGenerative {
            throw Violation.generativeInProtectedMode(kind)
        }
        if kind.isTonal && !policy.allowsTonalOperations {
            throw Violation.tonalInAuthenticitySafe(kind)
        }
    }

    /// The user-facing guarantee shown after a protected correction.
    public var safeStatement: String {
        "Authenticity Safe: No generative image editing was used."
    }
}

/// A machine-readable, locally-stored record of everything done to a photo.
/// Persisted alongside the corrected copy so provenance is auditable.
public struct EditingProvenance: Codable, Equatable, Sendable {
    public var policy: ProcessingPolicy
    public var rotationDegrees: Double
    public var perspectiveVerticalDegrees: Double
    public var perspectiveHorizontalDegrees: Double
    public var cropRectNormalized: NormalizedRect          // in the source's 0..1 space
    public var croppedAreaFraction: Double                 // 0..1 of original area removed
    public var appliedOperations: [ImageOperationKind]
    public var aiAnalysisPerformed: Bool                   // description/OCR ran (read-only)
    public var generativeModelAlteredPixels: Bool          // must stay false in safe mode

    public init(policy: ProcessingPolicy = .authenticitySafe,
                rotationDegrees: Double = 0,
                perspectiveVerticalDegrees: Double = 0,
                perspectiveHorizontalDegrees: Double = 0,
                cropRectNormalized: NormalizedRect = .full,
                croppedAreaFraction: Double = 0,
                appliedOperations: [ImageOperationKind] = [],
                aiAnalysisPerformed: Bool = false,
                generativeModelAlteredPixels: Bool = false) {
        self.policy = policy
        self.rotationDegrees = rotationDegrees
        self.perspectiveVerticalDegrees = perspectiveVerticalDegrees
        self.perspectiveHorizontalDegrees = perspectiveHorizontalDegrees
        self.cropRectNormalized = cropRectNormalized
        self.croppedAreaFraction = croppedAreaFraction
        self.appliedOperations = appliedOperations
        self.aiAnalysisPerformed = aiAnalysisPerformed
        self.generativeModelAlteredPixels = generativeModelAlteredPixels
    }

    /// The disclosure line for the processing record.
    public var generativeDisclosure: String {
        generativeModelAlteredPixels ? "Generative modification: Yes." : "Generative modification: None."
    }
}

/// A rectangle in normalized 0..1 image coordinates (origin top-left), so it is
/// independent of the pixel resolution.
public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    public var areaFraction: Double { max(0, width) * max(0, height) }
}
