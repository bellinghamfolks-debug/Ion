import SwiftUI
import UIKit
import Vision

/// Version 3 parts of the bean editor: roast date and freshness, price and
/// cost per cup, decaf, rating and "buy again", the barcode and grind notes.
struct BeanV3Sections: View {
    @Environment(AppModel.self) var model
    @Binding var bean: BeanProfile
    @State var scanningBarcode = false
    @State var noteGrind = 6
    @State var noteRating = 4

    var body: some View {
        Section {
            DatePicker(L("beans.roastDate"), selection: Binding(get: { bean.roastDate ?? Date() }, set: { bean.roastDate = $0 }),
                       in: ...Date(), displayedComponents: .date)
            let freshness = Freshness.state(of: bean)
            LabeledContent(L("freshness.title"), value: freshness.title)
            Text(freshness.detail).font(.footnote).foregroundStyle(Theme.textSecondary)
        } header: { Text(L("freshness.header")) }

        Section {
            TextField(L("beans.price"), value: Binding(get: { bean.price }, set: { bean.price = $0 }), format: .number)
                .keyboardType(.decimalPad)
            if let cost = CostPerCup.beans(for: Recipe.standard(.espresso), bean: bean) {
                LabeledContent(L("cost.espresso"), value: CostPerCup.text(cost))
            }
            Toggle(L("beans.decaf"), isOn: $bean.decaf)
        } footer: { Text(L("beans.price.footer")) }

        Section {
            Picker(L("beans.rating"), selection: Binding(get: { bean.rating ?? 0 }, set: { bean.rating = $0 == 0 ? nil : $0 })) {
                Text(L("beans.rating.none")).tag(0)
                ForEach(1...5, id: \.self) { Text(L("stars.value", $0)).tag($0) }
            }
            Toggle(L("beans.buyAgain"), isOn: $bean.buyAgain)
            HStack {
                TextField(L("beans.barcode"), text: $bean.barcode).keyboardType(.numberPad)
                Button { scanningBarcode = true } label: { Image(systemName: "barcode.viewfinder") }
                    .accessibilityLabel(L("barcode.scan"))
            }
        } footer: { Text(L("beans.buyAgain.footer")) }

        Section {
            ForEach(Array(bean.grindNotes.enumerated()), id: \.offset) { _, note in
                LabeledContent(L("grindNote.row", note.grind), value: L("stars.value", note.rating))
            }
            .onDelete { bean.grindNotes.remove(atOffsets: $0) }
            Stepper(value: $noteGrind, in: 1...13) { LabeledContent(L("beans.grind"), value: "\(noteGrind)") }
            Stepper(value: $noteRating, in: 1...5) { LabeledContent(L("grindNote.taste"), value: L("stars.value", noteRating)) }
            Button(L("grindNote.add")) {
                bean.grindNotes.insert(GrindNote(grind: noteGrind, rating: noteRating), at: 0)
                Announcer.shared.announce(L("grindNote.added", noteGrind, noteRating))
            }
            if let best = GrindCoach.bestFromNotes(bean.grindNotes) {
                Text(L("grindNote.best", best)).font(.footnote.weight(.semibold))
            }
        } header: { Text(L("grindNote.title")) } footer: { Text(L("grindNote.footer")) }
        .onAppear { noteGrind = bean.recommendedGrind }
        .sheet(isPresented: $scanningBarcode) {
            BarcodeScannerSheet { code in
                guard let code else { return }
                bean.barcode = code
                if let known = BarcodeLookup.match(code, beans: model.data.beanProfiles.filter { $0.id != bean.id }) {
                    if bean.name.isEmpty { bean.name = known.name }
                    bean.roast = known.roast
                    bean.kind = known.kind
                    if bean.roaster.isEmpty { bean.roaster = known.roaster }
                    Announcer.shared.announce(L("barcode.known", known.name))
                } else {
                    Announcer.shared.announce(L("barcode.read", code))
                }
            }
        }
    }
}

/// Reads a product barcode from a photo of the bag.
struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onRead: (String?) -> Void

    var body: some View {
        ImagePicker { image in
            guard let image else { onRead(nil); dismiss(); return }
            Task {
                let code = await BarcodeReader.read(image)
                if code == nil { Announcer.shared.announce(L("barcode.none"), priority: .high) }
                onRead(code)
                dismiss()
            }
        }
        .ignoresSafeArea()
    }
}

