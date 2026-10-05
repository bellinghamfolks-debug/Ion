import SwiftUI

/// Bean Adapt: up to six bean profiles. The active one tunes every drink's
/// default strength and temperature and tells you the grinder setting.
struct BeansView: View {
    @Environment(AppModel.self) var model
    @State var editing: BeanProfile?

    private var beans: [BeanProfile] { model.data.beanProfiles }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("beans.intro"))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                if let active = model.data.activeBean {
                    activeCard(active)
                }
                if beans.isEmpty {
                    HStack(spacing: 16) {
                        BeanBagIllustration().frame(width: 70)
                        Text(L("beans.empty"))
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(18)
                    .card()
                } else {
                    SectionTitle(text: L("beans.list"))
                    ForEach(beans) { bean in
                        row(bean)
                    }
                }
                Button {
                    editing = BeanProfile(name: "")
                } label: {
                    Label(L("beans.add"), systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(beans.count >= BeanProfile.maxCount)
                Text(beans.count >= BeanProfile.maxCount ? L("beans.full") : L("beans.slots", BeanProfile.maxCount - beans.count))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(L("beans.footer"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("beans.title"))
        .sheet(item: $editing) { bean in
            BeanEditor(bean: bean) { saved in
                var ok = false
                model.updateData { ok = $0.saveBean(saved) }
                Announcer.shared.announce(ok ? L("announce.saved") : L("beans.needsName"))
                if ok { editing = nil }
            }
        }
    }

    /// The bean in use: its bag, "In use", Refine, its profile and taste.
    private func activeCard(_ bean: BeanProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("bean.card.set"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(bean.name)
                .font(.display(.largeTitle))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ZStack(alignment: .topLeading) {
                BeanBagIllustration(roast: bean.roast)
                    .frame(maxWidth: 170)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surfaceRaised))
                InfoChip(text: L("beans.inUse"), symbol: "checkmark", filled: true)
                    .padding(12)
                    .accessibilityHidden(true)
            }
            Button { editing = bean } label: {
                Label(L("beans.refine"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(PillButtonStyle())
            Text(L("beans.profile"))
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                profileTile(L("beans.kind"), value: bean.kind.title, symbol: "leaf")
                profileTile(L("beans.roast"), value: bean.roast.title, symbol: "flame")
                profileTile(L("beans.grind"), value: L("beans.grind.value", bean.recommendedGrind), symbol: "dial.medium")
                profileTile(L("param.temperature"), value: bean.recommendedTemperature.title, symbol: "thermometer.medium")
            }
            NavigationLink {
                TasteProfileView(bean: bean)
            } label: {
                NavigationRowCard(title: L("taste.open"), subtitle: L("taste.\(bean.taste.flavour.rawValue).title"), symbol: "sparkles")
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .card()
    }

    private func profileTile(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                Image(systemName: symbol).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            Divider().overlay(Theme.separator)
            Text(value).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceRaised))
        .accessibilityElement(children: .combine)
    }

    private func row(_ bean: BeanProfile) -> some View {
        let active = bean.id == model.data.activeBeanID
        return Button {
            model.selectBean(bean.id)
            Announcer.shared.announce(L("beans.selected", bean.name))
        } label: {
            HStack(spacing: 14) {
                BeanBagIllustration(roast: bean.roast)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bean.name).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(bean.summary).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(L("beans.select.hint"))
        .accessibilityAction(named: Text(L("action.edit"))) { editing = bean }
        .accessibilityAction(named: Text(L("action.delete"))) { delete(bean) }
        .contextMenu {
            Button(L("action.edit"), systemImage: "pencil") { editing = bean }
            Button(L("action.delete"), systemImage: "trash", role: .destructive) { delete(bean) }
        }
    }

    private func delete(_ bean: BeanProfile) {
        model.updateData { $0.removeBean(id: bean.id) }
        Announcer.shared.announce(L("announce.deleted", bean.name))
    }
}

/// "Your coffee profile is…": the taste the active beans give, with acidity
/// and body out of ten, on a dark roasted backdrop.
struct TasteProfileView: View {
    let bean: BeanProfile

    private var taste: TasteProfile { bean.taste }

    private var symbol: String {
        switch taste.flavour {
        case .fruity: return "leaf.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .chocolatey: return "square.grid.2x2.fill"
        case .bold: return "flame.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("taste.intro"))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(L("taste.\(taste.flavour.rawValue).title"))
                        .font(.display(.largeTitle))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color(hex: 0x7A4A33)))
                        .accessibilityHidden(true)
                    Text(L("taste.flavour"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(L("taste.\(taste.flavour.rawValue).detail"))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
                .frame(maxWidth: 300, minHeight: 260)
                .background(Circle().stroke(.white.opacity(0.6), lineWidth: 1.2))
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                HStack(spacing: 20) {
                    meter(L("taste.acidity"), value: taste.acidity)
                    meter(L("taste.body"), value: taste.body)
                }

                Text(L("taste.basedOn", bean.name, bean.roast.title, bean.kind.title))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
        }
        .background(HeroBackground().ignoresSafeArea())
        .navigationTitle(L("taste.open"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func meter(_ title: String, value: Int) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            RingGauge(fraction: Double(value) / 10, tint: .white, track: .white.opacity(0.25), lineWidth: 6) {
                Text(L("taste.outOfTen", value))
                    .font(.title2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 120, height: 120)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(L("taste.outOfTen.spoken", value))
    }
}

struct BeanEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var bean: BeanProfile
    let onSave: (BeanProfile) -> Void

    init(bean: BeanProfile, onSave: @escaping (BeanProfile) -> Void) {
        _bean = State(initialValue: bean)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("beans.name")) {
                    TextField(L("beans.name.placeholder"), text: $bean.name)
                }
                Section(L("beans.roast")) {
                    Picker(L("beans.roast"), selection: $bean.roast) {
                        ForEach(BeanProfile.Roast.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(L("beans.kind")) {
                    Picker(L("beans.kind"), selection: $bean.kind) {
                        ForEach(BeanProfile.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Picker(L("beans.bias"), selection: $bean.strengthBias) {
                        Text(L("beans.bias.milder")).tag(-1)
                        Text(L("beans.bias.none")).tag(0)
                        Text(L("beans.bias.stronger")).tag(1)
                    }
                } footer: {
                    Text(L("beans.bias.footer"))
                }
                Section(L("beans.recommendation")) {
                    LabeledContent(L("beans.grind"), value: L("beans.grind.value", bean.recommendedGrind))
                    LabeledContent(L("param.temperature"), value: bean.recommendedTemperature.title)
                    Text(L("beans.grind.howTo"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle(bean.name.isEmpty ? L("beans.add") : bean.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("action.save")) { onSave(bean) } }
            }
        }
    }
}
