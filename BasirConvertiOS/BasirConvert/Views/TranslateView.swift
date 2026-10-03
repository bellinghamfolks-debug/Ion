import SwiftUI

/// Kept for direct entry points; the app's "New" tab hosts both operations.
struct TranslateView: View {
    var body: some View { TaskComposerView(operation: .constant(.translate)) }
}
