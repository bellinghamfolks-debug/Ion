import Foundation
import CoreVideo

/// Fast luminance analysis for live capture.
/// Uses relative scene statistics where possible so a white wall is not treated
/// as "sky" and a naturally dark room is not automatically treated as a covered
/// lens.
public struct FrameAnalyzer {

    public struct Result: Sendable {
        public var sharpness: Sharpness
        public var exposure: ExposureState
        public var obstruction: ObstructionResult
        public var skyFraction: Double
        public var groundFraction: Double
    }

    public var targetCols = 160
    public var targetRows = 120

    public func analyze(_ buffer: CVPixelBuffer) -> Result {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return Result(sharpness: .severelyBlurry,
                          exposure: .veryDark,
                          obstruction: .init(),
                          skyFraction: 0,
                          groundFraction: 0)
        }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let cols = min(targetCols, width)
        let rows = min(targetRows, height)
        guard cols > 4, rows > 4 else {
            return Result(sharpness: .severelyBlurry,
                          exposure: .veryDark,
                          obstruction: .init(),
                          skyFraction: 0,
                          groundFraction: 0)
        }

        let stepX = max(1, width / cols)
        let stepY = max(1, height / rows)

        var grid = [Int](repeating: 0, count: cols * rows)
        var histogram = [Int](repeating: 0, count: 256)
        var sum = 0

        for row in 0..<rows {
            let sourceRow = min(height - 1, row * stepY) * bytesPerRow
            for col in 0..<cols {
                let sourceCol = min(width - 1, col * stepX)
                let value = Int(ptr[sourceRow + sourceCol])
                grid[row * cols + col] = value
                histogram[value] += 1
                sum += value
            }
        }

        let count = cols * rows
        let mean = Double(sum) / Double(count)
        let sharpness = classifySharpness(grid: grid, cols: cols, rows: rows)
        let exposure = classifyExposure(histogram: histogram, mean: mean, count: count)
        let obstruction = detectObstruction(grid: grid, cols: cols, rows: rows)
        let sceneBands = classifySceneBands(grid: grid, cols: cols, rows: rows)

        return Result(sharpness: sharpness,
                      exposure: exposure,
                      obstruction: obstruction,
                      skyFraction: sceneBands.sky,
                      groundFraction: sceneBands.ground)
    }

    private func classifySharpness(grid: [Int], cols: Int, rows: Int) -> Sharpness {
        var laplacianSum = 0.0
        var laplacianSquareSum = 0.0
        var sampleCount = 0

        for row in 1..<(rows - 1) {
            for col in 1..<(cols - 1) {
                let index = row * cols + col
                let laplacian = 4 * grid[index]
                    - grid[index - 1]
                    - grid[index + 1]
                    - grid[index - cols]
                    - grid[index + cols]
                let value = Double(laplacian)
                laplacianSum += value
                laplacianSquareSum += value * value
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return .severelyBlurry }
        let average = laplacianSum / Double(sampleCount)
        let variance = max(0,
                           laplacianSquareSum / Double(sampleCount)
                           - average * average)

        switch variance {
        case 220...: return .sharp
        case 90..<220: return .slightlySoft
        case 25..<90: return .blurry
        default: return .severelyBlurry
        }
    }

    private func classifyExposure(histogram: [Int], mean: Double, count: Int) -> ExposureState {
        let darkClip = Double(histogram[0...12].reduce(0, +)) / Double(count)
        let brightClip = Double(histogram[243...255].reduce(0, +)) / Double(count)

        if mean < 32 || darkClip > 0.62 { return .veryDark }
        if brightClip > 0.28 { return .overexposed }
        if mean < 68 { return .dark }
        if mean > 205 { return .bright }
        return .good
    }

    private struct RegionStats {
        var mean: Double
        var variance: Double
        var brightFraction: Double
        var darkFraction: Double
    }

    private func stats(grid: [Int], cols: Int,
                       rowRange: Range<Int>, colRange: Range<Int>) -> RegionStats {
        var sum = 0.0
        var squareSum = 0.0
        var bright = 0
        var dark = 0
        var count = 0

        for row in rowRange {
            for col in colRange {
                let value = Double(grid[row * cols + col])
                sum += value
                squareSum += value * value
                if value > 195 { bright += 1 }
                if value < 110 { dark += 1 }
                count += 1
            }
        }

        guard count > 0 else {
            return RegionStats(mean: 0, variance: 0, brightFraction: 0, darkFraction: 0)
        }

        let mean = sum / Double(count)
        let variance = max(0, squareSum / Double(count) - mean * mean)
        return RegionStats(mean: mean,
                           variance: variance,
                           brightFraction: Double(bright) / Double(count),
                           darkFraction: Double(dark) / Double(count))
    }

    private func detectObstruction(grid: [Int], cols: Int, rows: Int) -> ObstructionResult {
        let whole = stats(grid: grid,
                          cols: cols,
                          rowRange: 0..<rows,
                          colRange: 0..<cols)
        let halfRows = rows / 2
        let halfCols = cols / 2

        let regions: [(ObstructionRegion, RegionStats)] = [
            (.upperLeft, stats(grid: grid, cols: cols, rowRange: 0..<halfRows, colRange: 0..<halfCols)),
            (.upperRight, stats(grid: grid, cols: cols, rowRange: 0..<halfRows, colRange: halfCols..<cols)),
            (.lowerLeft, stats(grid: grid, cols: cols, rowRange: halfRows..<rows, colRange: 0..<halfCols)),
            (.lowerRight, stats(grid: grid, cols: cols, rowRange: halfRows..<rows, colRange: halfCols..<cols))
        ]

        let globalMean = max(1, whole.mean)
        let globalVariance = max(1, whole.variance)

        var best: (region: ObstructionRegion, confidence: Double)?
        for (region, regionStats) in regions {
            let relativeDarkness = clamp((globalMean - regionStats.mean) / globalMean)
            let relativeFlatness = clamp(1 - regionStats.variance / globalVariance)

            let absoluteDark = regionStats.mean < 42
            let relativelyDark = regionStats.mean < whole.mean * 0.58
            let sufficientlyFlat = regionStats.variance < max(35, whole.variance * 0.18)

            guard absoluteDark && relativelyDark && sufficientlyFlat else { continue }

            let confidence = clamp(0.55 + 0.27 * relativeDarkness + 0.23 * relativeFlatness)
            if best == nil || confidence > best!.confidence {
                best = (region, confidence)
            }
        }

        guard let best, best.confidence >= 0.78 else {
            return ObstructionResult()
        }
        return ObstructionResult(isObstructed: true,
                                 region: best.region,
                                 confidence: best.confidence)
    }

    /// Conservative sky/ground cues. A band is only considered dominant when
    /// it differs meaningfully from the middle of the image. This avoids the old
    /// behavior where a uniformly bright wall could be called sky.
    private func classifySceneBands(grid: [Int], cols: Int, rows: Int) -> (sky: Double, ground: Double) {
        let third = max(1, rows / 3)
        let top = stats(grid: grid, cols: cols,
                        rowRange: 0..<third, colRange: 0..<cols)
        let middle = stats(grid: grid, cols: cols,
                           rowRange: third..<min(rows, third * 2), colRange: 0..<cols)
        let bottom = stats(grid: grid, cols: cols,
                           rowRange: max(0, rows - third)..<rows, colRange: 0..<cols)

        let sky = top.mean >= 145
            && top.mean - middle.mean >= 18
            ? top.brightFraction : 0

        let ground = bottom.mean <= 125
            && middle.mean - bottom.mean >= 15
            ? bottom.darkFraction : 0

        return (sky, ground)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
