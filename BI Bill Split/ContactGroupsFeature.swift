import SwiftUI
import ContactsUI
import UIKit

// MARK: - Contact Groups ViewModel
@MainActor
final class ContactGroupsViewModel: ObservableObject {
    @Published var groups: [ContactGroup] = []
    private let key = "contactGroups"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ContactGroup].self, from: data)
        else { return }
        groups = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func addGroup(name: String, members: [Person]) {
        groups.append(ContactGroup(name: name, members: members))
        save()
    }

    func updateGroup(_ updated: ContactGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == updated.id }) else { return }
        groups[idx] = updated
        save()
    }

    func delete(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        save()
    }
}

// MARK: - Contact Groups View
struct ContactGroupsView: View {
    @EnvironmentObject private var groupsVM: ContactGroupsViewModel
    @State private var activeSheet: GroupSheet? = nil

    /// Drives a single `.sheet` so both presentations can coexist on the same view.
    enum GroupSheet: Identifiable {
        case newGroup
        case editGroup(ContactGroup)

        var id: String {
            switch self {
            case .newGroup:            return "newGroup"
            case .editGroup(let g):   return g.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupsVM.groups.isEmpty {
                    ContentUnavailableView(
                        "No Groups Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Tap + to create a reusable group of people.")
                    )
                } else {
                    List {
                        ForEach(groupsVM.groups) { group in
                            Button {
                                activeSheet = .editGroup(group)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(group.members.count) member\(group.members.count == 1 ? "" : "s") • \(group.members.map(\.name).joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: groupsVM.delete)
                    }
                }
            }
            .navigationTitle("Contact Groups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeSheet = .newGroup } label: {
                        Label("Add Group", systemImage: "plus")
                    }
                }
            }
            // Single sheet modifier — avoids the iOS bug where only the last
            // chained .sheet modifier is honoured on the same view.
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .newGroup:
                    NewGroupSheet(groupsVM: groupsVM)
                case .editGroup(let group):
                    GroupEditView(group: group) { updated in
                        groupsVM.updateGroup(updated)
                    }
                }
            }
        }
    }
}

// MARK: - New Group Sheet
/// Standalone sheet for creating a brand-new group. Keeps ContactGroupsView clean.
struct NewGroupSheet: View {
    @ObservedObject var groupsVM: ContactGroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var members: [Person] = []
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Work Friends", text: $groupName)
                }

                Section {
                    if members.isEmpty {
                        Text("No members yet — tap Add People")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members) { person in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                if let phone = person.phone, !phone.isEmpty {
                                    Text(phone).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in members.remove(atOffsets: offsets) }
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Members (\(members.count))")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        groupsVM.addGroup(name: groupName.trimmingCharacters(in: .whitespaces),
                                          members: members)
                        dismiss()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || members.isEmpty)
                }
            }
            // Use the non-dismissing picker so its dismiss() doesn't
            // bubble up and close this sheet too.
            .sheet(isPresented: $showingPicker) {
                ContactPickerSheet(isPresented: $showingPicker) { picked in
                    let existingIDs = Set(members.map(\.id))
                    members.append(contentsOf: picked.filter { !existingIDs.contains($0.id) })
                }
            }
        }
    }
}

// MARK: - Group Edit View
/// Full editing experience for an existing ContactGroup.
struct GroupEditView: View {
    @Environment(\.dismiss) private var dismiss

    // Local mutable copy; committed only on Save.
    @State private var draft: ContactGroup
    @State private var showingPicker = false

    let onSave: (ContactGroup) -> Void

    init(group: ContactGroup, onSave: @escaping (ContactGroup) -> Void) {
        _draft = State(initialValue: group)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("Group name", text: $draft.name)
                }

                Section {
                    if draft.members.isEmpty {
                        Text("No members — tap Add People")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.members) { person in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .fontWeight(.medium)
                                if let phone = person.phone, !phone.isEmpty {
                                    Text(phone)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { offsets in
                            draft.members.remove(atOffsets: offsets)
                        }
                    }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                    }
                } header: {
                    HStack {
                        Text("Members")
                        Spacer()
                        Text("\(draft.members.count)")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Swipe left on a member to remove them.")
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            // Use the non-dismissing picker so its dismiss() doesn't
            // bubble up and close this sheet too.
            .sheet(isPresented: $showingPicker) {
                ContactPickerSheet(isPresented: $showingPicker) { picked in
                    let existingIDs = Set(draft.members.map(\.id))
                    draft.members.append(contentsOf: picked.filter { !existingIDs.contains($0.id) })
                }
            }
        }
    }
}

// MARK: - Contact Picker Sheet (non-self-dismissing)
/// Reusable multi-select contacts picker, used anywhere in the app a sheet
/// needs to let the user pick people from Contacts. Dismisses via a
/// `Binding<Bool>` instead of calling `@Environment(\.dismiss)` — which would
/// otherwise propagate up and close the parent sheet (e.g. NewGroupSheet /
/// GroupEditView) as well when presented from inside one.
struct ContactPickerSheet: View {
    @Binding var isPresented: Bool
    let onSelect: ([Person]) -> Void

