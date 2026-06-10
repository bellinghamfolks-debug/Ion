import SwiftUI

struct MemoryView: View {
    @StateObject private var store = ArchiveStore.shared
    @State private var newSection: NewEntrySheet?

    enum NewEntrySheet: String, Identifiable {
        case person, product, place
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                BasirStatusBanner(
                    text: L10n.t(
                        "هذه الملاحظات محفوظة على جهازك فقط، ولا تُرسل إلى خدمة الذكاء الاصطناعي إلا إذا نسختها بنفسك إلى إحدى الأدوات.",
                        "These notes stay on your device and are not sent to the AI service unless you copy them into a tool yourself."
                    ),
                    tone: .success
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            memorySection(
                title: L10n.t("الأشخاص", "People"),
                items: store.people,
                emptyText: L10n.t("لم تُضف أشخاصًا بعد.", "No people added yet."),
                addTitle: L10n.t("إضافة شخص", "Add person"),
                addIcon: "person.badge.plus",
                addKind: .person,
                delete: { store.deletePerson($0.id) }
            ) { person in
                MemoryRow(
                    icon: "person.fill",
                    title: person.name,
                    subtitle: person.relation,
                    notes: person.notes
                )
            }

            memorySection(
                title: L10n.t("المنتجات والأدوية", "Products and medications"),
                items: store.products,
                emptyText: L10n.t("لم تُضف منتجات أو أدوية بعد.", "No products or medications added yet."),
                addTitle: L10n.t("إضافة منتج أو دواء", "Add product or medication"),
                addIcon: "shippingbox.and.arrow.backward.fill",
                addKind: .product,
                delete: { store.deleteProduct($0.id) }
            ) { product in
                MemoryRow(
                    icon: "shippingbox.fill",
                    title: product.name,
                    subtitle: product.barcode.isEmpty ? "" : L10n.t("الرمز: \(product.barcode)", "Code: \(product.barcode)"),
                    notes: product.notes
                )
            }

            memorySection(
                title: L10n.t("الأماكن", "Places"),
                items: store.places,
                emptyText: L10n.t("لم تُضف أماكن بعد.", "No places added yet."),
                addTitle: L10n.t("إضافة مكان", "Add place"),
                addIcon: "mappin.and.ellipse",
                addKind: .place,
                delete: { store.deletePlace($0.id) }
            ) { place in
                MemoryRow(
                    icon: "mappin.circle.fill",
                    title: place.name,
                    subtitle: place.description,
                    notes: place.notes
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BasirTheme.screenBackground)
        .navigationTitle(L10n.t("ملاحظاتي المحلية", "My local notes"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newSection) { kind in
            NewEntrySheetView(kind: kind, store: store)
        }
    }

    @ViewBuilder
    private func memorySection<Item: Identifiable, Row: View>(
        title: String,
        items: [Item],
        emptyText: String,
        addTitle: String,
        addIcon: String,
        addKind: NewEntrySheet,
        delete: @escaping (Item) -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        Section(title) {
            if items.isEmpty {
                Label(emptyText, systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in row(item) }
                    .onDelete { indexSet in
                        for index in indexSet { delete(items[index]) }
                    }
            }

            Button { newSection = addKind } label: {
                Label(addTitle, systemImage: addIcon)
            }
            .fontWeight(.semibold)
        }
    }
}

private struct MemoryRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let notes: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BasirTheme.brand)
                .frame(width: 32, height: 32)
                .background(BasirTheme.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                if !notes.isEmpty {
                    Text(notes).font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct NewEntrySheetView: View {
    let kind: MemoryView.NewEntrySheet
    let store: ArchiveStore

    @State private var name = ""
    @State private var secondary = ""
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(namePlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(L10n.t("الاسم", "Name"))
                }

                Section {
                    TextField(secondaryFieldPlaceholder, text: $secondary, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(secondaryFieldLabel)
                }

                Section {
                    TextField(L10n.t("أي معلومة تساعدك على التذكر", "Anything that helps you remember"),
                              text: $notes,
                              axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L10n.t("ملاحظات اختيارية", "Optional notes"))
                }
            }
            .navigationTitle(titleForKind)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("حفظ", "Save")) {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var titleForKind: String {
        switch kind {
        case .person: return L10n.t("إضافة شخص", "Add person")
        case .product: return L10n.t("إضافة منتج أو دواء", "Add product or medication")
        case .place: return L10n.t("إضافة مكان", "Add place")
        }
    }

    private var namePlaceholder: String {
        switch kind {
        case .person: return L10n.t("اسم الشخص", "Person's name")
        case .product: return L10n.t("اسم المنتج أو الدواء", "Product or medication name")
        case .place: return L10n.t("اسم المكان", "Place name")
        }
    }

    private var secondaryFieldLabel: String {
        switch kind {
        case .person: return L10n.t("صلة الشخص بك", "Relationship")
        case .product: return L10n.t("الباركود أو الرمز", "Barcode or code")
        case .place: return L10n.t("وصف يساعدك على معرفة المكان", "Description that helps identify the place")
        }
    }

    private var secondaryFieldPlaceholder: String {
        switch kind {
        case .person: return L10n.t("مثال: زميل العمل", "Example: work colleague")
        case .product: return L10n.t("اختياري", "Optional")
        case .place: return L10n.t("مثال: الباب الثاني بعد المصعد", "Example: second door after the lift")
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .person:
            store.addPerson(Person(name: cleanName, relation: cleanSecondary, notes: cleanNotes))
        case .product:
            store.addProduct(Product(name: cleanName, barcode: cleanSecondary, notes: cleanNotes))
        case .place:
            store.addPlace(Place(name: cleanName, description: cleanSecondary, notes: cleanNotes))
        }
    }
}
