import Foundation
import CoreGraphics

/// Pure geometry for cropping empty corners created by rotation.
public enum CropSolver {

    public static func largestInscribed(w0: Double,
                                        h0: Double,
                                        angle: Double) -> (w: Double, h: Double) {
        guard w0 > 0, h0 > 0 else { return (0, 0) }

        let sinAngle = abs(sin(angle))
        let cosAngle = abs(cos(angle))
        if sinAngle < 1e-9 { return (w0, h0) }

        let widthIsLonger = w0 >= h0
        let longSide = widthIsLonger ? w0 : h0
        let shortSide = widthIsLonger ? h0 : w0

        let width: Double
        let height: Double

        if shortSide <= 2 * sinAngle * cosAngle * longSide
            || abs(sinAngle - cosAngle) < 1e-10 {
            let halfShortSide = 0.5 * shortSide
            if widthIsLonger {
                width = halfShortSide / sinAngle
                height = halfShortSide / cosAngle
            } else {
                width = halfShortSide / cosAngle
                height = halfShortSide / sinAngle
            }
        } else {
            let cos2 = cosAngle * cosAngle - sinAngle * sinAngle
            width = (w0 * cosAngle - h0 * sinAngle) / cos2
            height = (h0 * cosAngle - w0 * sinAngle) / cos2
        }

        return (max(0, min(width, w0)),
                max(0, min(height, h0)))
    }

    public static func largestValidCrop(imageSize: CGSize,
                                        degrees: Double) -> NormalizedRect {
        let originalWidth = Double(imageSize.width)
        let originalHeight = Double(imageSize.height)
        guard originalWidth > 0, originalHeight > 0 else { return .full }

        let result = largestInscribed(w0: originalWidth,
                                      h0: originalHeight,
                                      angle: degrees * .pi / 180)
        let normalizedWidth = result.w / originalWidth
        let normalizedHeight = result.h / originalHeight
        return NormalizedRect(x: (1 - normalizedWidth) / 2,
                              y: (1 - normalizedHeight) / 2,
                              width: normalizedWidth,
                              height: normalizedHeight)
    }

    public static func croppedAreaFraction(_ rect: NormalizedRect) -> Double {
        max(0, min(1, 1 - rect.areaFraction))
    }

    /// Centered crop that stays inside the valid post-rotation region while
    /// preserving the source aspect ratio. In normalized source coordinates,
    /// preserving the source aspect ratio means using the same scale factor for
    /// width and height.
    public static func safeAspectCrop(imageSize: CGSize,
                                      degrees: Double,
                                      insetFraction: Double = 0.01) -> NormalizedRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .full }

        let maximum = largestValidCrop(imageSize: imageSize, degrees: degrees)
        let inset = min(0.25, max(0, insetFraction))
        let uniformScale = max(0, min(maximum.width, maximum.height) * (1 - inset))

        return NormalizedRect(x: (1 - uniformScale) / 2,
                              y: (1 - uniformScale) / 2,
                              width: uniformScale,
                              height: uniformScale)
    }
}
