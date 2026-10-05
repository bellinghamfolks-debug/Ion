import SwiftUI

/// An original, cut-away illustration of a drink in its glass: layers of
/// espresso, milk, foam, water or tea stacked as they settle in the cup.
/// `fill` (0...1) animates the cup filling while a drink is prepared.
/// Purely decorative: hidden from VoiceOver, which reads the drink name.
struct DrinkIllustration: View {
    let beverage: BeverageID
    var fill: Double = 1
    var showsSteam = true
    var toGo = false

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var steamPhase = false

    var body: some View {
        let spec = beverage.spec
        let vessel = toGo && spec.supportsToGo ? Vessel.travelMug : spec.vessel
        GeometryReader { proxy in
            let size = proxy.size
            let frame = VesselGeometry(vessel: vessel, size: size)
            ZStack {
                if frame.hasSaucer {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                        .frame(width: frame.body.width * 1.45, height: size.height * 0.07)
                        .position(x: frame.body.midX, y: frame.body.maxY + size.height * 0.015)
                }
                if frame.hasHandle {
                    HandleShape()
                        .stroke(Theme.textSecondary.opacity(0.55), lineWidth: max(3, size.width * 0.035))
                        .frame(width: frame.body.width * 0.32, height: frame.body.height * 0.48)
                        .position(x: frame.body.maxX + frame.body.width * 0.1, y: frame.body.minY + frame.body.height * 0.42)
                }
                liquid(spec: spec, frame: frame)
                    .clipShape(VesselShape(vessel: vessel).path(in: frame.body))
                VesselShape(vessel: vessel)
                    .path(in: frame.body)
                    .stroke(Theme.textSecondary.opacity(0.7), lineWidth: max(1.5, size.width * 0.018))
                if vessel == .travelMug {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.textSecondary.opacity(0.75))
                        .frame(width: frame.body.width * 1.06, height: frame.body.height * 0.1)
                        .position(x: frame.body.midX, y: frame.body.minY - frame.body.height * 0.02)
                }
                if showsSteam, !spec.isCold, fill > 0.6, vessel != .travelMug {
                    steam(frame: frame)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { steamPhase = true } }
    }

    private func liquid(spec: BeverageSpec, frame: VesselGeometry) -> some View {
        let interior = frame.body
        let layers = spec.layers.filter { $0 != .ice }
        let weights = layers.map(Self.weight)
        let total = max(weights.reduce(0, +), 0.01)
        let usable = interior.height * frame.fillRatio * min(max(fill, 0), 1)
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ForEach(Array(layers.enumerated().reversed()), id: \.offset) { index, layer in
                    Rectangle()
                        .fill(Self.color(layer).gradient)
                        .frame(height: usable * weights[index] / total)
                }
            }
            .frame(width: interior.width, height: interior.height, alignment: .bottom)
            if spec.layers.contains(.ice) {
                IceCubes()
                    .frame(width: interior.width, height: interior.height * 0.55)
                    .frame(width: interior.width, height: interior.height, alignment: .bottom)
                    .padding(.bottom, interior.height * 0.05)
            }
        }
        .frame(width: interior.width, height: interior.height)
        .position(x: interior.midX, y: interior.midY)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: fill)
    }

    private func steam(frame: VesselGeometry) -> some View {
        HStack(spacing: frame.body.width * 0.14) {
            ForEach(0..<3, id: \.self) { index in
                SteamWisp()
                    .stroke(Theme.textSecondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: frame.body.width * 0.12, height: frame.body.height * 0.36)
                    .offset(y: steamPhase ? -6 : 2)
                    .opacity(steamPhase ? 0.3 : 0.85)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever().delay(Double(index) * 0.35),
                        value: steamPhase
                    )
            }
        }
        .position(x: frame.body.midX, y: frame.body.minY - frame.body.height * 0.24)
    }

    static func weight(_ layer: DrinkLayer) -> CGFloat {
        switch layer {
        case .espresso: return 0.28
        case .coffee: return 0.7
        case .crema: return 0.07
        case .milk: return 0.5
        case .foam: return 0.22
        case .water: return 0.45
        case .tea: return 0.8
        case .ice: return 0
        }
    }

    static func color(_ layer: DrinkLayer) -> Color {
        switch layer {
        case .espresso: return Theme.espresso
        case .coffee: return Theme.coffeeBrew
        case .crema: return Theme.crema
        case .milk: return Theme.milk
        case .foam: return Theme.foam
        case .water: return Theme.water
        case .tea: return Theme.tea
        case .ice: return Theme.ice
        }
    }
}

