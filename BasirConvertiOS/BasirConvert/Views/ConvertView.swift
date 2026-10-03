import SwiftUI

/// Kept for direct entry points; the app's "New" tab hosts both operations.
struct ConvertView: View {
    var body: some View { TaskComposerView(operation: .constant(.convert)) }
}
