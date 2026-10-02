import SwiftUI
import UIKit

// MARK: - People Editor
struct PeopleEditor: View {
    @EnvironmentObject var vm: BillViewModel
    @EnvironmentObject private var groupsVM: ContactGroupsViewModel
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var activeSheet: PeopleEditorSheet? = nil

    enum PeopleEditorSheet: Identifiable {
        case contacts, groupPicker, saveAsGroup
        var id: Int {
            switch self { case .contacts: 0; case .groupPicker: 1; case .saveAsGroup: 2 }
        }
    }

    var body: some View {
        // No nested List — this view lives inside a Form/Section in CurrentBillView.
        Group {
            if vm.bill.people.isEmpty {
                Text("Add at least one person").foregroundStyle(.secondary)
            }

            ForEach(vm.bill.people) { person in
                PersonRow(person: person)
            }
            .onDelete(perform: vm.removePeople)

            // Manual entry row — name is required, phone is optional
            VStack(spacing: 6) {
                HStack {
                    TextField("Name (required)", text: $newName)
                    Button(action: add) { Image(systemName: "plus.circle.fill") }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Image(systemName: "phone")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                    TextField("Phone (optional)", text: $newPhone)
                        .keyboardType(.phonePad)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // Contacts picker button
            Button {
                activeSheet = .contacts
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Contacts")
                }
                .padding(3)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 10))
            }

            // Group picker button — only shown when groups exist
            if !groupsVM.groups.isEmpty {
                Button {
                    activeSheet = .groupPicker
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.person.crop")
                        Text("Add Group")
                    }
                    .padding(3)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 10))
                }
            }

            // Save current people as a new group
            if !vm.bill.people.isEmpty {
                Button {
                    activeSheet = .saveAsGroup
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Save as Group")
                    }
                    .padding(3)
                    .background(Color.teal)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 10))
                }
            }

            HStack {
                TextField("Zelle To email", text: Binding(
                    get: { vm.bill.zelleEmail ?? "" },
                    set: { vm.bill.zelleEmail = $0.isEmpty ? nil : $0 }
                ))
                TextField("Zelle To Phone", text: Binding(
                    get: { vm.bill.zellePhone ?? "" },
                    set: { vm.bill.zellePhone = $0.isEmpty ? nil : $0 }
                ))
            }
            HStack {
                TextField("Venmo @username", text: Binding(
                    get: { vm.bill.venmoUsername ?? "" },
                    set: { vm.bill.venmoUsername = $0.isEmpty ? nil : $0 }
                ))
                TextField("Cash App $cashtag", text: Binding(
                    get: { vm.bill.cashAppTag ?? "" },
                    set: { vm.bill.cashAppTag = $0.isEmpty ? nil : $0 }
                ))
            }

            // Single invisible anchor — drives all three sheets via enum.
            Color.clear
                .frame(height: 0)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .contacts:
                        // `activeSheet` is already non-nil (we're in its .sheet(item:)
                        // closure) — this Binding only needs to clear it to dismiss.
                        ContactPickerSheet(isPresented: Binding(
                            get: { true },
                            set: { if !$0 { activeSheet = nil } }
                        )) { persons in
                            vm.bill.people.append(contentsOf: persons)
                        }
                    case .groupPicker:
                        GroupPickerSheet(groups: groupsVM.groups) { selectedGroup in
                            let existingNames = Set(vm.bill.people.map { $0.name.lowercased() })
                            let newMembers = selectedGroup.members.filter { !existingNames.contains($0.name.lowercased()) }
                            vm.bill.people.append(contentsOf: newMembers)
                        }
                    case .saveAsGroup:
                        SaveBillPeopleAsGroupSheet(people: vm.bill.people)
                    }
                }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let phone = newPhone.trimmingCharacters(in: .whitespaces)
        vm.addPerson(name: name, phone: phone.isEmpty ? nil : phone)
        newName = ""
        newPhone = ""
    }
}

// MARK: - Person Row
/// Displays one person with their share and a payment-request action.
struct PersonRow: View {
    @EnvironmentObject var vm: BillViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    let person: Person
    @State private var showPayerPicker = false
    @State private var showPaywall = false

