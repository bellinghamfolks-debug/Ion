import SwiftUI

/// Local audit history for corrected copies saved by TrueFrame.
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
                ContentUnavailableView(
                    settings.t("No corrected photos yet."),
                    systemImage: "photo"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text(item.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.headline)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }

                        Text("\(settings.t("Rotation")): \(rotation(item.provenance))°")
                            .font(.subheadline)

                        Text("\(settings.t("Cropped")): \(croppedPercent(item.provenance))%")
                            .font(.subheadline)

                        Text("\(settings.t("Generative")): \(item.provenance.generativeModelAlteredPixels ? settings.t("Yes") : settings.t("None"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(settings.t("Recent Photos"))
        .onAppear(perform: load)
    }

    private func rotation(_ provenance: EditingProvenance) -> String {
        String(format: "%.1f", provenance.rotationDegrees)
    }

    private func croppedPercent(_ provenance: EditingProvenance) -> String {
        String(format: "%.1f", provenance.croppedAreaFraction * 100)
    }

    private func load() {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else {
            return
        }

        let folder = directory.appendingPathComponent("Provenance", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []

        let decoded: [Item] = files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let provenance = try? JSONDecoder().decode(EditingProvenance.self, from: data) else {
                return nil
            }

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileDate = attributes?[.creationDate] as? Date
            let fallbackDate = attributes?[.modificationDate] as? Date
            let date = fileDate ?? fallbackDate ?? .distantPast

            return Item(id: url.lastPathComponent,
                        date: date,
                        provenance: provenance)
        }

        items = decoded.sorted { $0.date > $1.date }
    }
}
