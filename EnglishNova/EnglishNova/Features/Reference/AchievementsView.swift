import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var session: UserSession

    var body: some View {
        List(ReferenceLibrary.achievements) { achievement in
            let unlocked = session.points >= achievement.requiredPoints
            HStack(spacing: 14) {
                Image(systemName: unlocked ? achievement.systemImage : "lock.fill")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(achievement.titleAr)).font(.headline)
                    Text(L(achievement.descriptionAr)).font(.subheadline).foregroundStyle(.secondary)
                    if !unlocked {
                        Text("متبقي \(max(0, achievement.requiredPoints - session.points)) نقطة")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if unlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(unlocked ? L("مفتوح") : L("مغلق"))
        }
        .navigationTitle(L("الإنجازات"))
    }
}
