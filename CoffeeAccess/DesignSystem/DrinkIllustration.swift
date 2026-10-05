import SwiftUI
import UIKit

/// An original drawing of a drink in a double-walled glass: layers of
/// espresso, milk, foam, water or tea settle above a thick glass base, with
/// highlights on the glass and a soft shadow below. `fill` (0...1) animates
/// the glass filling while a drink is prepared.
/// Purely decorative: hidden from VoiceOver, which reads the drink name.
struct DrinkIllustration: View {
    let beverage: BeverageID
    var fill: Double = 1
    var showsSteam = true
    var toGo = false
    /// Lighter glass edges for dark backgrounds.
    var onDark = false

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var steamPhase = false

    var body: some View {
        let spec = beverage.spec
        let vessel = toGo && spec.supportsToGo ? Vessel.travelMug : spec.vessel
        GeometryReader { proxy in
            let size = proxy.size
            let frame = VesselGeometry(vessel: vessel, size: size)
            let edge = onDark ? Color.white.opacity(0.75) : Theme.textSecondary.opacity(0.55)
            let outline = VesselShape(vessel: vessel).path(in: frame.body)
            let inner = VesselShape(vessel: vessel).path(in: frame.interior)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(onDark ? 0.35 : 0.16))
                    .frame(width: frame.body.width * 1.15, height: max(4, size.height * 0.045))
                    .blur(radius: size.width * 0.02)
                    .position(x: frame.body.midX, y: frame.body.maxY + size.height * 0.01)
                if frame.hasHandle {
                    HandleShape()
                        .stroke(edge, style: StrokeStyle(lineWidth: max(2.5, size.width * 0.03), lineCap: .round))
                        .frame(width: frame.body.width * 0.3, height: frame.body.height * 0.46)
                        .position(x: frame.body.maxX + frame.body.width * 0.09, y: frame.body.minY + frame.body.height * 0.42)
                }
                outline.fill(
                    LinearGradient(colors: [Color.white.opacity(onDark ? 0.18 : 0.6), Color.white.opacity(onDark ? 0.06 : 0.22)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                liquid(spec: spec, frame: frame)
                    .clipShape(inner)
                inner.stroke(Color.white.opacity(0.55), lineWidth: max(1, size.width * 0.008))
                outline.stroke(edge, lineWidth: max(1.2, size.width * 0.013))
                highlights(frame: frame)
                    .clipShape(outline)
                if vessel == .travelMug {
                    RoundedRectangle(cornerRadius: frame.body.width * 0.08, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x3A3F47), Color(hex: 0x1E2227)], startPoint: .top, endPoint: .bottom))
                        .frame(width: frame.body.width * 1.08, height: frame.body.height * 0.12)
                        .position(x: frame.body.midX, y: frame.body.minY)
                }
                if showsSteam, !spec.isCold, fill > 0.6, vessel != .travelMug {
                    steam(frame: frame, color: edge)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { steamPhase = true } }
    }

    private func liquid(spec: BeverageSpec, frame: VesselGeometry) -> some View {
        let interior = frame.interior
        let layers = spec.layers.filter { $0 != .ice }
        let weights = layers.map(Self.weight)
        let total = max(weights.reduce(0, +), 0.01)
        let usable = interior.height * frame.fillRatio * min(max(fill, 0), 1)
        let surface = interior.width * 0.13
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ForEach(Array(layers.enumerated().reversed()), id: \.offset) { index, layer in
                    Rectangle()
                        .fill(LinearGradient(colors: [Self.color(layer).blended(with: .white, amount: 0.12), Self.color(layer)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: usable * weights[index] / total)
                }
            }
            .frame(width: interior.width, height: interior.height, alignment: .bottom)
            if let top = layers.last, usable > surface {
                // The liquid's surface seen slightly from above.
                Ellipse()
                    .fill(Self.color(top).blended(with: .white, amount: 0.22))
                    .frame(width: interior.width * 1.02, height: surface)
                    .frame(width: interior.width, height: interior.height, alignment: .bottom)
                    .offset(y: -(usable - surface / 2))
            }
            if spec.layers.contains(.ice) {
                IceCubes()
                    .frame(width: interior.width, height: interior.height * 0.6)
                    .frame(width: interior.width, height: interior.height, alignment: .bottom)
                    .padding(.bottom, interior.height * 0.08)
            }
        }
        .frame(width: interior.width, height: interior.height)
        .position(x: interior.midX, y: interior.midY)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: fill)
    }

    private func highlights(frame: VesselGeometry) -> some View {
        let body = frame.body
        return ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: max(2, body.width * 0.055), height: body.height * 0.62)
                .position(x: body.minX + body.width * 0.17, y: body.minY + body.height * 0.42)
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: max(1.5, body.width * 0.03), height: body.height * 0.4)
                .position(x: body.maxX - body.width * 0.14, y: body.minY + body.height * 0.36)
        }
    }

    private func steam(frame: VesselGeometry, color: Color) -> some View {
        HStack(spacing: frame.body.width * 0.14) {
            ForEach(0..<3, id: \.self) { index in
                SteamWisp()
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: frame.body.width * 0.12, height: frame.body.height * 0.32)
                    .offset(y: steamPhase ? -6 : 2)
                    .opacity(steamPhase ? 0.3 : 0.85)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever().delay(Double(index) * 0.35),
                        value: steamPhase
                    )
            }
        }
        .position(x: frame.body.midX, y: frame.body.minY - frame.body.height * 0.22)
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

