import Foundation
import CoreGraphics

/// Spoken directions for photographing a page without seeing the screen.
/// Pure logic: it takes the four corners of the document the camera found
/// (normalized 0...1, origin top-left, as the person holds the phone) and
/// says what to do next. The camera view only feeds it and speaks.
enum CaptureInstruction: Equatable, Sendable {
    case searching
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case closer
    case farther
    case holdSteady
    case ready

    @MainActor
    func spoken(_ l10n: L10n) -> String {
        switch self {
        case .searching: return l10n.t("لم تظهر الصفحة بعد. ضعها على سطح داكن ووجّه الكاميرا نحوها.",
                                       "No page detected yet. Place it on a dark surface and point the camera at it.")
        case .moveLeft: return l10n.t("حرّك الهاتف قليلًا لليسار", "Move the phone a little to the left")
        case .moveRight: return l10n.t("حرّك الهاتف قليلًا لليمين", "Move the phone a little to the right")
        case .moveUp: return l10n.t("حرّك الهاتف قليلًا نحو أعلى الصفحة", "Move the phone slightly toward the top of the page")
        case .moveDown: return l10n.t("حرّك الهاتف قليلًا نحو أسفل الصفحة", "Move the phone slightly toward the bottom of the page")
        case .closer: return l10n.t("قرّب الهاتف من الورقة", "Bring the phone closer to the page")
        case .farther: return l10n.t("أبعد الهاتف قليلًا عن الورقة لتظهر كاملة", "Move the phone slightly away from the page to fit it all in")
        case .holdSteady: return l10n.t("ثبّت الهاتف", "Hold the phone steady")
        case .ready: return l10n.t("الصفحة ظاهرة بالكامل. جارٍ التقاط الصورة", "The whole page is in view. Capturing now")
        }
    }
}

struct DocumentQuad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var boundingBox: CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Shoelace area, as a share of the whole frame.
    var area: CGFloat {
        let p = points
        var sum: CGFloat = 0
        for index in 0..<4 {
            let a = p[index], b = p[(index + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    var center: CGPoint {
        CGPoint(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
    }

    func maximumCornerShift(to other: DocumentQuad) -> CGFloat {
        zip(points, other.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 1
    }
}

enum CaptureGuidance {
    /// The page must fill at least this share of the frame to be legible.
    static let minimumArea: CGFloat = 0.28
    /// A corner closer than this to the frame edge is likely cut off.
    static let edgeMargin: CGFloat = 0.02
    /// How far off-centre the page may sit before asking to move.
    static let centreTolerance: CGFloat = 0.14

    static func instruction(for quad: DocumentQuad?) -> CaptureInstruction {
        guard let quad else { return .searching }
        let box = quad.boundingBox
        let touchesLeft = box.minX < edgeMargin
        let touchesRight = box.maxX > 1 - edgeMargin
        let touchesTop = box.minY < edgeMargin
        let touchesBottom = box.maxY > 1 - edgeMargin
        // Cut off on both sides: too close.
        if (touchesLeft && touchesRight) || (touchesTop && touchesBottom) { return .farther }
        // Cut off on one side: the camera must move toward that side.
        if touchesLeft { return .moveLeft }
        if touchesRight { return .moveRight }
        if touchesTop { return .moveUp }
        if touchesBottom { return .moveDown }
        if quad.area < minimumArea {
            let dx = quad.center.x - 0.5, dy = quad.center.y - 0.5
            if abs(dx) > centreTolerance || abs(dy) > centreTolerance {
                return abs(dx) >= abs(dy) ? (dx < 0 ? .moveLeft : .moveRight) : (dy < 0 ? .moveUp : .moveDown)
            }
            return .closer
        }
        return .ready
    }
}

/// Turns a stream of detections into calm speech: a direction is spoken only
/// when it changes or after a pause, and capture happens only after the page
/// has stayed in view and still for a moment.
struct CaptureStabilizer {
    var requiredStableFrames = 6
    var stillTolerance: CGFloat = 0.02
    var repeatInterval: TimeInterval = 3

    private(set) var stableFrames = 0
    private var lastQuad: DocumentQuad?
    private var lastSpoken: CaptureInstruction?
    private var lastSpokenAt: Date = .distantPast

    enum Output: Equatable {
        case none
        case speak(CaptureInstruction)
        case capture
    }

    mutating func update(quad: DocumentQuad?, now: Date = Date()) -> Output {
        var instruction = CaptureGuidance.instruction(for: quad)
        if instruction == .ready, let quad {
            if let lastQuad, quad.maximumCornerShift(to: lastQuad) <= stillTolerance {
                stableFrames += 1
            } else {
                stableFrames = 0
            }
            lastQuad = quad
            if stableFrames >= requiredStableFrames {
                stableFrames = 0
                lastSpoken = nil
                return .capture
            }
            // In view but still moving.
            if stableFrames == 0 { instruction = .holdSteady } else { return .none }
        } else {
            stableFrames = 0
            lastQuad = quad
        }
        if instruction != lastSpoken || now.timeIntervalSince(lastSpokenAt) >= repeatInterval {
            lastSpoken = instruction
            lastSpokenAt = now
            return .speak(instruction)
        }
        return .none
    }

    mutating func reset() {
        stableFrames = 0
        lastQuad = nil
        lastSpoken = nil
        lastSpokenAt = .distantPast
    }
}
