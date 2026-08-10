import SwiftUI

/// Deliberately simple home screen: four large, clearly-labeled actions.
struct HomeView: View {
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                bigButton("Take Photo", systemImage: "camera.fill",
                          hint: "Opens the accessible camera with leveling and framing guidance.") {
                    showCamera = true
                }
                NavigationLink {
                    Text("Import from Photos — coming soon")
                        .font(.title2)
                        .accessibilityLabel("Import photo. Feature coming soon.")
                } label: { label("Import Photo", systemImage: "photo.on.rectangle") }
                    .buttonStyle(.bordered)

                NavigationLink {
                    Text("Recent corrected photos — coming soon")
                } label: { label("Recent Photos", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(.bordered)

                NavigationLink {
                    Text("Settings — coming soon")
                } label: { label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("TrueFrame")
            .fullScreenCover(isPresented: $showCamera) { CameraView() }
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