    private var share: (preTax: Double, tax: Double, tip: Double, total: Double) {
        vm.totalForPerson(person.id)
    }
    private var hasShare: Bool { share.total > 0.01 }
    private var isNotPaying: Bool { person.notPayingAssignedToID != nil }
    private var payerName: String? {
        guard let payerID = person.notPayingAssignedToID else { return nil }
        return vm.bill.people.first(where: { $0.id == payerID })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name + total
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if person.isBirthday {
                            Text("🎂").font(.body)
                        } else if person.isExcluded {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .font(.body)
                                .foregroundStyle(.orange)
                        } else if isNotPaying {
                            Image(systemName: "arrowshape.turn.up.right.circle.fill")
                                .font(.body)
                                .foregroundStyle(.purple)
                        }
                        Text(person.name).fontWeight(.semibold)
                            .foregroundStyle(
                                person.isBirthday ? Color.pink :
                                person.isExcluded  ? Color.orange :
                                isNotPaying        ? Color.purple : Color.primary
                            )
                    }
                    if let phone = person.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if person.isBirthday {
                        Text("Covered by the group 🎉")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    } else if person.isExcluded {
                        Text("Only pays own items")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let payerName {
                        Text("Paid by \(payerName)")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if person.isBirthday {
                        Text("$0.00")
                            .fontWeight(.semibold)
                            .foregroundStyle(.pink)
                    } else if isNotPaying {
                        Text("$0.00")
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    } else if hasShare {
                        Text(share.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .fontWeight(.semibold)
                    }
                    HStack(spacing: 6) {
                        Button {
                            vm.toggleBirthday(for: person.id)
                        } label: {
                            Label(person.isBirthday ? "Remove Birthday" : "Birthday",
                                  systemImage: person.isBirthday ? "birthday.cake.fill" : "birthday.cake")
                                .font(.caption2)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(person.isBirthday ? Color.pink.opacity(0.15) : Color.secondary.opacity(0.12))
                                .foregroundStyle(person.isBirthday ? Color.pink : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(person.isExcluded || isNotPaying)

                        Button {
                            vm.toggleExcluded(for: person.id)
                        } label: {
                            Label(person.isExcluded ? "Included" : "Exclude",
                                  systemImage: person.isExcluded ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus")
                                .font(.caption2)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(person.isExcluded ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12))
                                .foregroundStyle(person.isExcluded ? Color.orange : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(person.isBirthday || isNotPaying)

                        Button {
                            notPayingButtonTapped()
                        } label: {
                            Label(isNotPaying ? "Paying" : "Not Paying",
                                  systemImage: isNotPaying ? "arrow.uturn.backward.circle" : "arrowshape.turn.up.right.circle")
                                .font(.caption2)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isNotPaying ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.12))
                                .foregroundStyle(isNotPaying ? Color.purple : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(person.isBirthday || person.isExcluded)
                    }
                }
            }

            // Itemised breakdown
            if hasShare && !person.isBirthday {
                Text("Items \(share.preTax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))  •  Tax \(share.tax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))  •  Tip \(share.tip.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Payment buttons — hidden for birthday people (they owe nothing)
            if hasShare && !person.isBirthday {
                HStack(spacing: 8) {
                    // Request — sends person a payment request so YOU receive money
                    Button {
                        requestPayment()
                    } label: {
                        Label("Request", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showPayerPicker) {
            PayerPickerSheet(
                people: vm.bill.people.filter { $0.id != person.id && $0.notPayingAssignedToID == nil },
                onSelect: { payer in
                    vm.setNotPayingPayer(for: person.id, payerID: payer.id)
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func notPayingButtonTapped() {
        if isNotPaying {
            vm.setNotPayingPayer(for: person.id, payerID: nil)
        } else if purchaseManager.isUnlocked {
            showPayerPicker = true
        } else {
            showPaywall = true
        }
    }

    /// Sends a payment REQUEST to the person so that YOU receive the money.
    /// Tries Venmo's charge deep link first, then falls back to a pre-filled
    /// iMessage so you can forward it to the person manually.
    private func requestPayment() {
        let code = Locale.current.currency?.identifier ?? "USD"
        let amount = share.total
        let amountFormatted = amount.formatted(.currency(code: code))
        let restaurant = vm.bill.restaurantName.isEmpty ? "our meal" : vm.bill.restaurantName
        let amountString = String(format: "%.2f", (amount * 100).rounded() / 100)
        let note = "Share for \(restaurant)"
        let noteEncoded = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? note

        // 1. Venmo charge request deep link (txn=charge means you are requesting money)
        if let venmoURL = URL(string: "venmo://paycharge?txn=charge&amount=\(amountString)&note=\(noteEncoded)"),
           UIApplication.shared.canOpenURL(venmoURL) {
            UIApplication.shared.open(venmoURL)
            return
        }

        // 2. Fallback: pre-filled iMessage/SMS addressed to the person's phone number.
        //    The message tells them exactly how much to send and via which apps.
        let message = "Hey \(person.name)! Your share for \(restaurant) is \(amountFormatted). Please send me that amount via Apple Cash or Venmo. Thanks!"
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Contacts phone numbers often contain spaces, dashes, and parentheses
        // (e.g. "(555) 123-4567"), which are invalid in a URL and make
        // URL(string:) return nil — silently doing nothing. Keep only digits
        // and a leading "+" so the sms: URL always parses.
        let sanitizedPhone = person.phone?.filter { $0.isNumber || $0 == "+" }
        let phoneTarget = (sanitizedPhone?.isEmpty == false ? sanitizedPhone : nil).map { "sms:\($0)" } ?? "sms:"
        if let smsURL = URL(string: "\(phoneTarget)&body=\(encoded)") {
            UIApplication.shared.open(smsURL)
        }
    }
}

// MARK: - Payer Picker Sheet
/// Lets the user pick who covers a "Not Paying" person's share. People who
/// are themselves flagged "Not Paying" are excluded from `people` by the
/// caller, so a payer can't chain their own share onto someone else.
struct PayerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let people: [Person]
    let onSelect: (Person) -> Void

    var body: some View {
        NavigationStack {
            List {
                if people.isEmpty {
                    Text("Add another person to the bill first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(people) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            Text(candidate.name)
                        }
                    }
                }
            }
            .navigationTitle("Who's Paying?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


