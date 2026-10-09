import CoreImage.CIFilterBuiltins
import SwiftUI

/// How full the cup will be: the drink's volume against its vessel. The
/// value is spoken; the bar is a picture of the same number.
struct CupFillGauge: View {
    let recipe: Recipe

    static func capacity(_ vessel: Vessel) -> Int {
        switch vessel {
        case .espressoCup: return 90
        case .cup: return 220
        case .teaCup: return 300
        case .tallGlass: return 330
        case .mug: return 350
        case .iceGlass: return 400
        case .travelMug: return 450
        case .pot: return 1000
        }
    }

    var body: some View {
        let capacity = recipe.toGo ? Self.capacity(.travelMug) : Self.capacity(recipe.spec.vessel)
        let fraction = min(1.2, Double(recipe.approximateVolumeML) / Double(capacity))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("fill.title"), systemImage: "cup.and.saucer")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(L("unit.percent", Int(min(fraction, 1.2) * 100)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(fraction > 1 ? Theme.danger : Theme.accent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule().fill(fraction > 1 ? Theme.danger : Theme.accent)
                        .frame(width: geometry.size.width * min(1, fraction))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            if fraction > 1 {
                Text(L("fill.overflow")).font(.footnote).foregroundStyle(Theme.danger)
            }
        }
        .padding(14)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("fill.title"))
        .accessibilityValue(L("fill.spoken", recipe.approximateVolumeML, capacity, Int(min(fraction, 1.2) * 100)))
    }
}

/// Origin, coffee-to-milk ratio and the right cup.
struct DrinkKnowledgeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("knowledge.title"))
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            row(L("knowledge.origin"), DrinkKnowledge.origin(recipe.beverage), symbol: "globe")
            if let ratio = DrinkKnowledge.ratio(recipe) { row(L("knowledge.ratio"), ratio, symbol: "chart.pie") }
            row(L("knowledge.cup"), DrinkKnowledge.vessel(recipe.beverage), symbol: "cup.and.saucer")
            row(L("caffeine.title"), L("caffeine.estimate", CaffeineEstimator.milligrams(for: recipe)), symbol: "bolt.heart")
        }
        .padding(16)
        .card()
    }

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(value).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Recipes travel as a coffeeaccess://recipe link (and a QR code for it);
/// opening the link offers to add the recipe to the favorites.
enum RecipeShare {
    static func url(for recipe: Recipe) -> URL? {
        var copy = recipe.normalized()
        copy.id = UUID()
        guard let data = try? JSONEncoder().encode(copy) else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = CoffeeLink.scheme
        components.host = "recipe"
        components.queryItems = [URLQueryItem(name: "d", value: encoded)]
        return components.url
    }

    static func recipe(from url: URL) -> Recipe? {
        guard url.scheme == CoffeeLink.scheme, url.host == "recipe",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), data.count < 4_000,
              var recipe = try? JSONDecoder().decode(Recipe.self, from: data) else { return nil }
        recipe.id = UUID()
        recipe.customName = String(recipe.customName.prefix(30))
        return recipe.normalized()
    }

    static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct ShareRecipeButton: View {
    let recipe: Recipe
    @State var showingQR = false

    var body: some View {
        if let url = RecipeShare.url(for: recipe) {
            HStack(spacing: 12) {
                ShareLink(item: url, subject: Text(recipe.displayName), message: Text(L("share.message", recipe.spokenSummary))) {
                    Label(L("share.recipe"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button { showingQR = true } label: { Label(L("share.qr"), systemImage: "qrcode") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .sheet(isPresented: $showingQR) {
                VStack(spacing: 20) {
                    Text(recipe.displayName).font(.display(.title2, weight: .semibold))
                    if let image = RecipeShare.qrCode(for: url) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .accessibilityLabel(L("share.qr.label", recipe.displayName))
                    }
                    Text(L("share.qr.hint")).font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    Button(L("action.done")) { showingQR = false }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
                .presentationDetents([.medium, .large])
            }
        }
    }
}

/// "Add this recipe?" for a recipe opened from a shared link.
struct ImportedRecipeSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("share.import.title")).font(.display(.title2, weight: .semibold)).accessibilityAddTraits(.isHeader)
            RecipeRow(recipe: recipe)
            Text(recipe.spokenSummary).font(.body).foregroundStyle(Theme.textSecondary)
            Button(L("share.import.add")) {
                model.updateData { _ = $0.saveFavorite(recipe) }
                Announcer.shared.announce(L("announce.favoriteSaved", recipe.displayName))
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(L("action.cancel"), role: .cancel) { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