/// Where the vessel sits inside the illustration's square.
struct VesselGeometry {
    let body: CGRect
    let fillRatio: CGFloat
    let hasHandle: Bool
    let hasSaucer: Bool

    init(vessel: Vessel, size: CGSize) {
        let w = size.width, h = size.height
        func rect(width: CGFloat, height: CGFloat, bottom: CGFloat) -> CGRect {
            CGRect(x: (w - w * width) / 2 - ([.tallGlass, .iceGlass, .travelMug].contains(vessel) ? 0 : w * 0.04),
                   y: h * bottom - h * height, width: w * width, height: h * height)
        }
        switch vessel {
        case .espressoCup:
            body = rect(width: 0.4, height: 0.3, bottom: 0.86); fillRatio = 0.7; hasHandle = true; hasSaucer = true
        case .cup:
            body = rect(width: 0.56, height: 0.42, bottom: 0.86); fillRatio = 0.86; hasHandle = true; hasSaucer = true
        case .teaCup:
            body = rect(width: 0.62, height: 0.32, bottom: 0.86); fillRatio = 0.82; hasHandle = true; hasSaucer = true
        case .mug:
            body = rect(width: 0.5, height: 0.56, bottom: 0.9); fillRatio = 0.86; hasHandle = true; hasSaucer = false
        case .tallGlass:
            body = rect(width: 0.36, height: 0.72, bottom: 0.92); fillRatio = 0.9; hasHandle = false; hasSaucer = false
        case .iceGlass:
            body = rect(width: 0.48, height: 0.6, bottom: 0.9); fillRatio = 0.88; hasHandle = false; hasSaucer = false
        case .travelMug:
            body = rect(width: 0.38, height: 0.66, bottom: 0.92); fillRatio = 0.9; hasHandle = false; hasSaucer = false
        case .pot:
            body = rect(width: 0.5, height: 0.66, bottom: 0.92); fillRatio = 0.85; hasHandle = true; hasSaucer = false
        }
    }
}

struct VesselShape: Shape {
    let vessel: Vessel

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let taper: CGFloat
        let bottomRadius: CGFloat
        switch vessel {
        case .espressoCup, .cup, .teaCup: taper = 0.14; bottomRadius = rect.height * 0.32
        case .mug, .travelMug: taper = 0.02; bottomRadius = rect.width * 0.08
        case .pot: taper = -0.06; bottomRadius = rect.width * 0.12
        case .tallGlass: taper = 0.06; bottomRadius = rect.width * 0.06
        case .iceGlass: taper = 0.1; bottomRadius = rect.width * 0.05
        }
        let inset = rect.width * taper
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - bottomRadius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset - bottomRadius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset + bottomRadius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY - bottomRadius),
                          control: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct HandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12),
                      control1: CGPoint(x: rect.maxX * 1.1, y: rect.minY - rect.height * 0.1),
                      control2: CGPoint(x: rect.maxX * 1.1, y: rect.maxY + rect.height * 0.1))
        return path
    }
}

struct SteamWisp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX - rect.width * 0.4, y: rect.maxY - rect.height * 0.35),
                      control2: CGPoint(x: rect.maxX + rect.width * 0.4, y: rect.minY + rect.height * 0.35))
        return path
    }
}

struct IceCubes: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width * 0.34, proxy.size.height * 0.45)
            ZStack {
                cube(side).rotationEffect(.degrees(-12)).position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.72)
                cube(side).rotationEffect(.degrees(16)).position(x: proxy.size.width * 0.68, y: proxy.size.height * 0.64)
                cube(side * 0.9).rotationEffect(.degrees(6)).position(x: proxy.size.width * 0.48, y: proxy.size.height * 0.3)
            }
        }
    }

    private func cube(_ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
            .fill(Theme.ice.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2))
            .frame(width: side, height: side)
    }
}
