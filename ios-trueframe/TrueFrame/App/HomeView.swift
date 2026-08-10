import SwiftUI
import PhotosUI
import ImageIO
import CoreGraphics

/// Main hub with large, high-contrast action cards. The interface-mode setting
/// now has a real effect instead of being stored without changing the UI.
struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var importedImage: CGImage?
    @State private var showImportReview = false

    private var isLowVisionMode: Bool { settings.interfaceMode == "Low Vision" }
    private var isBlindMode: Bool { settings.interfaceMode == "Blind" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    introCard

                    actionButton(
                        title: settings.t("Take Photo"),
                        subtitle: settings.t("Get clear spoken and haptic guidance while you frame the shot."),
                        systemImage: "camera.fill",
                        prominent: true,
                        hint: settings.t("Opens the accessible camera with leveling and framing guidance.")
                    ) {
                        showCamera = true
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        actionLabel(
                            title: settings.t("Import Photo"),
                            subtitle: settings.t("Choose an existing photo and straighten it without generative editing."),
                            systemImage: "photo.on.rectangle.angled",
                            prominent: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(settings.t("Import Photo"))
                    .accessibilityHint(settings.t("Choose an existing photo and straighten it without generative editing."))

                    NavigationLink {
                        RecentView()
                    } label: {
                        actionLabel(
                            title: settings.t("Recent Photos"),
                            subtitle: settings.t("Browse corrected copies saved by TrueFrame."),
                            systemImage: "clock.arrow.circlepath",
                            prominent: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(settings.t("Recent Photos"))
                    .accessibilityHint(settings.t("Browse corrected copies saved by TrueFrame."))

                    NavigationLink {
                        SettingsView()
                    } label: {
                        actionLabel(
                            title: settings.t("Settings"),
                            subtitle: settings.t("Change language, guidance, accessibility, and auto capture."),
                            systemImage: "slider.horizontal.3",
                            prominent: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(settings.t("Settings"))
                    .accessibilityHint(settings.t("Change language, guidance, accessibility, and auto capture."))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("TrueFrame")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showCamera) {
                CameraView().environmentObject(settings)
            }
            .fullScreenCover(isPresented: $showImportReview) {
                if let image = importedImage {
                    ReviewView(image: image,
                               capturedLevel: LevelReading(rollDegrees: 0, pitchDegrees: 0),
                               analysis: nil)
                        .environmentObject(settings)
                }
            }
            .onChange(of: pickerItem) { _, item in
                loadPicked(item)
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: settings.isArabic ? .trailing : .leading, spacing: 8) {
            Label {
                Text(settings.t("Accessible camera"))
                    .font(isLowVisionMode ? .title.bold() : .title2.bold())
            } icon: {
                Image(systemName: "viewfinder")
                    .font(.title)
                    .accessibilityHidden(true)
            }

            if !isBlindMode {
                Text(settings.t("Get clear spoken and haptic guidance while you frame the shot."))
                    .font(isLowVisionMode ? .title3 : .body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: settings.isArabic ? .trailing : .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func actionButton(title: String,
                              subtitle: String,
                              systemImage: String,
                              prominent: Bool,
                              hint: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title: title,
                        subtitle: subtitle,
                        systemImage: systemImage,
                        prominent: prominent)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func actionLabel(title: String,
                             subtitle: String,
                             systemImage: String,
                             prominent: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(isLowVisionMode ? .largeTitle : .title2)
                .frame(width: isLowVisionMode ? 58 : 48,
                       height: isLowVisionMode ? 58 : 48)
                .background(
                    prominent ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: settings.isArabic ? .trailing : .leading,
                   spacing: 4) {
                Text(title)
                    .font(isLowVisionMode ? .title2.bold() : .headline)
                    .frame(maxWidth: .infinity,
                           alignment: settings.isArabic ? .trailing : .leading)

                if !isBlindMode {
                    Text(subtitle)
                        .font(isLowVisionMode ? .body : .subheadline)
                        .foregroundStyle(prominent ? .white.opacity(0.86) : .secondary)
                        .frame(maxWidth: .infinity,
                               alignment: settings.isArabic ? .trailing : .leading)
                }
            }

            Image(systemName: settings.isArabic ? "chevron.left" : "chevron.right")
                .font(.headline)
                .accessibilityHidden(true)
        }
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .padding(isLowVisionMode ? 22 : 18)
        .frame(maxWidth: .infinity)
        .background(
            prominent ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return
            }
            await MainActor.run {
                importedImage = image
                showImportReview = true
                pickerItem = nil
            }
        }
    }
}