enum BarcodeReader {
    static func read(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                    let payload = (request.results ?? []).compactMap(\.payloadStringValue).first
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Bags bought, newest first, with what was spent this month.
struct PurchasesView: View {
    @Environment(AppModel.self) var model
    @State var adding = false
    @State var draft = BeanPurchase(name: "")

    var body: some View {
        let purchases = model.data.life.pro.purchases
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let spent = purchases.filter { $0.date >= monthAgo }.compactMap(\.price).reduce(0, +)
        ProForm(title: L("screen.purchases")) {
            Section {
                LabeledContent(L("purchases.month"), value: CostPerCup.text(spent))
                LabeledContent(L("purchases.count"), value: "\(purchases.count)")
            }
            Section {
                ForEach(purchases) { purchase in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(purchase.name).font(.headline)
                        Text([purchase.date.formatted(date: .abbreviated, time: .omitted),
                              purchase.grams.map { L("stock.grams", $0) } ?? "",
                              purchase.price.map(CostPerCup.text) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in model.updateData { $0.life.pro.purchases.remove(atOffsets: offsets) } }
                if purchases.isEmpty { Text(L("purchases.empty")).foregroundStyle(Theme.textSecondary) }
            } footer: { Text(L("purchases.footer")) }
            Section {
                Button { model.openedNewBag() } label: { Label(L("bag.openedButton"), systemImage: "bag") }
                    .disabled(model.data.activeBean == nil)
                Button { draft = BeanPurchase(name: model.data.activeBean?.name ?? ""); adding = true } label: {
                    Label(L("purchases.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField(L("beans.name"), text: $draft.name)
                    TextField(L("beans.roaster"), text: $draft.roaster)
                    DatePicker(L("purchases.date"), selection: $draft.date, in: ...Date(), displayedComponents: .date)
                    TextField(L("beans.bag"), value: $draft.grams, format: .number).keyboardType(.numberPad)
                    TextField(L("beans.price"), value: $draft.price, format: .number).keyboardType(.decimalPad)
                }
                .navigationTitle(L("purchases.add"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("action.cancel")) { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("action.save")) {
                            model.updateData { $0.life.pro.purchases.insert(draft, at: 0) }
                            adding = false
                        }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

/// Two bags side by side.
struct CompareBeansView: View {
    @Environment(AppModel.self) var model
    @State var first: UUID?
    @State var second: UUID?

    var body: some View {
        let beans = model.data.beanProfiles
        ProForm(title: L("screen.compareBeans")) {
            if beans.count < 2 {
                Text(L("compareBeans.needTwo"))
            } else {
                Section {
                    Picker(L("compare.first"), selection: $first) { ForEach(beans) { Text($0.name).tag(UUID?.some($0.id)) } }
                    Picker(L("compare.second"), selection: $second) { ForEach(beans) { Text($0.name).tag(UUID?.some($0.id)) } }
                }
                if let a = beans.first(where: { $0.id == first }), let b = beans.first(where: { $0.id == second }) {
                    Section(L("compare.result")) {
                        ForEach(BeanComparison.rows(a, b, profiles: model.data.profiles, milkPrice: model.data.life.pro.milkPricePerLitre)) { row in
                            HStack {
                                Text(row.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(row.first).frame(minWidth: 70)
                                Text(row.second).frame(minWidth: 70)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.title)
                            .accessibilityValue(L("compare.spoken", a.name, row.first, b.name, row.second))
                        }
                    }
                }
            }
        }
        .onAppear {
            if first == nil { first = beans.first?.id }
            if second == nil { second = beans.dropFirst().first?.id }
        }
    }
}

/// After the beans ran out and were refilled: which beans went in?
struct WhichBeanSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.data.beanProfiles) { bean in
                        Button {
                            model.selectBean(bean.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(bean.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if bean.id == model.data.activeBeanID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        .accessibilityAddTraits(bean.id == model.data.activeBeanID ? .isSelected : [])
                    }
                } footer: { Text(L("whichBean.footer")) }
                Section {
                    Button(L("whichBean.newBag")) {
                        model.openedNewBag()
                        dismiss()
                    }
                    Button(L("whichBean.same"), role: .cancel) { dismiss() }
                }
            }
            .navigationTitle(L("whichBean.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
