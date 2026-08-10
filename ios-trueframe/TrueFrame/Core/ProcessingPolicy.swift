import Foundation

/// The processing policy that governs whether generative image editing is
/// permitted in a given workflow. The standard camera-correction workflow is
/// always `.authenticitySafe`.
public enum ProcessingPolicy: String, Codable, Sendable {
    /// No generative model may touch pixels. Only deterministic geometric and
    /// (optionally, explicitly enabled) conservative tonal operations. Every
    /// output pixel originates from the source, except normal interpolation for
    /// geometric transforms. This is the default for the main "Fix Photo" flow.
    case authenticitySafe

    /// Traditional, non-generative enhancement beyond geometry (e.g. classical
    /// denoise / sharpen / white balance). Still NO generative synthesis.
    case enhancedNonGenerative

    /// Reserved for a future, clearly-separated, opt-in generative feature. It
    /// must never be reachable from the standard correction workflow.
    case generativeExperimental

    /// Whether this policy allows any generative pixel synthesis.
    public var allowsGenerative: Bool { self == .generativeExperimental }

    /// Whether this policy allows non-geometric (but still non-generative) tonal
    /// operations such as classical denoise/sharpen.
    public var allowsTonalOperations: Bool { self != .authenticitySafe }
}

/// The classes of image operation the app can perform, tagged by whether they
/// are generative. `AuthenticityGuard` uses these tags to enforce policy.
public enum ImageOperationKind: String, Codable, Sendable {
    // --- Deterministic geometry (authenticity-safe) ---
    case rotate, horizonLevel, perspectiveCorrect, keystoneCorrect, crop
    case translate, scale, lensDistortionCorrect, exifOrientationCorrect
    // --- Conservative, non-generative tonal (opt-in only) ---
    case exposureAdjust, whiteBalanceAdjust, traditionalDenoise, traditionalSharpen
    // --- Generative (never allowed outside generativeExperimental) ---
    case generativeFill, diffusionReconstruct, outpaint, objectReplace, skyGenerate

    public var isGeometric: Bool {
        switch self {
        case .rotate, .horizonLevel, .perspectiveCorrect, .keystoneCorrect, .crop,
             .translate, .scale, .lensDistortionCorrect, .exifOrientationCorrect:
            return true
        default:
            return false
        }
    }

    public var isGenerative: Bool {
        switch self {
        case .generativeFill, .diffusionReconstruct, .outpaint, .objectReplace, .skyGenerate:
            return true
        default:
            return false
        }
    }

    public var isTonal: Bool {
        switch self {
        case .exposureAdjust, .whiteBalanceAdjust, .traditionalDenoise, .traditionalSharpen:
            return true
        default:
            return false
        }
    }
}
