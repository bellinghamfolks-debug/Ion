import SwiftUI

/// An original drawing of a bean-to-cup machine with a milk carafe: brushed
/// steel body, dark touch display, spout over a glass and a slotted drip
/// tray. Decorative only.
struct MachineIllustration: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: w * 0.86, height: h * 0.05)
                    .blur(radius: w * 0.02)
                    .position(x: w * 0.52, y: h * 0.93)

                // Body
                RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xC9CED5), Color(hex: 0xF3F4F6), Color(hex: 0xD3D7DD), Color(hex: 0xB7BCC4)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.04, style: .continuous).stroke(Color(hex: 0x8D939B), lineWidth: 1))
                    .frame(width: w * 0.64, height: h * 0.82)
                    .position(x: w * 0.56, y: h * 0.5)
                // Lid
                RoundedRectangle(cornerRadius: w * 0.03, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xA2A8B0), Color(hex: 0xD9DCE1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.66, height: h * 0.07)
                    .position(x: w * 0.56, y: h * 0.11)
                // Display
                RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                    .fill(Color(hex: 0x15171B))
                    .overlay(display(w: w, h: h))
                    .frame(width: w * 0.44, height: h * 0.18)
                    .position(x: w * 0.56, y: h * 0.27)
                ForEach(0..<2, id: \.self) { row in
                    ForEach(0..<2, id: \.self) { side in
                        Circle()
                            .stroke(Color(hex: 0x6E747C), lineWidth: 1.2)
                            .frame(width: w * 0.035)
                            .position(x: w * (side == 0 ? 0.3 : 0.82), y: h * (0.22 + CGFloat(row) * 0.1))
                    }
                }
                // Dark front column and spout
                RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3A3D43), Color(hex: 0x24262A)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.42, height: h * 0.38)
                    .position(x: w * 0.6, y: h * 0.6)
                RoundedRectangle(cornerRadius: w * 0.015, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xE6E8EB), Color(hex: 0xAEB3BA)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.15, height: h * 0.11)
                    .position(x: w * 0.6, y: h * 0.47)
                HStack(spacing: w * 0.03) {
                    Capsule().fill(Color(hex: 0x1A1B1E)).frame(width: w * 0.022, height: h * 0.03)
                    Capsule().fill(Color(hex: 0x1A1B1E)).frame(width: w * 0.022, height: h * 0.03)
                }
                .position(x: w * 0.6, y: h * 0.54)
                // Glass under the spout
                DrinkIllustration(beverage: .espresso, showsSteam: false, onDark: true)
                    .frame(width: w * 0.2)
                    .position(x: w * 0.6, y: h * 0.69)
                // Drip tray with slots
                RoundedRectangle(cornerRadius: w * 0.015, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xE4E6E9), Color(hex: 0xA9AEB5)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        HStack(spacing: w * 0.018) {
                            ForEach(0..<12, id: \.self) { _ in
                                Capsule().fill(Color(hex: 0x2A2C30)).frame(width: w * 0.012, height: h * 0.04)
                            }
                        }
                    )
                    .frame(width: w * 0.6, height: h * 0.075)
                    .position(x: w * 0.57, y: h * 0.82)
                RoundedRectangle(cornerRadius: w * 0.012, style: .continuous)
                    .fill(Color(hex: 0x1F2124))
                    .frame(width: w * 0.62, height: h * 0.035)
                    .position(x: w * 0.56, y: h * 0.88)
                carafe(w: w, h: h)
            }
        }
        .aspectRatio(0.82, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func display(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: h * 0.018) {
            Capsule().fill(Color(hex: 0x4D8DE0)).frame(width: w * 0.16, height: h * 0.01)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: w * 0.025) {
                ForEach([Theme.crema, Theme.milk, Theme.coffeeBrew, Theme.foam], id: \.self) { color in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: w * 0.055, height: h * 0.05)
                }
            }
            HStack(spacing: w * 0.025) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: w * 0.05, height: h * 0.006)
                }
            }
        }
        .padding(w * 0.03)
    }

    private func carafe(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Tube from carafe lid to the spout
            Path { path in
                path.move(to: CGPoint(x: w * 0.16, y: h * 0.44))
                path.addQuadCurve(to: CGPoint(x: w * 0.53, y: h * 0.46), control: CGPoint(x: w * 0.3, y: h * 0.36))
            }
            .stroke(Color(hex: 0xBFC4CA), style: StrokeStyle(lineWidth: w * 0.018, lineCap: .round))
            RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.85), Theme.milk], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                        .frame(height: h * 0.12)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
                .overlay(RoundedRectangle(cornerRadius: w * 0.04, style: .continuous).stroke(Color(hex: 0x9EA4AC), lineWidth: 1))
                .frame(width: w * 0.17, height: h * 0.38)
                .position(x: w * 0.13, y: h * 0.66)
            RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xD9DCE1), Color(hex: 0x9EA4AC)], startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.19, height: h * 0.05)
                .position(x: w * 0.13, y: h * 0.46)
        }
    }
}

