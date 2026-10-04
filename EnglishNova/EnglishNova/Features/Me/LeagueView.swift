import SwiftUI

struct LeagueMember: Decodable, Hashable, Identifiable {
    let rank: Int
    let name: String
    let weeklyPoints: Int
    let isMe: Bool
    var id: Int { rank }
}

struct LeagueLastWeek: Decodable, Hashable {
    let result: String
    let rank: Int
    let fromTier: String
}

struct LeagueStandings: Decodable, Hashable {
    struct Me: Decodable, Hashable { let rank: Int; let weeklyPoints: Int }

    let weekStart: String
    let endsAt: String
    let tier: String
    let tierIndex: Int
    let tierCount: Int
    let promoteCount: Int
    let demoteCount: Int
    let members: [LeagueMember]
    let me: Me
    let lastWeek: LeagueLastWeek?

    enum Zone { case promotion, safe, demotion }

    func zone(for rank: Int) -> Zone {
        if rank <= promoteCount { return .promotion }
        if demoteCount > 0 && rank > members.count - demoteCount { return .demotion }
        return .safe
    }

    var endsAtDate: Date? { ISO8601DateFormatter().date(from: endsAt) }
}

/// Display names and colours for the five tiers.
enum LeagueTier {
    static func title(_ tier: String) -> String {
        switch tier {
        case "silver": return LE("الدوري الفضي", "Silver league")
        case "gold": return LE("الدوري الذهبي", "Gold league")
        case "platinum": return LE("الدوري البلاتيني", "Platinum league")
        case "diamond": return LE("الدوري الماسي", "Diamond league")
        default: return LE("الدوري البرونزي", "Bronze league")
        }
    }

    static func color(_ tier: String) -> Color {
        switch tier {
        case "silver": return .gray
        case "gold": return AppTheme.warning
        case "platinum": return AppTheme.accentTeal
        case "diamond": return AppTheme.brandSecondary
        default: return AppTheme.streak
        }
    }
}

struct LeagueService {
    private let api = APIClient(configuration: APIConfiguration(baseURL: nil))

    func standings() async throws -> LeagueStandings {
        guard let token = KeychainStore().string(for: "server.authToken"), !token.isEmpty else {
            throw AIStudioError.notSignedIn
        }
        do {
            return try await api.get(path: "league", response: LeagueStandings.self, bearerToken: token)
        } catch {
            if case APIError.server(let status, _) = error, status == 401 { throw AIStudioError.notSignedIn }
            throw AIStudioError.unavailable
        }
    }
}