    @State private var allContacts: [CNContact] = []
    @State private var filtered: [CNContact] = []
    @State private var searchText = ""
    @State private var selectedIdentifiers: Set<String> = []
    @State private var loading = true
    @State private var authDenied = false
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            contactListContent
                .navigationTitle("Select People")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
                .safeAreaInset(edge: .bottom) { addButton }
                .searchable(text: $searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search by name or phone")
                .onChange(of: searchText) { _, _ in applyFilter() }
                .onAppear {
                    if !hasLoaded { hasLoaded = true; Task { await loadContacts() } }
                }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var contactListContent: some View {
        if authDenied {
            ContentUnavailableView {
                Label("Contacts Access Required", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Enable access in Settings › Privacy & Security › Contacts.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if loading {
            ProgressView("Loading contacts…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Contacts" : "No Matches",
                systemImage: "magnifyingglass",
                description: Text(searchText.isEmpty
                    ? "No contacts with phone numbers were found."
                    : "Try a different name or number.")
            )
        } else {
            List(filtered, id: \.identifier) { contact in
                contactRow(for: contact)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(contact) }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func contactRow(for contact: CNContact) -> some View {
        let name = displayName(for: contact)
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        let isSelected = selectedIdentifiers.contains(contact.identifier)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(isSelected ? .semibold : .regular)
                if !phone.isEmpty {
                    Text(phone).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var addButton: some View {
        Button {
            let selected = allContacts.filter { selectedIdentifiers.contains($0.identifier) }
            let persons = selected.map { c in
                Person(name: displayName(for: c), phone: c.phoneNumbers.first?.value.stringValue)
            }
            onSelect(persons)
            isPresented = false   // close via binding, not environment dismiss
        } label: {
            Group {
                if selectedIdentifiers.isEmpty {
                    Text("Add Contacts")
                } else {
                    Text("Add \(selectedIdentifiers.count) Contact\(selectedIdentifiers.count == 1 ? "" : "s")")
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selectedIdentifiers.isEmpty ? Color.secondary : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .disabled(selectedIdentifiers.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: selectedIdentifiers.isEmpty)
    }

    // MARK: Data

    private func loadContacts() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                await MainActor.run { authDenied = true; loading = false }
                return
            }
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            let req = CNContactFetchRequest(keysToFetch: keys)
            req.sortOrder = .userDefault

            // enumerateContacts is a synchronous, blocking call — safe to run
            // directly here since this async function already executes off the
            // main actor. (Previously this bounced to a manual background queue
            // via a continuation, sharing a mutable array across that boundary.)
            var temp: [CNContact] = []
            try store.enumerateContacts(with: req) { c, _ in
                if !c.phoneNumbers.isEmpty { temp.append(c) }
            }
            await MainActor.run { allContacts = temp; loading = false; applyFilter() }
        } catch {
            print("Contacts fetch failed: \(error)")
            await MainActor.run { loading = false }
        }
    }

    private func applyFilter() {
        guard !searchText.isEmpty else { filtered = allContacts; return }
        let q = searchText.lowercased()
        filtered = allContacts.filter { c in
            let name = displayName(for: c).lowercased()
            let phone = c.phoneNumbers.first?.value.stringValue
                .replacingOccurrences(of: " ", with: "") ?? ""
            return name.contains(q) || phone.contains(q.replacingOccurrences(of: " ", with: ""))
        }
    }

    private func toggle(_ contact: CNContact) {
        if selectedIdentifiers.contains(contact.identifier) {
            selectedIdentifiers.remove(contact.identifier)
        } else {
            selectedIdentifiers.insert(contact.identifier)
        }
    }

    private func displayName(for c: CNContact) -> String {
        [c.givenName, c.familyName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Group Picker Sheet
/// Presents the list of saved contact groups and lets the user pick one to
/// add all its members to the current bill.
struct GroupPickerSheet: View {
    let groups: [ContactGroup]
    let onSelect: (ContactGroup) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(groups) { group in
                Button {
                    onSelect(group)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(group.members.map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Save Bill People As Group Sheet
/// Sheet that lets the user save the current bill's people as a new contact group.
struct SaveBillPeopleAsGroupSheet: View {
    let people: [Person]
    @EnvironmentObject private var groupsVM: ContactGroupsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Dinner Friends", text: $groupName)
                }
                Section("Members (\(people.count))") {
                    ForEach(people) { person in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .fontWeight(.medium)
                            if let phone = person.phone, !phone.isEmpty {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Save as Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        groupsVM.addGroup(
                            name: groupName.trimmingCharacters(in: .whitespaces),
                            members: people
                        )
                        dismiss()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

