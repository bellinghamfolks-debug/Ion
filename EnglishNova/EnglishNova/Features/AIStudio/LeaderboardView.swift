import SwiftUI

/// Leaderboard — top learners by points, plus the signed-in user's own rank.
/// Powered by /leaderboard (reads points/streak the server denormalises from
/// each user's synced progress).
struct LeaderboardView: View {
    @State private var result: LeaderboardResult?
    @State private var loading = true
    @State private var errorMessage: String?

    private let service = AIStudioService()

    var body: some View {
        List {
            if let me = result?.me {
                Section(L("ترتيبك")) {
                    HStack(spacing: 12) {
                        Text("#\(me.rank)")
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.brand)
                        Spacer()
                        Label("\(me.points)", systemImage: "star.fill")
                            .foregroundStyle(AppTheme.warning)
                        Label("\(me.streak)", systemImage: "flame.fill")
                            .foregroundStyle(AppTheme.streak)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Section(L("أفضل المتعلّمين")) {
                if loading {
                    HStack(spacing: 10) { ProgressView(); Text(L("جارٍ التحميل…")).foregroundStyle(.secondary) }
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                } else if (result?.top.isEmpty ?? true) {
                    Text(L("لا يوجد متصدّرون بعد. احفظ تقدّمك من شاشة الحساب لتكون أول المتصدّرين!"))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(result?.top ?? []) { entry in row(entry) }
                }
            }
        }
        .navigationTitle(L("لوحة الصدارة"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(entry.rank)
            Text(entry.name)
                .font(.subheadline.weight(entry.isMe ? .bold : .regular))
                .foregroundStyle(entry.isMe ? AppTheme.brand : .primary)
            if entry.isMe {
                Text(L("أنت")).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AppTheme.brand.opacity(0.15), in: Capsule())
                    .foregroundStyle(AppTheme.brand)
            }
            Spacer()
            Label("\(entry.points)", systemImage: "star.fill")
                .font(.caption).foregroundStyle(AppTheme.warning)
            if entry.streak > 0 {
                Label("\(entry.streak)", systemImage: "flame.fill")
                    .font(.caption).foregroundStyle(AppTheme.streak)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Lf("المركز %@، %@، %@ نقطة", "\(entry.rank)", "\(entry.name)", "\(entry.points)"))
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        let medals = [1: "🥇", 2: "🥈", 3: "🥉"]
        if let medal = medals[rank] {
            Text(medal).font(.title3)
        } else {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            result = try await service.leaderboard()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "تعذّر تحميل لوحة الصدارة."
        }
        loading = false
    }
}
