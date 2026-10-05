import SwiftUI

/// A readable text page: each section has a heading (VoiceOver heading
/// navigation) and a paragraph.
struct InfoPage: View {
    let title: String
    let sections: [(heading: String, body: String)]

    init(title: String, sections: [(heading: String, body: String)]) {
        self.title = title
        self.sections = sections
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    static func sections(prefix: String, count: Int) -> [(heading: String, body: String)] {
        (1...count).map { (L("\(prefix).\($0).heading"), L("\(prefix).\($0).body")) }
    }
}

struct AboutView: View {
    var body: some View {
        InfoPage(title: L("about.title"), sections: InfoPage.sections(prefix: "about", count: 4))
    }
}

struct AccessibilityStatementView: View {
    var body: some View {
        InfoPage(title: L("accessibility.title"), sections: InfoPage.sections(prefix: "accessibility", count: 6))
    }
}

struct HelpView: View {
    var body: some View {
        InfoPage(title: L("help.title"), sections: InfoPage.sections(prefix: "help", count: 9))
    }
}

struct TroubleshootingView: View {
    var body: some View {
        InfoPage(title: L("trouble.title"), sections: InfoPage.sections(prefix: "trouble", count: 10))
    }
}
