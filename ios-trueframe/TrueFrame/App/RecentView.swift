import SwiftUI

/// Lists the locally-stored provenance of previously corrected photos (from
/// Documents/Provenance). Read-only and fully accessible.
struct RecentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var items: [Item] = []

    struct Item: Identifiable {
        let id: String
        let date: Date
        let provenance: EditingProvenance
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text(settings.t("No corrected photos yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.date, style: .date).font(.headline)
                        Text("\(settings.t("Rotation")): \(rot(item.provenance))°   ·   \(settings.t("Cropped")): \(pct(item.provenance))%")
                            .font(.subheadline)
                        Text("\(settings.t("Generative")): \(item.provenance.generativeModelAlteredPixels ? "" : settings.t("None"))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(settings.t("Recent Photos"))
        .onAppear(perform: load)
    }

    private func rot(_ p: EditingProvenance) -> String { String(format: "%.1f", p.rotationDegrees) }
    private func pct(_ p: EditingProvenance) -> String { String(format: "%.1f", p.croppedAreaFraction * 100) }

    private func load() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = dir.appendingPathComponent("Provenance", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoded: [Item] = files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let prov = try? JSONDecoder().decode(EditingProvenance.self, from: data) else { return nil }
            // Timestamp is encoded in the filename: provenance-<epoch>.json
            let ts = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "provenance-", with: "")
            let date = Date(timeIntervalSince1970: TimeInterval(ts) ?? 0)
            return Item(id: url.lastPathComponent, date: date, provenance: prov)
        }
        items = decoded.sorted { $0.date > $1.date }
    }
}
