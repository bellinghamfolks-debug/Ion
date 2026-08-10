import SwiftUI
import PhotosUI
import ImageIO
import CoreGraphics

/// Deliberately simple home screen: four large, clearly-labeled actions.
struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var importedImage: CGImage?
    @State private var showImportReview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                bigButton(settings.t("Take Photo"), systemImage: "camera.fill",
                          hint: settings.t("Opens the accessible camera with leveling and framing guidance.")) {
                    showCamera = true
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    label(settings.t("Import Photo"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                NavigationLink { RecentView() } label: {
                    label(settings.t("Recent Photos"), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)

                NavigationLink { SettingsView() } label: {
                    label(settings.t("Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("TrueFrame")
            .fullScreenCover(isPresented: $showCamera) {
                CameraView().environmentObject(settings)
            }
            .fullScreenCover(isPresented: $showImportReview) {
                if let cg = importedImage {
                    ReviewView(image: cg,
                               capturedLevel: LevelReading(rollDegrees: 0, pitchDegrees: 0),
                               analysis: nil)
                        .environmentObject(settings)
                }
            }
            .onChange(of: pickerItem) { _, item in loadPicked(item) }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
            await MainActor.run {
                importedImage = cg
                showImportReview = true
                pickerItem = nil
            }
        }
    }

    private func bigButton(_ title: String, systemImage: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, systemImage: systemImage) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(hint)
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage).imageScale(.large)
            Text(title).font(.title2.weight(.semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