/// An original drawing of a bag of coffee beans; the bag's colour follows
/// the roast. Decorative only.
struct BeanBagIllustration: View {
    var roast: BeanProfile.Roast = .medium

    private var bagColors: [Color] {
        switch roast {
        case .light: return [Color(hex: 0xD6B48C), Color(hex: 0xB08960)]
        case .medium: return [Color(hex: 0x2B3D5E), Color(hex: 0x18253D)]
        case .dark: return [Color(hex: 0x2E2724), Color(hex: 0x141110)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: w * 0.8, height: h * 0.05)
                    .blur(radius: w * 0.03)
                    .position(x: w * 0.5, y: h * 0.95)
                BagShape()
                    .fill(LinearGradient(colors: bagColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w * 0.72, height: h * 0.88)
                    .position(x: w * 0.5, y: h * 0.5)
                // Folded top seam
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: w * 0.66, height: h * 0.02)
                    .position(x: w * 0.5, y: h * 0.16)
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
                    .frame(width: w * 0.08)
                    .position(x: w * 0.5, y: h * 0.25)
                // Label
                RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                    .fill(Color(hex: 0xF7F1E8))
                    .frame(width: w * 0.46, height: h * 0.34)
                    .position(x: w * 0.5, y: h * 0.56)
                CoffeeBean()
                    .frame(width: w * 0.14, height: h * 0.1)
                    .rotationEffect(.degrees(-25))
                    .position(x: w * 0.5, y: h * 0.5)
                VStack(spacing: h * 0.02) {
                    Capsule().fill(Color(hex: 0x5B3421)).frame(width: w * 0.3, height: h * 0.014)
                    Capsule().fill(Color(hex: 0xB79E85)).frame(width: w * 0.2, height: h * 0.01)
                }
                .position(x: w * 0.5, y: h * 0.64)
                // Glossy edge
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: w * 0.04, height: h * 0.6)
                    .position(x: w * 0.22, y: h * 0.52)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private struct BagShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let top = rect.minY + rect.height * 0.08
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: top))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.05))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.05), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            path.addRect(CGRect(x: rect.minX + rect.width * 0.06, y: rect.minY, width: rect.width * 0.88, height: rect.height * 0.09))
            return path
        }
    }
}

/// A single roasted coffee bean with its centre crease.
struct CoffeeBean: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0x7A4524), Color(hex: 0x3A1D0D)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: max(rect.width, rect.height) * 0.7))
                Path { path in
                    path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
                    path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08),
                                  control1: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.midY - rect.height * 0.1),
                                  control2: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.midY + rect.height * 0.1))
                }
                .stroke(Color(hex: 0x1E0E05), style: StrokeStyle(lineWidth: max(1, rect.width * 0.08), lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Dark roasted-brown-to-navy backdrop with a few scattered beans, for
/// welcome screens, drink pages and the coffee profile. Decorative only.
struct HeroBackground: View {
    var beans = true

    private static let scatter: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, blur: CGFloat)] = [
        (0.08, 0.12, 0.13, -30, 0), (0.88, 0.08, 0.1, 40, 1.5), (0.78, 0.34, 0.16, 15, 0),
        (0.14, 0.52, 0.09, 70, 2), (0.92, 0.66, 0.12, -50, 0), (0.06, 0.86, 0.15, 20, 0.5),
        (0.6, 0.94, 0.11, -15, 2.5), (0.42, 0.04, 0.07, 80, 3),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .top, endPoint: .bottom)
                if beans {
                    ForEach(Array(Self.scatter.enumerated()), id: \.offset) { _, bean in
                        let side = proxy.size.width * bean.size
                        CoffeeBean()
                            .frame(width: side, height: side * 0.72)
                            .rotationEffect(.degrees(bean.angle))
                            .blur(radius: bean.blur)
                            .opacity(0.85)
                            .position(x: proxy.size.width * bean.x, y: proxy.size.height * bean.y)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