private extension Color {
    /// Blends toward another colour; used for the lighter top of each layer.
    func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t), blue: Double(b1 + (b2 - b1) * t))
    }
}

/// Where the glass sits inside the illustration's square. `interior` is the
/// space for the drink: inside the double wall, above the thick base.
struct VesselGeometry {
    let body: CGRect
    let interior: CGRect
    let fillRatio: CGFloat
    let hasHandle: Bool

    init(vessel: Vessel, size: CGSize) {
        let w = size.width, h = size.height
        let handled: Bool
        let width: CGFloat, height: CGFloat, bottom: CGFloat
        switch vessel {
        case .espressoCup: width = 0.42; height = 0.4; bottom = 0.9; fillRatio = 0.74; handled = false
        case .cup: width = 0.54; height = 0.5; bottom = 0.92; fillRatio = 0.86; handled = false
        case .teaCup: width = 0.56; height = 0.4; bottom = 0.9; fillRatio = 0.82; handled = true
        case .mug: width = 0.46; height = 0.62; bottom = 0.93; fillRatio = 0.86; handled = true
        case .tallGlass: width = 0.36; height = 0.8; bottom = 0.95; fillRatio = 0.9; handled = false
        case .iceGlass: width = 0.5; height = 0.68; bottom = 0.94; fillRatio = 0.9; handled = false
        case .travelMug: width = 0.38; height = 0.72; bottom = 0.95; fillRatio = 0.88; handled = false
        case .pot: width = 0.52; height = 0.7; bottom = 0.94; fillRatio = 0.85; handled = true
        }
        let shift: CGFloat = handled ? w * 0.04 : 0
        body = CGRect(x: (w - w * width) / 2 - shift, y: h * bottom - h * height, width: w * width, height: h * height)
        let side = body.width * 0.07
        let base = body.height * (vessel == .travelMug ? 0.05 : 0.13)
        interior = CGRect(x: body.minX + side, y: body.minY + body.height * 0.03,
                          width: body.width - side * 2, height: body.height * 0.97 - base)
        hasHandle = handled
    }
}

struct VesselShape: Shape {
    let vessel: Vessel

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let taper: CGFloat
        let bottomRadius: CGFloat
        switch vessel {
        case .espressoCup, .cup: taper = 0.1; bottomRadius = rect.height * 0.3
        case .teaCup: taper = 0.12; bottomRadius = rect.height * 0.32
        case .mug, .travelMug: taper = 0.03; bottomRadius = rect.width * 0.1
        case .pot: taper = -0.05; bottomRadius = rect.width * 0.14
        case .tallGlass: taper = 0.07; bottomRadius = rect.width * 0.1
        case .iceGlass: taper = 0.1; bottomRadius = rect.width * 0.09
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
            let side = min(proxy.size.width * 0.34, proxy.size.height * 0.42)
            ZStack {
                cube(side).rotationEffect(.degrees(-12)).position(x: proxy.size.width * 0.3, y: proxy.size.height * 0.72)
                cube(side).rotationEffect(.degrees(16)).position(x: proxy.size.width * 0.7, y: proxy.size.height * 0.62)
                cube(side * 0.9).rotationEffect(.degrees(6)).position(x: proxy.size.width * 0.48, y: proxy.size.height * 0.3)
            }
        }
    }

    private func cube(_ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.7), Theme.ice.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: side * 0.2, style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: 1.2))
            .frame(width: side, height: side)
    }
}