/// Weekly league: compete with up to 30 learners in your tier. The top five
/// move up next week; in bigger groups the bottom five move down.
struct LeagueView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var account: AccountService
    @State private var standings: LeagueStandings?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if !account.isAuthenticated {
                ContentUnavailableView {
                    Label(LE("سجّل الدخول للانضمام", "Sign in to join"), systemImage: "trophy")
                } description: {
                    Text(LE("الدوري الأسبوعي يقارن نقاط هذا الأسبوع مع متعلّمين في مستواك. يحتاج حسابًا لمزامنة نقاطك.",
                            "The weekly league compares this week's points with learners in your tier. It needs an account to sync your points."))
                } actions: {
                    NavigationLink(LE("تسجيل الدخول", "Sign in")) { AccountView() }
                        .buttonStyle(.borderedProminent)
                }
            } else if let standings {
                Section { header(standings) }
                if let last = standings.lastWeek { Section { lastWeekBanner(last) } }
                Section {
                    ForEach(standings.members) { member in
                        row(member, standings: standings)
                    }
                } header: {
                    Text(LfE("مجموعتك (%@)", "Your group (%@)", "\(standings.members.count)"))
                } footer: {
                    Text(rulesText(standings))
                }
            } else if isLoading {
                ProgressView(LE("جارٍ تحميل الدوري", "Loading the league"))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorMessage {
                ContentUnavailableView(LE("تعذّر تحميل الدوري", "Couldn't load the league"),
                                       systemImage: "wifi.exclamationmark",
                                       description: Text(errorMessage))
            }
        }
        .navigationTitle(LE("الدوري الأسبوعي", "Weekly league"))
        .task(id: account.isAuthenticated) { await load() }
        .refreshable { await load() }
    }

    private func header(_ value: LeagueStandings) -> some View {
        let tint = LeagueTier.color(value.tier)
        return HStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LeagueTier.title(value.tier))
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(LfE("مركزك %@ • %@ نقطة هذا الأسبوع", "Rank %@ • %@ points this week",
                         "\(value.me.rank)", "\(value.me.weeklyPoints)"))
                    .font(.subheadline)
                Text(timeLeft(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(LfE("المستوى %@ من %@", "Tier %@ of %@", "\(value.tierIndex + 1)", "\(value.tierCount)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func lastWeekBanner(_ last: LeagueLastWeek) -> some View {
        let text: String
        let icon: String
        let tint: Color
        switch last.result {
        case "promoted":
            text = LfE("الأسبوع الماضي أنهيت في المركز %@ وصعدت إلى دوري أعلى!", "Last week you finished #%@ and moved up a league!", "\(last.rank)")
            icon = "arrow.up.circle.fill"; tint = AppTheme.success
        case "demoted":
            text = LfE("الأسبوع الماضي أنهيت في المركز %@ ونزلت دوريًا. هذا أسبوع جديد!", "Last week you finished #%@ and moved down a league. New week, new chance!", "\(last.rank)")
            icon = "arrow.down.circle.fill"; tint = AppTheme.streak
        default:
            text = LfE("الأسبوع الماضي أنهيت في المركز %@ وبقيت في دوريك.", "Last week you finished #%@ and stayed in your league.", "\(last.rank)")
            icon = "equal.circle.fill"; tint = AppTheme.accentTeal
        }
        return Label(text, systemImage: icon)
            .foregroundStyle(tint)
            .font(.subheadline.weight(.semibold))
    }

    private func row(_ member: LeagueMember, standings: LeagueStandings) -> some View {
        let zone = standings.zone(for: member.rank)
        return HStack(spacing: 12) {
            Text("\(member.rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 34)
                .foregroundStyle(zone == .promotion ? AppTheme.success : (zone == .demotion ? AppTheme.streak : .secondary))
            Image(systemName: zoneIcon(zone))
                .foregroundStyle(zone == .promotion ? AppTheme.success : (zone == .demotion ? AppTheme.streak : .clear))
                .accessibilityHidden(true)
            Text(member.isMe ? LfE("%@ (أنت)", "%@ (you)", member.name) : member.name)
                .font(member.isMe ? .body.bold() : .body)
                .lineLimit(1)
            Spacer()
            Text("\(member.weeklyPoints)")
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .listRowBackground(member.isMe ? AppTheme.brand.opacity(0.10) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LfE("المركز %@، %@، %@ نقطة. %@", "Rank %@, %@, %@ points. %@",
                                "\(member.rank)", member.isMe ? LE("أنت", "you") : member.name,
                                "\(member.weeklyPoints)", zoneTitle(zone)))
    }

    private func zoneIcon(_ zone: LeagueStandings.Zone) -> String {
        switch zone {
        case .promotion: return "arrow.up"
        case .demotion: return "arrow.down"
        case .safe: return "minus"
        }
    }

    private func zoneTitle(_ zone: LeagueStandings.Zone) -> String {
        switch zone {
        case .promotion: return LE("في منطقة الصعود", "In the promotion zone")
        case .demotion: return LE("في منطقة الهبوط", "In the demotion zone")
        case .safe: return ""
        }
    }

    private func rulesText(_ value: LeagueStandings) -> String {
        var parts = [LE("تُحتسب النقاط التي تكسبها هذا الأسبوع (من الأحد إلى السبت بتوقيت الرياض) بعد مزامنة تقدّمك.",
                        "Points you earn this week (Sunday to Saturday, Riyadh time) count once your progress syncs.")]
        if value.promoteCount > 0 {
            parts.append(LfE("أول %@ يصعدون إلى الدوري التالي.", "The top %@ move up to the next league.", "\(value.promoteCount)"))
        }
        if value.demoteCount > 0 {
            parts.append(LfE("آخر %@ ينزلون دوريًا.", "The bottom %@ move down a league.", "\(value.demoteCount)"))
        }
        return parts.joined(separator: " ")
    }

    private func timeLeft(_ value: LeagueStandings) -> String {
        guard let end = value.endsAtDate else { return "" }
        let hours = max(0, Int(end.timeIntervalSinceNow / 3600))
        if hours >= 48 { return LfE("ينتهي الأسبوع بعد %@ أيام", "Week ends in %@ days", "\(hours / 24)") }
        return LfE("ينتهي الأسبوع بعد %@ ساعة", "Week ends in %@ hours", "\(hours)")
    }

    private func load() async {
        guard account.isAuthenticated else { isLoading = false; return }
        isLoading = true
        // Sync first so this week's points are current.
        _ = await container.progressSyncService.pushIfStale(maxAge: 60)
        do {
            standings = try await LeagueService().standings()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
        isLoading = false
    }
}
