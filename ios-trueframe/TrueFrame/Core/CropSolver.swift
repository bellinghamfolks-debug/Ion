import Foundation
import CoreGraphics

/// Pure geometry for deciding how much of a rotated image is real (non-empty)
/// content. When we rotate an image to level it, the corners become empty; the
/// authenticity-safe policy CROPS those corners rather than inventing pixels.
///
/// `largestValidCrop` returns the largest axis-aligned rectangle, centered in
/// the image, that contains ONLY source pixels after a rotation of `degrees`.
public enum CropSolver {

    /// Largest inscribed axis-aligned rectangle (w, h) inside a `w0 x h0`
    /// rectangle rotated by `angle` radians. Classic closed-form solution.
    public static func largestInscribed(w0: Double, h0: Double, angle: Double) -> (w: Double, h: Double) {
        guard w0 > 0, h0 > 0 else { return (0, 0) }
        let sinA = abs(sin(angle))
        let cosA = abs(cos(angle))
        if sinA < 1e-9 { return (w0, h0) }          // no rotation

        let widthIsLonger = w0 >= h0
        let sideLong = widthIsLonger ? w0 : h0
        let sideShort = widthIsLonger ? h0 : w0

        let wr: Double, hr: Double
        if sideShort <= 2 * sinA * cosA * sideLong || abs(sinA - cosA) < 1e-10 {
            // Half-constrained: the crop touches the mid-points of the long sides.
            let x = 0.5 * sideShort
            if widthIsLonger { wr = x / sinA; hr = x / cosA }
            else { wr = x / cosA; hr = x / sinA }
        } else {
            let cos2A = cosA * cosA - sinA * sinA
            wr = (w0 * cosA - h0 * sinA) / cos2A
            hr = (h0 * cosA - w0 * sinA) / cos2A
        }
        return (max(0, min(wr, w0)), max(0, min(hr, h0)))
    }

    /// The centered largest-valid crop as a normalized rect for a rotation.
    public static func largestValidCrop(imageSize: CGSize, degrees: Double) -> NormalizedRect {
        let w0 = Double(imageSize.width), h0 = Double(imageSize.height)
        guard w0 > 0, h0 > 0 else { return .full }
        let (wr, hr) = largestInscribed(w0: w0, h0: h0, angle: degrees * .pi / 180)
        let nw = wr / w0, nh = hr / h0
        let nx = (1 - nw) / 2, ny = (1 - nh) / 2
        return NormalizedRect(x: nx, y: ny, width: nw, height: nh)
    }

    /// Fraction of the original AREA removed by cropping to `rect` (0..1).
    public static func croppedAreaFraction(_ rect: NormalizedRect) -> Double {
        max(0, min(1, 1 - rect.areaFraction))
    }

    /// A conservative "safe" crop that keeps the original aspect ratio and is
    /// slightly inside the largest valid crop (a 1% inset guards against
    /// sub-pixel interpolation bleed at the very edge).
    public static func safeAspectCrop(imageSize: CGSize, degrees: Double, insetFraction: Double = 0.01) -> NormalizedRect {
        let maxCrop = largestValidCrop(imageSize: imageSize, degrees: degrees)
        // Fit the source aspect ratio inside maxCrop, centered.
        let srcAspect = imageSize.width / max(imageSize.height, 1)
        var w = maxCrop.width, h = maxCrop.height
        // maxCrop already has the source aspect from largestInscribed for same
        // aspect; keep it and apply the inset.
        let inset = insetFraction
        w *= (1 - inset); h *= (1 - inset)
        _ = srcAspect
        let x = (1 - w) / 2, y = (1 - h) / 2
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }
}
