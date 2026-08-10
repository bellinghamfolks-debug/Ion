import Foundation
import CoreVideo

/// Fast, allocation-light analysis of a preview frame's luma (Y) plane:
/// sharpness (Laplacian variance), exposure (histogram), lens obstruction, and
/// a rough sky/ground split. Runs on the video queue, on a downsampled grid so
/// it stays well under the per-frame budget.
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
            return Result(sharpness: .sharp, exposure: .good, obstruction: .init(), skyFraction: 0, groundFraction: 0)
        }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bpr = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let cols = min(targetCols, w), rows = min(targetRows, h)
        guard cols > 4, rows > 4 else {
            return Result(sharpness: .sharp, exposure: .good, obstruction: .init(), skyFraction: 0, groundFraction: 0)
        }
        let sx = w / cols, sy = h / rows

        // Sample into a small grid.
        var grid = [Int](repeating: 0, count: cols * rows)
        var hist = [Int](repeating: 0, count: 256)
        var sum = 0
        for r in 0..<rows {
            let srcRow = (r * sy) * bpr
            for c in 0..<cols {
                let v = Int(ptr[srcRow + c * sx])
                grid[r * cols + c] = v
                hist[v] += 1
                sum += v
            }
        }
        let n = cols * rows
        let mean = Double(sum) / Double(n)

        // --- Sharpness: variance of a 4-neighborhood Laplacian ---
        var lapSum = 0.0, lapSqSum = 0.0, lapN = 0
        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let i = r * cols + c
                let lap = 4 * grid[i] - grid[i - 1] - grid[i + 1] - grid[i - cols] - grid[i + cols]
                let d = Double(lap)
                lapSum += d; lapSqSum += d * d; lapN += 1
            }
        }
        let lapMean = lapN > 0 ? lapSum / Double(lapN) : 0
        let lapVar = lapN > 0 ? max(0, lapSqSum / Double(lapN) - lapMean * lapMean) : 0
        let sharpness: Sharpness
        switch lapVar {
        case let v where v >= 220: sharpness = .sharp
        case let v where v >= 90:  sharpness = .slightlySoft
        case let v where v >= 25:  sharpness = .blurry
        default:                   sharpness = .severelyBlurry
        }

        // --- Exposure: mean + clipping fractions ---
        let darkClip = Double(hist[0...12].reduce(0, +)) / Double(n)
        let brightClip = Double(hist[243...255].reduce(0, +)) / Double(n)
        let exposure: ExposureState
        if mean < 35 { exposure = .veryDark }
        else if brightClip > 0.28 { exposure = .overexposed }
        else if mean < 70 { exposure = .dark }
        else if mean > 200 { exposure = .bright }
        else { exposure = .good }
        _ = darkClip

        // --- Obstruction: a corner/region that is very dark AND very flat ---
        let obstruction = detectObstruction(grid: grid, cols: cols, rows: rows)

        // --- Sky vs ground (rough): top band bright, bottom band darker ---
        let (sky, ground) = skyGround(grid: grid, cols: cols, rows: rows)

        return Result(sharpness: sharpness, exposure: exposure, obstruction: obstruction,
                      skyFraction: sky, groundFraction: ground)
    }

    private func detectObstruction(grid: [Int], cols: Int, rows: Int) -> ObstructionResult {
        // Evaluate the four quadrants; a covered lens region is both dark and
        // almost texture-free.
        func quad(_ r0: Int, _ r1: Int, _ c0: Int, _ c1: Int) -> (mean: Double, varr: Double) {
            var s = 0.0, sq = 0.0, k = 0
            for r in r0..<r1 { for c in c0..<c1 {
                let v = Double(grid[r * cols + c]); s += v; sq += v * v; k += 1
            } }
            let m = k > 0 ? s / Double(k) : 0
            return (m, k > 0 ? max(0, sq / Double(k) - m * m) : 0)
        }
        let hr = rows / 2, hc = cols / 2
        let regions: [(ObstructionRegion, (mean: Double, varr: Double))] = [
            (.upperLeft, quad(0, hr, 0, hc)), (.upperRight, quad(0, hr, hc, cols)),
            (.lowerLeft, quad(hr, rows, 0, hc)), (.lowerRight, quad(hr, rows, hc, cols)),
        ]
        for (region, q) in regions where q.mean < 28 && q.varr < 18 {
            return ObstructionResult(isObstructed: true, region: region, confidence: 0.8)
        }
        return ObstructionResult()
    }

    private func skyGround(grid: [Int], cols: Int, rows: Int) -> (Double, Double) {
        let topRows = rows / 3, botStart = rows - rows / 3
        var topBright = 0, topN = 0, botDark = 0, botN = 0
        for r in 0..<topRows { for c in 0..<cols { if grid[r * cols + c] > 195 { topBright += 1 }; topN += 1 } }
        for r in botStart..<rows { for c in 0..<cols { if grid[r * cols + c] < 110 { botDark += 1 }; botN += 1 } }
        let sky = topN > 0 ? Double(topBright) / Double(topN) : 0
        let ground = botN > 0 ? Double(botDark) / Double(botN) : 0
        return (sky, ground)
    }
}
