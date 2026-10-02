import SwiftUI

// MARK: - Item Edit Sheet
struct ItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var draftPrice: Double

    let item: Item
    let onSave: (Item) -> Void

    init(item: Item, onSave: @escaping (Item) -> Void) {
        self.item = item
        self.onSave = onSave
        _draftName  = State(initialValue: item.name)
        _draftPrice = State(initialValue: item.price)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $draftName)
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", value: $draftPrice,
                                  format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.name  = draftName.trimmingCharacters(in: .whitespaces)
                        updated.price = draftPrice
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty || draftPrice <= 0)
                }
            }
        }
    }
}

// MARK: - Items Editor View
struct ItemsEditor: View {
    @EnvironmentObject var vm: BillViewModel
    @State private var newItemName = ""
    @State private var newItemPrice: Double? = nil
    /// Lifted from parent via binding so the sheet lives outside the Form.
    @Binding var itemToEdit: Item?

    var body: some View {
        // Split into explicit @ViewBuilder helpers so the Swift type-checker
        // doesn't have to unify all branches of a single Group at once —
        // which is what caused the spurious ForEach / Binding errors.
        itemRows
        addRow
    }

    // MARK: - Subviews

    @ViewBuilder
    private var itemRows: some View {
        if vm.bill.items.isEmpty {
            Text("Add items and assign consumers").foregroundStyle(.secondary)
        } else {
            ForEach(vm.bill.items) { item in
                itemRow(for: item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let idx = vm.bill.items.firstIndex(where: { $0.id == item.id }) {
                                vm.removeItems(at: IndexSet(integer: idx))
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func itemRow(for item: Item) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(item.name).fontWeight(.semibold)
                Spacer()
                Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                Button {
                    itemToEdit = item
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 180), spacing: 6)], spacing: 6) {
                ForEach(vm.bill.people) { person in
                    let isOn = item.consumers.contains(person.id)
                    Button {
                        vm.toggleConsumer(item: item, person: person)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                            Text(person.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(isOn ? .accentColor : .secondary)
                }
            }
        }
    }

    private var addRow: some View {
        HStack {
            TextField("Item name", text: $newItemName)
            TextField("Price", value: $newItemPrice, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .frame(width: 100)
            Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                .disabled((newItemPrice ?? 0) <= 0 || newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let price = newItemPrice, price > 0 else { return }
        vm.addItem(name: name, price: price)
        newItemName = ""; newItemPrice = nil
    }
}
// MARK: - Summary Section
struct SummarySection: View {
    @EnvironmentObject var vm: BillViewModel

    var body: some View {
        Section("Summary") {
            Toggle(isOn: $vm.bill.isPreTaxCalc ) {
                           Text("Pre Tax Tip")
                       }
            HStack { Text("Subtotal"); Spacer(); Text(vm.subtotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD")) }
            HStack { Text("Tax (") + Text(vm.bill.taxPercent, format: .number) + Text("%)"); Spacer(); Text(vm.taxAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")) }
            HStack { Text("Tip (") + Text(vm.bill.tipPercent, format: .number) + Text("%)"); Spacer(); Text(vm.tipAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")) }
            HStack { Text("Grand Total").fontWeight(.semibold); Spacer(); Text(vm.grandTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).fontWeight(.semibold) }
            
            if !vm.bill.people.isEmpty {
                
                Text("To Pay Per Person").fontWeight(.semibold)
                Divider()
                ForEach(vm.bill.people) { person in
                    let share = vm.totalForPerson(person.id )
                    VStack(alignment: .leading) {
                        HStack {
                            Text(person.name).fontWeight(.semibold)
                            Spacer()
                            Text(share.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        }
                        Text("• Items: \(share.preTax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))  • Tax: \(share.tax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))  • Tip: \(share.tip.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

