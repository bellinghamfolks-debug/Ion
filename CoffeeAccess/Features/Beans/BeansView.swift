import SwiftUI

/// Bean Adapt: up to six bean profiles. The active one tunes every drink's
/// default strength and temperature and tells you the grinder setting.
struct BeansView: View {
    @Environment(AppModel.self) var model
    @State var editing: BeanProfile?

    var body: some View {
        List {
            Section {
                Text(L("beans.intro"))
                    .font(.body)
            }
            if model.data.beanProfiles.isEmpty {
                Section {
                    Text(L("beans.empty")).foregroundStyle(Theme.textSecondary)
                }
            } else {
                Section(L("beans.list")) {
                    ForEach(model.data.beanProfiles) { bean in
                        let active = bean.id == model.data.activeBeanID
                        Button {
                            model.selectBean(bean.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bean.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    Text(bean.summary).font(.footnote).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(L("beans.select.hint"))
                        .accessibilityAction(named: Text(L("action.edit"))) { editing = bean }
                        .accessibilityAction(named: Text(L("action.delete"))) { delete(bean) }
                        .swipeActions {
                            Button(L("action.delete"), role: .destructive) { delete(bean) }
                            Button(L("action.edit")) { editing = bean }
                        }
                    }
                }
            }
            Section {
                Button {
                    editing = BeanProfile(name: "")
                } label: {
                    Label(L("beans.add"), systemImage: "plus.circle.fill")
                }
                .disabled(model.data.beanProfiles.count >= BeanProfile.maxCount)
                if model.data.beanProfiles.count >= BeanProfile.maxCount {
                    Text(L("beans.full")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } footer: {
                Text(L("beans.footer"))
            }
        }
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

    private func delete(_ bean: BeanProfile) {
        model.updateData { $0.removeBean(id: bean.id) }
        Announcer.shared.announce(L("announce.deleted", bean.name))
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
