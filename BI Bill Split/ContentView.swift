// Bill Splitter iOS — Tip, Tax, PDF Export + Receipt Scanning
// iOS 16+ (SwiftUI). Remember to add NSCameraUsageDescription to Info.plist.

import SwiftUI
import UIKit
import Vision
import VisionKit
import UniformTypeIdentifiers
import CoreData
import PDFKit
import Charts
@preconcurrency import PassKit
import ContactsUI
import MapKit
import MultipeerConnectivity

// MARK: - Models
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var phone: String?
    var isBirthday: Bool

    init(id: UUID = UUID(), name: String, phone: String? = nil, isBirthday: Bool = false) {
        self.id = id; self.name = name; self.phone = phone; self.isBirthday = isBirthday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = (try? c.decode(UUID.self,   forKey: .id))   ?? UUID()
        name       = (try? c.decode(String.self, forKey: .name)) ?? ""
        phone      = try? c.decodeIfPresent(String.self, forKey: .phone)
        isBirthday = (try? c.decode(Bool.self,   forKey: .isBirthday)) ?? false
    }

    enum CodingKeys: String, CodingKey { case id, name, phone, isBirthday }
}

struct Item: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var price: Double
    /// People who consumed this item
    var consumers: Set<UUID>
    init(id: UUID = UUID(), name: String, price: Double, consumers: Set<UUID> = []) {
        self.id = id; self.name = name; self.price = price; self.consumers = consumers
    }
}

struct Bill: Identifiable, Codable {
    var id: UUID
    var people: [Person]
    var items: [Item]
    var taxPercent: Double
    var tipPercent: Double
    var isPreTaxCalc: Bool
    var restaurantName: String
    var restaurantAddress: String?
    var date: Date
    var receiptImageData: Data?
    var zelleEmail: String?
    var zellePhone: String?

    init(
        id: UUID = UUID(),
        people: [Person] = [],
        items: [Item] = [],
        taxPercent: Double = 8,
        tipPercent: Double = 18,
        isPreTaxCalc: Bool = true,
        restaurantName: String = "",
        restaurantAddress: String? = nil,
        date: Date = Date(),
        receiptImageData: Data? = nil,
        zelleEmail: String? = nil,
        zellePhone: String? = nil
    ) {
        self.id = id
        self.people = people
        self.items = items
        self.taxPercent = taxPercent
        self.tipPercent = tipPercent
        self.isPreTaxCalc = isPreTaxCalc
        self.restaurantName = restaurantName
        self.restaurantAddress = restaurantAddress
        self.date = date
        self.receiptImageData = receiptImageData
        self.zelleEmail = zelleEmail
        self.zellePhone = zellePhone
    }

    // Tolerant decoder — any missing or unrecognised field falls back to a
    // safe default, so bills saved by older app versions always load cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decode(UUID.self,     forKey: .id))             ?? UUID()
        people         = (try? c.decode([Person].self,  forKey: .people))         ?? []
        items          = (try? c.decode([Item].self,    forKey: .items))           ?? []
        taxPercent     = (try? c.decode(Double.self,    forKey: .taxPercent))     ?? 0
        tipPercent     = (try? c.decode(Double.self,    forKey: .tipPercent))     ?? 0
        isPreTaxCalc   = (try? c.decode(Bool.self,      forKey: .isPreTaxCalc))   ?? true
        restaurantName = (try? c.decode(String.self,    forKey: .restaurantName)) ?? ""
        restaurantAddress = try? c.decodeIfPresent(String.self, forKey: .restaurantAddress)
        date           = (try? c.decode(Date.self,      forKey: .date))           ?? Date()
        receiptImageData = try? c.decodeIfPresent(Data.self,   forKey: .receiptImageData)
        zelleEmail       = try? c.decodeIfPresent(String.self, forKey: .zelleEmail)
        zellePhone       = try? c.decodeIfPresent(String.self, forKey: .zellePhone)
    }

    enum CodingKeys: String, CodingKey {
        case id, people, items, taxPercent, tipPercent, isPreTaxCalc
        case restaurantName, restaurantAddress, date, receiptImageData, zelleEmail, zellePhone
    }
}

// ContactGroup — stored in UserDefaults as JSON, no Core Data needed
struct ContactGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var members: [Person]
}

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
                ToolbarItem(placement: .navigationBarTrailing) {
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
/// Like MultiContactPicker but dismisses via a `Binding<Bool>` instead of
/// calling `@Environment(\.dismiss)` — which would otherwise propagate up
/// and close the parent sheet (NewGroupSheet / GroupEditView) as well.
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
            var temp: [CNContact] = []
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try store.enumerateContacts(with: req) { c, _ in
                            if !c.phoneNumbers.isEmpty { temp.append(c) }
                        }
                        cont.resume()
                    } catch { cont.resume(throwing: error) }
                }
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

// MARK: - Bill Sync Session (Multipeer Connectivity)
/// Thin networking helper — not an ObservableObject. All callbacks arrive on the main thread.
final class BillSyncSession: NSObject {
    private let serviceType = "bi-billsplit"
    private let myPeerID: MCPeerID
    private var mcSession: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    var onBillReceived: ((Bill) -> Void)?
    var onPeersChanged: (([String]) -> Void)?
    var onInvitation: ((String, @escaping (Bool) -> Void) -> Void)?

    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        super.init()
        mcSession.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        mcSession.disconnect()
        DispatchQueue.main.async { self.onPeersChanged?([]) }
    }

    func send(bill: Bill) {
        guard !mcSession.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(bill) else { return }
        try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
    }
}

extension BillSyncSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let names = session.connectedPeers.map { $0.displayName }
        DispatchQueue.main.async { self.onPeersChanged?(names) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let bill = try? JSONDecoder().decode(Bill.self, from: data) else { return }
        DispatchQueue.main.async { self.onBillReceived?(bill) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension BillSyncSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        DispatchQueue.main.async {
            self.onInvitation?(name) { [weak self] accepted in
                invitationHandler(accepted, accepted ? self?.mcSession : nil)
            }
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Sync advertiser error: \(error.localizedDescription)")
    }
}

extension BillSyncSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard !mcSession.connectedPeers.contains(peerID) else { return }
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Sync browser error: \(error.localizedDescription)")
    }
}

// MARK: - ViewModel
@MainActor
final class BillViewModel: ObservableObject {
    // bill uses willSet/didSet (instead of @Published) so we can hook sync.
    var bill: Bill = Bill(people: [], items: [], taxPercent: 8, tipPercent: 18, restaurantName: "", date: Date(), receiptImageData: nil) {
        willSet { objectWillChange.send() }
        didSet {
            guard !isReceivingSync, isSyncActive else { return }
            syncDebounceTask?.cancel()
            syncDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, !self.isReceivingSync else { return }
                self.syncSession.send(bill: self.bill)
            }
        }
    }

    // MARK: Sync state
    struct SyncInvitation: Identifiable {
        let id = UUID()
        let peerName: String
        let respond: (Bool) -> Void
    }
    private let syncSession = BillSyncSession()
    @Published var isSyncActive = false
    @Published var syncPeerNames: [String] = []
    @Published var pendingSyncInvitation: SyncInvitation? = nil
    private var isReceivingSync = false
    private var syncDebounceTask: Task<Void, Never>? = nil

    @Published var savedBills: [Bill] = []
    @Published var isPreTaxCalc: Bool = true
    @Published var restaurantName: String = ""
    private let billsKey = "savedBills"
    private var savedBillEntities: [SavedBillEntity] = []
    
    private let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "BillModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        loadBills()
        syncSession.onBillReceived = { [weak self] received in
            guard let self else { return }
            self.isReceivingSync = true
            self.bill = received
            self.isReceivingSync = false
        }
        syncSession.onPeersChanged = { [weak self] names in
            self?.syncPeerNames = names
        }
        syncSession.onInvitation = { [weak self] peerName, respond in
            self?.pendingSyncInvitation = SyncInvitation(peerName: peerName, respond: respond)
        }
    }

    func toggleSync() {
        if isSyncActive {
            syncSession.stop()
            isSyncActive = false
            syncPeerNames = []
        } else {
            syncSession.start()
            isSyncActive = true
        }
    }


    // MARK: Derived values
    var subtotal: Double { bill.items.reduce(0) { $0 + $1.price } }
    var taxAmount: Double { subtotal * bill.taxPercent / 100.0 }
    var tipAmount: Double { (subtotal  + (isPreTaxCalc ? 0 : taxAmount)) * bill.tipPercent / 100.0 }
    var grandTotal: Double { subtotal + taxAmount + tipAmount }

    /// Per-person share for items (before tax/tip), accounting for shared items and birthday people.
    /// Birthday people pay $0; their item costs are absorbed by the non-birthday consumers.
    func preTaxShare(for personID: UUID) -> Double {
        let birthdayIDs = Set(bill.people.filter { $0.isBirthday }.map { $0.id })
        let nonBirthdayIDs = Set(bill.people.filter { !$0.isBirthday }.map { $0.id })

        if birthdayIDs.contains(personID) { return 0 }

        return bill.items.reduce(0.0) { partial, item in
            guard !item.consumers.isEmpty else { return partial }
            let effectiveConsumers = birthdayIDs.isEmpty
                ? item.consumers
                : item.consumers.subtracting(birthdayIDs)
            if effectiveConsumers.isEmpty {
                // All consumers are birthday people — split cost among every non-birthday person
                guard !nonBirthdayIDs.isEmpty, nonBirthdayIDs.contains(personID) else { return partial }
                return partial + item.price / Double(nonBirthdayIDs.count)
            } else {
                guard effectiveConsumers.contains(personID) else { return partial }
                return partial + item.price / Double(effectiveConsumers.count)
            }
        }
    }

    func toggleBirthday(for personID: UUID) {
        guard let idx = bill.people.firstIndex(where: { $0.id == personID }) else { return }
        bill.people[idx].isBirthday.toggle()
    }

    /// Distribute tax and tip proportionally to each person's pre-tax share.
    func totalForPerson(_ personID: UUID) -> (preTax: Double, tax: Double, tip: Double, total: Double) {
        let share = preTaxShare(for: personID)
        if subtotal <= 0 { return (0, 0, 0, 0) }
        let ratio = share / subtotal
        let tax = taxAmount * ratio
        let tip = tipAmount * ratio
        return (share, tax, tip, share + tax + tip)
    }
    
    func attachReceiptImage(_ image: UIImage) {
        // Iteratively reduce JPEG quality to keep the blob under ~1 MB so it
        // doesn't truncate the JSON stored in Core Data.
        let maxBytes = 1_000_000
        var quality: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.1 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        bill.receiptImageData = data
    }

    // MARK: - Functions
    func addPerson(name: String, phone: String? = nil) {
        bill.people.append(Person(name: name, phone: phone?.isEmpty == true ? nil : phone))
    }
    func removePeople(at offsets: IndexSet) {
        let ids = offsets.map { bill.people[$0].id }
        bill.items = bill.items.map { item in
            var copy = item
            copy.consumers.subtract(ids)
            return copy
        }
        bill.people.remove(atOffsets: offsets)
    }

    func addItem(name: String, price: Double) { bill.items.append(Item(name: name, price: price)) }
    func removeItems(at offsets: IndexSet) { bill.items.remove(atOffsets: offsets) }
    func updateItem(_ updated: Item) {
        guard let idx = bill.items.firstIndex(where: { $0.id == updated.id }) else { return }
        bill.items[idx] = updated
    }

    func toggleConsumer(item: Item, person: Person) {
        guard let idx = bill.items.firstIndex(where: { $0.id == item.id }) else { return }
        if bill.items[idx].consumers.contains(person.id) {
            bill.items[idx].consumers.remove(person.id)
        } else {
            bill.items[idx].consumers.insert(person.id)
        }
    }
    
    func saveCurrentBill() {
            guard !bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty else {
                    print("Restaurant name is required.")
                    return
                }
            let context = container.viewContext
//            var entity = searchBill(restaurantName: bill.restaurantName, date: bill.date, context: context)
            var entity = searchBillById(billId: bill.id, context: context)
        
            if entity == nil {
                entity = SavedBillEntity(context: context)
            }
            //let entity = SavedBillEntity(context: context)
            if let data = try? JSONEncoder().encode(bill) {
                entity!.billData = data
            }
            do {
                try context.save()
                loadBills()
            } catch {
                print("Failed to save bill: \(error.localizedDescription)")
            }
        }

        private func loadBills() {
            let request = NSFetchRequest<SavedBillEntity>(entityName: "SavedBillEntity")
            do {
                let entities = try container.viewContext.fetch(request)
                savedBillEntities = entities
                savedBills = entities.compactMap { entity in
                    if let data = entity.billData, let bill = try? JSONDecoder().decode(Bill.self, from: data) {
                        return bill
                    }
                    return nil
                }
            } catch {
                print("Failed to load bills: \(error.localizedDescription)")
            }
        }

    func deleteBill(at offsets: IndexSet) {
            let context = container.viewContext
            for index in offsets {
                let entity = savedBillEntities[index]
                context.delete(entity)
            }
            do {
                try context.save()
                loadBills()
            } catch {
                print("Failed to delete bill: \(error.localizedDescription)")
            }
        }
    func clearCurrentBill() {
        bill = Bill(people: [], items: [], taxPercent: 8, tipPercent: 18, restaurantName: "", date: Date(), receiptImageData: nil)
    }
    
    func searchBill(restaurantName: String, date: Date, context: NSManagedObjectContext) -> SavedBillEntity? {
        let request: NSFetchRequest<SavedBillEntity> = SavedBillEntity.fetchRequest()
        do {
            let results = try context.fetch(request)
            for entity in results {
                if let data = entity.billData {
                    do {
                        let bill = try JSONDecoder().decode(Bill.self, from: data)
                        if bill.restaurantName.lowercased() == restaurantName.lowercased() && Calendar.current.isDate(bill.date, inSameDayAs: date) {
                            return entity
                        }
                    } catch {
                        print("Failed to decode bill during search: \(error)")
                    }
                }
            }
        } catch {
            print("Search fetch failed: \(error)")
        }
        return nil
    }

    func searchBillById(billId: UUID, context: NSManagedObjectContext) -> SavedBillEntity? {
        let request: NSFetchRequest<SavedBillEntity> = SavedBillEntity.fetchRequest()
        do {
            let results = try context.fetch(request)
            for entity in results {
                if let data = entity.billData {
                    do {
                        let bill = try JSONDecoder().decode(Bill.self, from: data)
                        if bill.id == billId {
                            return entity
                        }
                    } catch {
                        print("Failed to decode bill during search: \(error)")
                    }
                }
            }
        } catch {
            print("Search fetch failed: \(error)")
        }
        return nil
    }
    
    // MARK: - Bill Sharing (deep link)

    /// Encodes the current bill as a `billsplit://import?data=<base64>` URL
    /// that any device running this app can open to load the full bill.
    func shareBillURL() -> URL? {
        guard let jsonData = try? JSONEncoder().encode(bill) else { return nil }
        let base64 = jsonData.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "billsplit://import?data=\(base64)")
    }

    // Export all saved bills to a JSON file URL.
    // Uses the ViewModel's own container — no external context needed.
    func exportAllBills() -> URL? {
        let request: NSFetchRequest<SavedBillEntity> = SavedBillEntity.fetchRequest()
        do {
            let results = try container.viewContext.fetch(request)
            let billsData = results.compactMap { $0.billData }
            let bills = billsData.compactMap { try? JSONDecoder().decode(Bill.self, from: $0) }
            let jsonData = try JSONEncoder().encode(bills)

            // Save JSON file to temporary directory
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("exported_bills.json")
            try jsonData.write(to: url)
            return url
        } catch {
            print("Failed to export bills: \(error)")
            return nil
        }
    }
    // MARK: - Sample data
    func loadSample() {
        bill.restaurantName = "My Restaurant"
        bill.people = ["Alejandro","Yanely","Margarita","Ricardo","Douglas","Jose","Rolando","Max","Lesli","Lazaro"].map { Person(name: $0) }
        let pIDs = bill.people.map { $0.id }
        bill.items = [
            Item(name: "Margherita Pizza", price: 18.0, consumers: Set([pIDs[0], pIDs[1]])),
            Item(name: "Pasta", price: 16.0, consumers: Set([pIDs[1]])),
            Item(name: "Salad", price: 12.0, consumers: Set([pIDs[0], pIDs[1], pIDs[2]])),
            Item(name: "Soda", price: 4.5, consumers: Set([pIDs[2]])),
            Item(name: "Lunch Special", price: 21.50, consumers: Set([pIDs[3]])),
            Item(name: "Carbonara", price: 18.99, consumers: Set([pIDs[4]])),
            Item(name: "BBQ Ranchero", price: 16.99, consumers: Set([pIDs[6]])),
            Item(name: "Shrimp Carbonara", price: 25.50, consumers: Set([pIDs[9]])),
            Item(name: "Morton Steak Salad", price: 27.75, consumers: Set([pIDs[8]])),
            Item(name: "Filet Mignon", price: 30.50, consumers: Set([pIDs[7]])),
            Item(name: "Burger", price: 17, consumers: Set([pIDs[5]])),
            Item(name: "Wine Bottle", price: 42.0, consumers: Set([pIDs[0], pIDs[1],pIDs[2], pIDs[3], pIDs[4],pIDs[8],pIDs[9]])),
        ]
        bill.taxPercent = 8
        bill.tipPercent = 20
        bill.date = Date()
    }
}

// MARK: - App
@main
struct BillSplitterApp: App {
    @StateObject private var model = BillViewModel()
    @StateObject private var groupsModel = ContactGroupsViewModel()
    /// "light", "dark", or "system" — persisted across launches.
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(groupsModel)
                .environment(\.appearanceMode, $appearanceMode)
                .preferredColorScheme(appearanceMode.colorScheme)
                // Handle deep-link bill imports (billsplit://import?data=<base64>)
                .onOpenURL { url in
                    guard
                        url.scheme == "billsplit",
                        url.host == "import",
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
                        let jsonData = Data(base64Encoded: dataParam),
                        let importedBill = try? JSONDecoder().decode(Bill.self, from: jsonData)
                    else { return }

                    model.bill = importedBill
                }
        }
    }
}

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.stars"
        }
    }
}

// MARK: - Environment Key for AppearanceMode binding
private struct AppearanceModeKey: EnvironmentKey {
    static let defaultValue: Binding<AppearanceMode> = .constant(.system)
}

extension EnvironmentValues {
    var appearanceMode: Binding<AppearanceMode> {
        get { self[AppearanceModeKey.self] }
        set { self[AppearanceModeKey.self] = newValue }
    }
}


// MARK: - Content View
struct ContentView: View {
    @State private var selectedTab = 0
    @Environment(\.appearanceMode) private var appearanceMode

    var body: some View {
        TabView(selection: $selectedTab) {
            CurrentBillView()
                .tabItem {
                    Label("Bill", systemImage: "doc.text")
                }
                .tag(0)

            SavedBillsView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Saved Bills", systemImage: "tray.full")
                }
                .tag(1)

            SpendingChartView()
                .tabItem {
                    Label("Spending", systemImage: "chart.bar")
                }
                .tag(2)

            ContactGroupsView()
                .tabItem {
                    Label("Groups", systemImage: "folder")
                }
                .tag(3)

            AppearanceSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
    }
}

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @Environment(\.appearanceMode) private var appearanceMode

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceModeRow(mode)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("\"System\" follows your iPhone's appearance setting in Settings → Display & Brightness.")
                }

                Section("Support") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("How to Use This App", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func appearanceModeRow(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceMode.wrappedValue == mode
        let iconForeground: Color = isSelected ? .white : .accentColor
        let iconBackground: Color = isSelected ? .accentColor : Color(.secondarySystemGroupedBackground)

        return Button {
            appearanceMode.wrappedValue = mode
        } label: {
            HStack(spacing: 14) {
                modeIcon(systemName: mode.icon, foreground: iconForeground, background: iconBackground)
                Text(mode.label)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func modeIcon(systemName: String, foreground: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
    }
}

// MARK: - Help View
struct HelpView: View {
    var body: some View {
        List {
            // MARK: Getting Started
            Section {
                DisclosureGroup {
                    helpText("""
                    1. Go to the **Bill** tab.
                    2. Enter the restaurant name (required), and optionally an address and date.
                    3. Add people using the manual field, Contacts, or a saved Group.
                    4. Add items and assign them to the people who ordered them.
                    5. Adjust tip and tax as needed.
                    6. Tap **Save** — the bill appears in the History tab.
                    """)
                } label: {
                    helpRow(icon: "list.bullet.clipboard", color: .blue, title: "Getting Started")
                }
            } header: {
                Text("Overview")
            }

            // MARK: Restaurant
            Section("Restaurant") {
                DisclosureGroup {
                    helpText("""
                    • **Name** — required before you can save, share, or export.
                    • **Address** — optional. Tap the 🔍 magnifying glass to search for the restaurant by name using Maps. Tap a result to fill the address field automatically. Once an address is saved, the icon switches to a 🗺 map button — tap it to open the location in Apple Maps.
                    • **Date** — defaults to today; tap to change it.
                    """)
                } label: {
                    helpRow(icon: "fork.knife", color: .orange, title: "Restaurant Info")
                }
            }

            // MARK: People
            Section("People") {
                DisclosureGroup {
                    helpText("""
                    Add people to the bill using any of these methods:
                    • **Type manually** — enter a name (and optional phone number) then tap +.
                    • **Contacts** (blue button) — pick one or more people from your address book.
                    • **Add Group** (indigo button) — import everyone from a saved Contact Group in one tap. Anyone already in the bill by name is skipped automatically.
                    • **Save as Group** (teal button, visible when at least one person is added) — saves the current list of people as a new reusable Contact Group for future bills.
                    • Swipe left on a person to remove them from the bill.
                    """)
                } label: {
                    helpRow(icon: "person.2", color: .indigo, title: "Adding People")
                }

                DisclosureGroup {
                    helpText("""
                    Go to the **Groups** tab to create and manage reusable lists of people.
                    • Tap **+** to create a new group — give it a name and add members from your Contacts.
                    • Tap a group to edit its name or members.
                    • Swipe left to delete a group.
                    • Groups saved from a bill (via "Save as Group") also appear here.
                    """)
                } label: {
                    helpRow(icon: "folder.badge.person.crop", color: .purple, title: "Contact Groups")
                }

                DisclosureGroup {
                    helpText("""
                    Mark someone as the birthday person to make their share $0 — covered by everyone else.
                    • Tap the **Birthday** capsule button on any person's row to flag them. Tap **Remove Birthday** to unmark.
                    • Multiple people can be marked at the same time.
                    • The 🎂 icon and pink highlight appear on their row; payment buttons are hidden since they owe nothing.
                    • **How the split works:** items the birthday person ordered are redistributed to the non-birthday consumers of those items. If an item was ordered exclusively by birthday people, its cost is split among all non-birthday people in the bill.
                    • Birthday indicators appear in the Share Bill preview, on both pages of the exported PDF, in the Saved Bills list, and in the Analytics tab.
                    """)
                } label: {
                    helpRow(icon: "birthday.cake", color: .pink, title: "Birthday Person 🎂")
                }
            }

            // MARK: Items
            Section("Items") {
                DisclosureGroup {
                    helpText("""
                    • Tap **+ Add Item** to add a dish or drink with a name and price.
                    • Tap an item to edit its name, price, or who shared it.
                    • Assign consumers by toggling each person's name in the item editor — the cost is split equally among all selected people.
                    • Swipe left on an item to delete it.
                    • An item with no assigned consumers is split among all non-birthday people in the bill.
                    """)
                } label: {
                    helpRow(icon: "cart", color: .green, title: "Adding & Assigning Items")
                }
            }

            // MARK: Tip & Tax
            Section("Tip & Tax") {
                DisclosureGroup {
                    helpText("""
                    • Adjust the **Tip %** and **Tax %** sliders in the bill form.
                    • Toggle **Pre-tax tip** to calculate tip on the subtotal (before tax), or off to calculate tip on the post-tax total — varies by country convention.
                    • Each person's share updates instantly as you move the sliders.
                    """)
                } label: {
                    helpRow(icon: "percent", color: .teal, title: "Tip & Tax")
                }
            }

            // MARK: Payments
            Section("Payments") {
                DisclosureGroup {
                    helpText("""
                    Collect payment from each person directly in the app:
                    • **Apple Pay** — tap the Apple Pay button on a person's row to request their share via Apple Pay contactless payment.
                    • **Zelle** — enter a Zelle email or phone number in the People section. Each person's row shows a Zelle button that opens the Zelle app pre-filled with their owed amount and a note.
                    • Birthday-flagged people show $0.00 and no payment buttons since they owe nothing.
                    """)
                } label: {
                    helpRow(icon: "creditcard", color: .mint, title: "Collecting Payment")
                }
            }

            // MARK: Receipt Scanning & Photos
            Section("Receipt & Photos") {
                DisclosureGroup {
                    helpText("""
                    • **Scan Receipt** — uses the camera and on-device OCR to detect item names and prices from a physical receipt automatically. Review and correct any misread items before adding them.
                    • **Attach Photo** — tap to attach an image of the receipt to the bill. A prompt lets you choose between **Take Photo** (camera) or **Choose from Gallery** (photo library). The attached image appears on page 2 of the exported PDF.
                    • Scanning works best on flat, well-lit receipts with clear printed text.
                    """)
                } label: {
                    helpRow(icon: "camera.viewfinder", color: .red, title: "Scanning & Attaching Photos")
                }
            }

            // MARK: Sharing & Export
            Section("Sharing & Export") {
                DisclosureGroup {
                    helpText("""
                    • **Export PDF** — generates a two-page PDF: page 1 shows the participants (with 🎂 indicators) and itemised list; page 2 shows each person's share breakdown and the attached receipt photo if any. Share via Messages, Mail, AirDrop, etc.
                    • **Share Bill** — sends a deep-link URL that another iPhone with this app can open to load the exact same bill (people, items, birthday flags, tip, and tax).
                    • The **Share Bill preview** shows a summary card including any birthday people flagged on the bill.
                    • **History tab** — view all saved bills. Tap a bill to load it, swipe left to share it, or swipe to delete.
                    • **Export All Bills** — in the History tab, export every saved bill as a single JSON file for backup.
                    """)
                } label: {
                    helpRow(icon: "square.and.arrow.up", color: .blue, title: "Sharing & Exporting")
                }
            }

            // MARK: Saved Bills (History)
            Section("History") {
                DisclosureGroup {
                    helpText("""
                    The **Saved Bills** tab lists all your past bills with their total amount.
                    • **Filter by person** — use the search bar to type a name. The list narrows to bills that include that person, and each row shows that person's individual share for the bill.
                    • **Birthday indicator** — bills where someone was flagged as birthday show a pink 🎂 line with their name.
                    • Tap a bill to load it into the Bill tab for review or editing.
                    • Swipe left on a row to share the bill via deep-link.
                    • Swipe right on a row to delete it (deletion respects the active filter).
                    """)
                } label: {
                    helpRow(icon: "tray.full", color: .brown, title: "Saved Bills & History")
                }
            }

            // MARK: Analytics
            Section("Analytics") {
                DisclosureGroup {
                    helpText("""
                    The **Analytics** tab shows spending summaries across all your saved bills.
                    • **Over Time** — a line chart of total bill amounts over your chosen date range (1 month, 3 months, 6 months, or all time).
                    • **Top Spenders** — a ranked list and bar chart of the top 10 people by total spend across all bills. Each entry shows:
                      – Total spent across all bills
                      – Number of bills they appeared in
                      – Average spent per bill
                    • Birthday-flagged shares ($0) are correctly excluded from totals, so they don't skew the rankings.
                    """)
                } label: {
                    helpRow(icon: "chart.bar", color: .yellow, title: "Analytics")
                }
            }

            // MARK: Settings
            Section("Settings") {
                DisclosureGroup {
                    helpText("""
                    • **Appearance** — choose Light, Dark, or System to match your iPhone's display setting in Settings → Display & Brightness.
                    • **How to Use This App** — you're reading it!
                    """)
                } label: {
                    helpRow(icon: "gearshape", color: .gray, title: "App Settings")
                }
            }
        }
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.large)
    }

    private func helpRow(icon: String, color: Color, title: String) -> some View {
        Label {
            Text(title).fontWeight(.medium)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(color))
        }
    }

    private func helpText(_ markdown: String) -> some View {
        Text(LocalizedStringKey(markdown))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Spending Chart View
struct SpendingChartView: View {

    @EnvironmentObject var vm: BillViewModel

    /// Which sub-page is showing
    enum SpendingTab { case overTime, topSpenders }
    @State private var activeTab: SpendingTab = .overTime

    // MARK: Time range filter
    enum TimeRange: String, CaseIterable, Identifiable {
        case week       = "1W"
        case month      = "1M"
        case threeMonths = "3M"
        case sixMonths  = "6M"
        case year       = "1Y"
        case all        = "All"
        var id: String { rawValue }

        var cutoffDate: Date? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .week:        return cal.date(byAdding: .day,   value: -7,   to: now)
            case .month:       return cal.date(byAdding: .month, value: -1,   to: now)
            case .threeMonths: return cal.date(byAdding: .month, value: -3,   to: now)
            case .sixMonths:   return cal.date(byAdding: .month, value: -6,   to: now)
            case .year:        return cal.date(byAdding: .year,  value: -1,   to: now)
            case .all:         return nil
            }
        }
    }
    @State private var selectedRange: TimeRange = .all

    // MARK: Bills over time series (filtered)
    private var series: [(date: Date, amount: Double)] {
        let cutoff = selectedRange.cutoffDate
        return vm.savedBills
            .filter { cutoff == nil || $0.date >= cutoff! }
            .map { ($0.date, $0.totalAmount) }
            .sorted { $0.date < $1.date }
    }

    // MARK: Top-10 spenders across all saved bills
    private var topSpenders: [(name: String, total: Double, billCount: Int)] {
        // Aggregate each person's share across every saved bill.
        // Key: person name (best proxy we have without a global person ID).
        var totals: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for bill in vm.savedBills {
            let sub = bill.items.reduce(0) { $0 + $1.price }
            guard sub > 0 else { continue }
            let tax = sub * bill.taxPercent / 100
            let tip = sub * bill.tipPercent / 100
            for person in bill.people {
                // Replicate the same proportional split logic used in BillViewModel
                let preTax = bill.items.reduce(0.0) { partial, item in
                    guard item.consumers.contains(person.id), !item.consumers.isEmpty else { return partial }
                    return partial + item.price / Double(item.consumers.count)
                }
                guard preTax > 0 else { continue }
                let ratio = preTax / sub
                let share = preTax + tax * ratio + tip * ratio
                totals[person.name, default: 0] += share
                counts[person.name, default: 0] += 1
            }
        }
        return totals
            .map { (name: $0.key, total: $0.value, billCount: counts[$0.key, default: 0]) }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $activeTab) {
                    Text("Over Time").tag(SpendingTab.overTime)
                    Text("Top Spenders").tag(SpendingTab.topSpenders)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)

                if vm.savedBills.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Saved Bills",
                        systemImage: "tray",
                        description: Text("Save a bill to see spending data.")
                    )
                    Spacer()
                } else {
                    switch activeTab {
                    case .overTime:  overTimeView
                    case .topSpenders: topSpendersView
                    }
                }
            }
            .navigationTitle("Spending")
        }
    }

    // MARK: - Over-Time Chart
    private var overTimeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Time range filter
                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 16)

                if series.isEmpty {
                    ContentUnavailableView(
                        "No Bills in Range",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No saved bills fall within the selected period.")
                    )
                    .padding(.top, 32)
                } else {
                    Text("Bill Totals — \(selectedRange.rawValue == "All" ? "All Time" : "Last \(selectedRange.rawValue)")")
                        .font(.headline)
                        .padding(.horizontal)

                    Chart {
                        ForEach(Array(series.enumerated()), id: \.offset) { _, entry in
                            BarMark(
                                x: .value("Date", entry.date),
                                y: .value("Amount", entry.amount)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                        }
                    }
                    .frame(height: 300)
                    .padding(.horizontal)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .chartYAxis {
                        AxisMarks(format: Decimal.FormatStyle.Currency(code: "USD"))
                    }
                    .animation(.easeInOut(duration: 0.25), value: selectedRange.id)

                    // Summary cards
                    let grandTotal = series.reduce(0) { $0 + $1.amount }
                    let avg = series.isEmpty ? 0 : grandTotal / Double(series.count)

                    HStack(spacing: 12) {
                        summaryCard(title: "Total Spent", value: grandTotal)
                        summaryCard(title: "Avg per Bill", value: avg)
                        summaryCard(title: "Bills", value: Double(series.count), isCurrency: false)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Top Spenders List
    private var topSpendersView: some View {
        List {
            Section {
                if topSpenders.isEmpty {
                    Text("No spending data yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(topSpenders.enumerated()), id: \.offset) { idx, entry in
                        HStack(spacing: 12) {
                            // Rank badge
                            ZStack {
                                Circle()
                                    .fill(rankColor(for: idx))
                                    .frame(width: 32, height: 32)
                                Text("\(idx + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .fontWeight(idx < 3 ? .semibold : .regular)
                                let avg = entry.billCount > 0 ? entry.total / Double(entry.billCount) : 0
                                Text("\(entry.billCount) bill\(entry.billCount == 1 ? "" : "s") · avg \(avg.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(entry.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                .fontWeight(.semibold)
                                .foregroundStyle(idx == 0 ? Color.accentColor : .primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Top 10 Spenders (all bills)")
            } footer: {
                Text("Amounts reflect each person's proportional share of items, tax, and tip.")
                    .font(.caption)
            }

            // Bar chart of top spenders
            if !topSpenders.isEmpty {
                Section("Breakdown") {
                    Chart {
                        ForEach(Array(topSpenders.enumerated()), id: \.offset) { idx, entry in
                            BarMark(
                                x: .value("Amount", entry.total),
                                y: .value("Name", entry.name)
                            )
                            .foregroundStyle(rankColor(for: idx).gradient)
                            .annotation(position: .trailing) {
                                Text(entry.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: CGFloat(topSpenders.count) * 36 + 24)
                    .chartXAxis(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func summaryCard(title: String, value: Double, isCurrency: Bool = true) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isCurrency {
                Text(value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(Int(value).description)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0:  return .yellow
        case 1:  return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 2:  return Color(red: 0.8, green: 0.5, blue: 0.2)    // bronze
        default: return .accentColor
        }
    }
}

// Bill-level totals used by the chart
extension Bill {
    var subtotal: Double { items.reduce(0) { $0 + $1.price } }
    var totalAmount: Double {
        let tax = subtotal * taxPercent / 100
        let tip = subtotal * tipPercent / 100
        return subtotal + tax + tip
    }
}

// MARK: - Zoomable Image Viewer
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1.0, lastScale * value)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        // Only allow panning when zoomed in
                                        guard scale > 1.0 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .background(Color.black)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("Pinch to zoom • Double-tap to fit")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Current Bill View
struct CurrentBillView: View {
    @EnvironmentObject var vm: BillViewModel
    @State private var showingScanner = false
    @State private var exportURL: URL?
    @State private var showingReceipt = false
    @State private var showingImagePicker = false
    @State private var showingAttachOptions = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var showingReceiptZoom = false
    @State private var isParsingReceipt = false
    @State private var parsingError: String? = nil
    @State private var isPeopleExpanded: Bool = true
    /// Owned here so the sheet sits outside the Form and avoids Group/sheet conflicts.
    @State private var itemToEdit: Item? = nil
    @State private var billShareItem: IdentifiableURL? = nil
    @State private var showingRestaurantSearch = false

    var body: some View {
        NavigationView {
            VStack {
                // Parsing progress banner
                if isParsingReceipt {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading receipt with AI…")
                            .font(.subheadline)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
                if let errorMsg = parsingError {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Live sync status banner
                if vm.isSyncActive {
                    HStack(spacing: 8) {
                        if vm.syncPeerNames.isEmpty {
                            ProgressView().scaleEffect(0.75)
                            Text("Looking for nearby devices…")
                        } else {
                            Image(systemName: "person.2.wave.2.fill")
                                .foregroundStyle(.green)
                            Text(vm.syncPeerNames.joined(separator: ", "))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("· \(vm.syncPeerNames.count) connected")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { vm.toggleSync() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                Form {
                    Section("Restaurant") {
                        TextField("Enter restaurant name", text: $vm.bill.restaurantName)
                            .autocapitalization(.words)
                        HStack {
                            TextField("Address (optional)", text: Binding(
                                get: { vm.bill.restaurantAddress ?? "" },
                                set: { vm.bill.restaurantAddress = $0.isEmpty ? nil : $0 }
                            ))
                            .autocapitalization(.words)
                            if let address = vm.bill.restaurantAddress, !address.isEmpty {
                                Button {
                                    let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    if let url = URL(string: "maps://?q=\(encoded)") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Image(systemName: "map.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Button {
                                    showingRestaurantSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        DatePicker("Date", selection: $vm.bill.date, displayedComponents: .date)
                    }
                    Section {
                        if isPeopleExpanded {
                            PeopleEditor()
                        }
                    } header: {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPeopleExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("People")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                if !isPeopleExpanded && !vm.bill.people.isEmpty {
                                    Text("(\(vm.bill.people.count))")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: isPeopleExpanded ? "chevron.up" : "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Section("Items") { ItemsEditor(itemToEdit: $itemToEdit) }
                    Section("Tax & Tip") {
                        HStack {
                            Text("Tax (%)")
                            Spacer()
                            TextField("0", value: $vm.bill.taxPercent, format: .number.precision(.fractionLength(3)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Tip (%)")
                            Spacer()
                            TextField("0", value: $vm.bill.tipPercent, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    SummarySection()
                    if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                        Section("Attached Receipt") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                                .onTapGesture { showingReceiptZoom = true }
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Bill Split")
            .toolbar {
                // Leading: preview receipt + sync toggle + overflow menu
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { showingReceipt = true }) {
                        Image(systemName: "eye")
                    }

                    Button { vm.toggleSync() } label: {
                        Image(systemName: vm.isSyncActive
                              ? "antenna.radiowaves.left.and.right.circle.fill"
                              : "antenna.radiowaves.left.and.right.circle")
                            .foregroundStyle(vm.isSyncActive ? Color.green : Color.primary)
                            .symbolEffect(.pulse, options: .repeating, isActive: vm.isSyncActive && vm.syncPeerNames.isEmpty)
                    }

                    Menu {
                        Button { vm.loadSample() } label: {
                            Label("Load Sample", systemImage: "doc.badge.plus")
                        }
                        Button { showingScanner = true } label: {
                            Label("Scan Receipt", systemImage: "document.viewfinder.fill")
                        }
                        Button { showingAttachOptions = true } label: {
                            Label("Attach Photo", systemImage: "camera")
                        }
                        Divider()
                        Button(role: .destructive) { vm.clearCurrentBill() } label: {
                            Label("Clear Bill", systemImage: "xmark.circle")
                        }
                        Button {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        } label: {
                            Label("Dismiss Keyboard", systemImage: "keyboard.chevron.compact.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                // Trailing: primary actions always visible
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.saveCurrentBill() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        if let url = vm.shareBillURL() {
                            billShareItem = IdentifiableURL(url: url)
                        }
                    } label: {
                        Label("Share Bill", systemImage: "person.2.wave.2")
                    }
                    .disabled(vm.bill.people.isEmpty || vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button { exportPDF2() } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.bill.people.isEmpty || vm.bill.restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            // All sheet presentations anchored here on the NavigationView, not on toolbar buttons
            .sheet(isPresented: $showingReceipt) {
                VStack(alignment: .leading, spacing: 5) {
                    ScrollView {
                        ReceiptView()
                        ReceiptView2()
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .init(horizontal: .leading, vertical: .top))
            }
            .fullScreenCover(isPresented: $showingReceiptZoom) {
                if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                    ZoomableImageView(image: uiImage)
                }
            }
        }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerView { lines in
                    guard !lines.isEmpty else { return }
                    isParsingReceipt = true
                    parsingError = nil
                    Task {
                        let items = await ReceiptParser.parse(lines: lines)
                        await MainActor.run {
                            isParsingReceipt = false
                            if items.isEmpty {
                                parsingError = "No items found. Try scanning again or add items manually."
                            } else {
                                for item in items {
                                    vm.addItem(name: item.name, price: item.price)
                                }
                            }
                        }
                    }
                }
            }
            .confirmationDialog("Attach Photo", isPresented: $showingAttachOptions, titleVisibility: .visible) {
                Button("Take Photo") {
                    imagePickerSource = .camera
                    showingImagePicker = true
                }
                Button("Choose from Gallery") {
                    imagePickerSource = .photoLibrary
                    showingImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: imagePickerSource) { image in
                    if let image = image {
                        vm.attachReceiptImage(image)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(activityItems: [exportURL]) }
            }
            .sheet(item: $itemToEdit) { item in
                ItemEditSheet(item: item) { updated in
                    vm.updateItem(updated)
                }
            }
            .sheet(item: $billShareItem) { item in
                BillShareSheet(bill: vm.bill, shareURL: item.url)
            }
            .sheet(isPresented: $showingRestaurantSearch) {
                RestaurantSearchSheet(restaurantName: vm.bill.restaurantName) { address in
                    vm.bill.restaurantAddress = address
                }
            }
            .alert("Live Sync Invitation", isPresented: Binding(
                get: { vm.pendingSyncInvitation != nil },
                set: { _ in }
            )) {
                Button("Accept") {
                    vm.pendingSyncInvitation?.respond(true)
                    vm.pendingSyncInvitation = nil
                }
                Button("Decline", role: .cancel) {
                    vm.pendingSyncInvitation?.respond(false)
                    vm.pendingSyncInvitation = nil
                }
            } message: {
                if let inv = vm.pendingSyncInvitation {
                    Text("\(inv.peerName) wants to join your live bill session.")
                }
            }

    }

    // MARK: - PDF Export
    func exportPDF() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillSplit_\(UUID().uuidString).pdf")
                     
        let renderer = ImageRenderer(content: ReceiptView().environmentObject(vm))
        
        let page2 = ImageRenderer(content: ReceiptView2().environmentObject(vm))
        #if os(iOS)
        renderer.isOpaque = false
        #endif
        do {
            let data = try await renderer.pdfData(pageSize: CGSize(width: 612, height: 792), // US Letter at 72dpi
                                                  pageMargins: 24)
            try data.write(to: url)
            
            let data2 = try await page2.pdfData(pageSize: CGSize(width: 612, height: 792), // US Letter at 72dpi
                                                pageMargins: 24)
            try data2.write(to: url)
            exportURL = url
        } catch {
            print("PDF export failed: \(error)")
        }
    }
    
    func exportPDF2() {
            let pdfMetaData = [
                kCGPDFContextCreator: "Bill Splitter",
                kCGPDFContextAuthor: "Ricardo Fong"
            ]
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = pdfMetaData as [String: Any]
        
            let pageWidth = 8.5 * 72.0
            let pageHeight = 11 * 72.0
            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

            let data = renderer.pdfData { context in
                context.beginPage()
                let bounds = CGRect(origin: .zero, size: CGSize(width: 612, height: 792))
                let hosting1 = UIHostingController(rootView: ReceiptView().environmentObject(vm))
                hosting1.view.backgroundColor = .white
                hosting1.view.bounds = bounds.insetBy(dx: 24, dy: 24)
                let fitting = hosting1.sizeThatFits(in: bounds.size)
                hosting1.view.bounds.size = CGSize(width: bounds.width - 24 * 2, height: fitting.height)
                hosting1.view.layoutIfNeeded()
                hosting1.view.drawHierarchy(in: hosting1.view.bounds, afterScreenUpdates: true)
                
                // Page 2 - Summary
                context.beginPage()
                let hosting = UIHostingController(rootView: ReceiptView2().environmentObject(vm))
                hosting.view.backgroundColor = .white
                hosting.view.bounds = bounds.insetBy(dx: 24, dy: 24)
                let fitting1 = hosting.sizeThatFits(in: bounds.size)
                hosting.view.bounds.size = CGSize(width: bounds.width - 24 * 2, height: fitting1.height)
                hosting.view.layoutIfNeeded()
                hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
                
                // Page 3 - Receipt Image if available
                if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                    context.beginPage()
                    let maxRect = CGRect(x: 20, y: 20, width: pageRect.width - 40, height: pageRect.height - 40)
                    let aspect = uiImage.size.width / uiImage.size.height
                    var drawRect = maxRect
                    if aspect > maxRect.width / maxRect.height {
                        let newHeight = maxRect.width / aspect
                        drawRect = CGRect(x: maxRect.minX, y: maxRect.minY, width: maxRect.width, height: newHeight)
                    } else {
                        let newWidth = maxRect.height * aspect
                        drawRect = CGRect(x: maxRect.minX, y: maxRect.minY, width: newWidth, height: maxRect.height)
                    }
                    uiImage.draw(in: drawRect)
                }
            }
        let outputFormat = DateFormatter()
        outputFormat.dateFormat = "MM-dd-yyyy"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bill_\(vm.bill.restaurantName)_\(outputFormat.string(from: vm.bill.date)).pdf")
            do {
                try data.write(to: url)
                exportURL = url
            } catch {
                print("Could not save PDF file: \(error)")
            }
        }
}

// MARK: - Bill Share Sheet
/// A polished share sheet that explains the deep-link and lets the user
/// send the current bill to another device that has this app installed.
struct BillShareSheet: View {
    let bill: Bill
    let shareURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var showActivityView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                // Icon + headline
                VStack(spacing: 12) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("Share Bill")
                        .font(.title2.weight(.bold))

                    Text("Send the full bill — people, items, tax & tip — to another device with Bill Splitter installed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Bill summary card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(bill.restaurantName.isEmpty ? "Unnamed Bill" : bill.restaurantName,
                              systemImage: "fork.knife")
                            .font(.headline)
                        Spacer()
                        Text(bill.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack(spacing: 16) {
                        Label("\(bill.people.count) people", systemImage: "person.2")
                        Label("\(bill.items.count) items", systemImage: "list.bullet")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    let birthdayPeople = bill.people.filter { $0.isBirthday }
                    if !birthdayPeople.isEmpty {
                        HStack(spacing: 4) {
                            Text("🎂")
                            Text(birthdayPeople.map { $0.name }.joined(separator: ", ") + " · covered by the group")
                                .foregroundStyle(.pink)
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)

                // Instruction
                VStack(spacing: 6) {
                    Label("How it works", systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Tap Share below and send the link via Messages, Mail, or AirDrop. When the recipient taps it, the bill opens automatically in their app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Share button
                Button {
                    showActivityView = true
                } label: {
                    Label("Share with…", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .navigationTitle("Share Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showActivityView) {
                let restaurantName = bill.restaurantName.isEmpty ? "a bill" : bill.restaurantName
                ShareSheet(activityItems: [
                    shareURL,
                    "Open this link to load '\(restaurantName)' in Bill Splitter."
                ])
            }
        }
    }
}

// MARK: - Saved Bills View
struct SavedBillsView: View {
    @EnvironmentObject var vm: BillViewModel
    @Binding var selectedTab: Int
    @State private var showingExporter = false
    @State private var exportURL: URL?
    @State private var billToShare: Bill? = nil
    @State private var searchText = ""

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredBills: [Bill] {
        guard isFiltering else { return vm.savedBills }
        let query = searchText.lowercased()
        return vm.savedBills.filter { bill in
            bill.people.contains { $0.name.lowercased().contains(query) }
        }
    }

    /// Calculates a named person's proportional share (pre-tax items + tax + tip) in a bill.
    private func personShare(in bill: Bill, query: String) -> Double? {
        let sub = bill.items.reduce(0.0) { $0 + $1.price }
        guard sub > 0,
              let person = bill.people.first(where: { $0.name.lowercased().contains(query) })
        else { return nil }
        let preTax = bill.items.reduce(0.0) { partial, item in
            guard item.consumers.contains(person.id), !item.consumers.isEmpty else { return partial }
            return partial + item.price / Double(item.consumers.count)
        }
        guard preTax > 0 else { return nil }
        let ratio = preTax / sub
        let tax = sub * bill.taxPercent / 100
        let tip = sub * bill.tipPercent / 100
        return preTax + tax * ratio + tip * ratio
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredBills) { bill in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(bill.restaurantName)
                                .font(.headline).foregroundStyle(.blue)
                            Spacer()
                            Text(bill.totalAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Text(bill.date, formatter: dateFormatter)
                            .font(.subheadline).foregroundStyle(.secondary)
                        if isFiltering, let share = personShare(in: bill, query: searchText.lowercased()) {
                            HStack {
                                Text(searchText.trimmingCharacters(in: .whitespaces) + "'s share")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(share, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                    .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(bill.people.map { $0.name }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        let birthdayPeople = bill.people.filter { $0.isBirthday }
                        if !birthdayPeople.isEmpty {
                            HStack(spacing: 4) {
                                Text("🎂")
                                Text(birthdayPeople.map { $0.name }.joined(separator: ", "))
                                    .foregroundStyle(.pink)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                    .onTapGesture {
                        vm.bill = bill
                        selectedTab = 0
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            billToShare = bill
                        } label: {
                            Label("Share", systemImage: "person.2.wave.2")
                        }
                        .tint(.indigo)
                    }
                }
                .onDelete { offsets in
                    // Map filtered-list offsets back to savedBills offsets for deletion.
                    let idsToDelete = Set(offsets.map { filteredBills[$0].id })
                    let originalOffsets = IndexSet(
                        vm.savedBills.indices.filter { idsToDelete.contains(vm.savedBills[$0].id) }
                    )
                    vm.deleteBill(at: originalOffsets)
                }
            }
            .searchable(text: $searchText, prompt: "Filter by person name")
            .navigationTitle("Saved Bills")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Export Bills") {
                        if let url = vm.exportAllBills() {
                            exportURL = url
                            showingExporter = true
                        }
                    }
                }
            }
            .fileExporter(isPresented: $showingExporter, document: ExportedFile(url: exportURL), contentType: .json, defaultFilename: "bills_export") { result in
                switch result {
                case .success(let url):
                    print("Exported to \(url)")
                case .failure(let error):
                    print("Export failed: \(error)")
                }
            }
            .sheet(item: $billToShare) { bill in
                if let jsonData = try? JSONEncoder().encode(bill),
                   let base64 = jsonData.base64EncodedString()
                       .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "billsplit://import?data=\(base64)") {
                    BillShareSheet(bill: bill, shareURL: url)
                }
            }
        }
    }
    private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter
        }
    
    // Exported file wrapper for FileExporter
    struct ExportedFile: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }
        var url: URL?

        init(url: URL?) {
            self.url = url
        }

        init(configuration: ReadConfiguration) throws {
            self.url = nil
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            guard let url = url else { throw CocoaError(.fileNoSuchFile) }
            let data = try Data(contentsOf: url)
            return FileWrapper(regularFileWithContents: data)
        }
    }
}

// MARK: - Restaurant Search Sheet
/// Searches for the restaurant by name using MapKit and lets the user pick
/// a result to populate the bill's address field.
struct RestaurantSearchSheet: View {
    let restaurantName: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    init(restaurantName: String, onSelect: @escaping (String) -> Void) {
        self.restaurantName = restaurantName
        self.onSelect = onSelect
        _query = State(initialValue: restaurantName)
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if results.isEmpty {
                    Text("No results — try a different search")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results, id: \.self) { item in
                        Button {
                            if let address = formatted(item.placemark) {
                                onSelect(address)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if let address = formatted(item.placemark) {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Find Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search by name or address")
            .onSubmit(of: .search) { search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { search() }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                results = response.mapItems
            } catch {
                results = []
            }
            isSearching = false
        }
    }

    private func formatted(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
            parts.append("\(number) \(street)")
        } else if let street = placemark.thoroughfare {
            parts.append(street)
        }
        if let city = placemark.locality { parts.append(city) }
        if let state = placemark.administrativeArea { parts.append(state) }
        if let zip = placemark.postalCode { parts.append(zip) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Add to People Editor: save persons directly into a group
struct SavePeopleToGroupView: View {
    var persons: [Person]
    @EnvironmentObject private var groupsVM: ContactGroupsViewModel
    @State private var groupName: String = ""
    @State private var showingAlert = false

    var body: some View {
        VStack(spacing: 16) {
            TextField("Group Name", text: $groupName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button("Save to Group") { saveToGroup() }
                .disabled(groupName.isEmpty || persons.isEmpty)
                .alert("Group Saved", isPresented: $showingAlert) {
                    Button("OK", role: .cancel) {}
                }
        }
        .padding()
    }

    private func saveToGroup() {
        groupsVM.addGroup(name: groupName, members: persons)
        showingAlert = true
        groupName = ""
    }
}



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
                .foregroundColor(.white)
                .cornerRadius(10)
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
                    .foregroundColor(.white)
                    .cornerRadius(10)
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
                    .foregroundColor(.white)
                    .cornerRadius(10)
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

            // Single invisible anchor — drives all three sheets via enum.
            Color.clear
                .frame(height: 0)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .contacts:
                        MultiContactPicker { persons in
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

// MARK: - Person Row
/// Displays one person with their share and contactless payment options.
struct PersonRow: View {
    @EnvironmentObject var vm: BillViewModel
    let person: Person

    @State private var paymentResult: PaymentResult? = nil
    @State private var showingPaymentResult = false

    enum PaymentResult { case success, failure(String) }

    private var share: (preTax: Double, tax: Double, tip: Double, total: Double) {
        vm.totalForPerson(person.id)
    }
    private var hasShare: Bool { share.total > 0.01 }
    private var canApplePay: Bool { PKPaymentAuthorizationViewController.canMakePayments() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name + total
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if person.isBirthday {
                            Text("🎂")
                                .font(.body)
                        }
                        Text(person.name).fontWeight(.semibold)
                            .foregroundStyle(person.isBirthday ? Color.pink : Color.primary)
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
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if person.isBirthday {
                        Text("$0.00")
                            .fontWeight(.semibold)
                            .foregroundStyle(.pink)
                    } else if hasShare {
                        Text(share.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .fontWeight(.semibold)
                    }
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
                    // Apple Pay — person pays YOU (contactless, presented via UIKit)
                    if canApplePay {
                        Button {
                            prepareAndShowApplePay()
                        } label: {
                            Label("Pay", systemImage: "wave.3.right.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Request — sends person a payment request so YOU receive money
                    Button {
                        requestPayment()
                    } label: {
                        Label("Request", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        // Result alert
        .alert(resultTitle, isPresented: $showingPaymentResult) {
            Button("OK", role: .cancel) { paymentResult = nil }
        } message: {
            if case .failure(let msg) = paymentResult { Text(msg) }
        }
    }

    private var resultTitle: String {
        switch paymentResult {
        case .success: return "✅ Payment Authorised"
        case .failure: return "❌ Payment Failed"
        case nil: return ""
        }
    }

    // Build the PKPaymentRequest and hand off to ApplePayPresenter.
    private func prepareAndShowApplePay() {
        let request = PKPaymentRequest()
        request.merchantIdentifier = "merchant.com.rfdigitaldev.store"
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = [.threeDSecure, .debit, .credit]
        request.countryCode = "US"
        request.currencyCode = Locale.current.currency?.identifier ?? "USD"

        func rounded(_ value: Double) -> NSDecimalNumber {
            NSDecimalNumber(string: String(format: "%.2f", (value * 100).rounded() / 100))
        }

        let restaurantLabel = vm.bill.restaurantName.isEmpty ? "Restaurant" : vm.bill.restaurantName
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "\(person.name)'s Items", amount: rounded(share.preTax)),
            PKPaymentSummaryItem(label: "Tax",                    amount: rounded(share.tax)),
            PKPaymentSummaryItem(label: "Tip",                    amount: rounded(share.tip)),
            PKPaymentSummaryItem(label: restaurantLabel,          amount: rounded(share.total))
        ]

        ApplePayPresenter.present(request: request) { success, message in
            paymentResult = success ? .success : .failure(message ?? "Payment failed.")
            showingPaymentResult = true
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
        let phoneTarget = person.phone.map { "sms:\($0)" } ?? "sms:"
        if let smsURL = URL(string: "\(phoneTarget)&body=\(encoded)") {
            UIApplication.shared.open(smsURL)
        }
    }
}


// Filterable multi-select contacts picker (SwiftUI-based)
struct MultiContactPicker: View {
    var onSelect: ([Person]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allContacts: [CNContact] = []
    @State private var filtered: [CNContact] = []
    @State private var searchText: String = ""
    @State private var selectedIdentifiers: Set<String> = []
    @State private var loading = true
    @State private var authDenied = false
    @State private var hasLoaded = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            contactListContent
                .navigationTitle("Select People")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                // Always-visible bottom bar so the Add button is never hidden
                // by the search bar or keyboard.
                .safeAreaInset(edge: .bottom) {
                    addButton
                }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name or phone"
                )
                .onChange(of: searchText) { _, _ in applyFilter() }
                .onAppear {
                    if !hasLoaded {
                        hasLoaded = true
                        Task { await requestAndLoadContacts() }
                    }
                }
        }
    }

    // MARK: - Subviews

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
            ProgressView("Loading contacts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .animation(.easeInOut(duration: 0.15), value: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(isSelected ? .semibold : .regular)
                if !phone.isEmpty {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Persistent "Add N Contacts" button anchored to the bottom of the screen.
    private var addButton: some View {
        Button(action: finishSelection) {
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

    // MARK: - Data

    private func requestAndLoadContacts() async {
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
            let fetchRequest = CNContactFetchRequest(keysToFetch: keys)
            fetchRequest.sortOrder = .userDefault

            var temp: [CNContact] = []
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try store.enumerateContacts(with: fetchRequest) { contact, _ in
                            if !contact.phoneNumbers.isEmpty { temp.append(contact) }
                        }
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            await MainActor.run {
                allContacts = temp
                loading = false
                applyFilter()
            }
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

    private func finishSelection() {
        let selected = allContacts.filter { selectedIdentifiers.contains($0.identifier) }
        let persons = selected.map { c in
            Person(name: displayName(for: c), phone: c.phoneNumbers.first?.value.stringValue)
        }
        onSelect(persons)
        dismiss()
    }

    private func displayName(for c: CNContact) -> String {
        [c.givenName, c.familyName]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}


// MARK: - Apple Pay Presenter
/// Presents PKPaymentAuthorizationViewController directly through the UIKit
/// hierarchy, bypassing SwiftUI sheets which cause a blank-popup conflict.
enum ApplePayPresenter {

    private static var coordinator: Coordinator?

    static func present(
        request: PKPaymentRequest,
        onCompletion: @escaping (_ success: Bool, _ message: String?) -> Void
    ) {
        guard let vc = PKPaymentAuthorizationViewController(paymentRequest: request) else {
            onCompletion(false, "Apple Pay is not available on this device.")
            return
        }
        let coord = Coordinator(onCompletion: onCompletion)
        coordinator = coord          // retain while the sheet is on screen
        vc.delegate = coord

        // Walk up to the top-most presented view controller
        guard let root = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            onCompletion(false, "Could not find a window to present from.")
            return
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(vc, animated: true)
    }

    final class Coordinator: NSObject, PKPaymentAuthorizationViewControllerDelegate {
        private let onCompletion: (_ success: Bool, _ message: String?) -> Void
        private var didAuthorise = false

        init(onCompletion: @escaping (_ success: Bool, _ message: String?) -> Void) {
            self.onCompletion = onCompletion
        }

        func paymentAuthorizationViewController(
            _ controller: PKPaymentAuthorizationViewController,
            didAuthorizePayment payment: PKPayment,
            handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
        ) {
            // TODO: forward payment.token.paymentData to your payment processor server.
            didAuthorise = true
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        }

        func paymentAuthorizationViewControllerDidFinish(
            _ controller: PKPaymentAuthorizationViewController
        ) {
            let success = didAuthorise
            controller.dismiss(animated: true) {
                self.onCompletion(success, success ? nil : "Payment was cancelled.")
                ApplePayPresenter.coordinator = nil   // release the coordinator
            }
        }
    }
}

    

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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(vm.bill.people) { person in
                        let isOn = item.consumers.contains(person.id)
                        Button {
                            vm.toggleConsumer(item: item, person: person)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                Text(person.name)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(isOn ? .accentColor : .gray)
                    }
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
            Toggle(isOn: $vm.isPreTaxCalc ) {
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

// MARK: - PDF Receipt View
struct ReceiptView: View {
    @EnvironmentObject var vm: BillViewModel
    var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BILL SPLIT RECEIPT \(vm.bill.restaurantName)").font(.title2).fontWeight(.bold)
            Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            Divider()
            Text("Participants").fontWeight(.semibold)
//            VStack(alignment: .leading) {
//                ForEach(vm.bill.people) { Text("• \($0.name)").font(.caption) }
//            }
            //let names = [String](vm.bill.people.map(\.init(\.name)))
            let names: [String] = vm.bill.people.map { $0.isBirthday ? "🎂 \($0.name)" : $0.name }
            var chunkedNames: [[String]] {
                    stride(from: 0, to: names.count, by: 2).map {
                        Array(names[$0..<min($0 + 2, names.count)])
                    }
                }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(chunkedNames, id: \.self) { column in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(column, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
            let birthdayNames = vm.bill.people.filter { $0.isBirthday }.map { $0.name }
            if !birthdayNames.isEmpty {
                Text("🎂 Birthday: \(birthdayNames.joined(separator: ", ")) — covered by the group")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
            Divider()
            Text("Items").fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(vm.bill.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.caption)
                            if !item.consumers.isEmpty {
                                Text("Shared by: " + vm.bill.people.filter { item.consumers.contains($0.id) }.map { $0.isBirthday ? "🎂 \($0.name)" : $0.name }.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(.caption)
                    }
                }
            }
           
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Subtotal").font(.caption); Spacer(); Text(vm.subtotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(.caption)}
                HStack { Text("Tax (\(vm.bill.taxPercent.formatted()))% ").font(.caption); Spacer(); Text(vm.taxAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(.caption) }
                HStack { Text("Tip (\(vm.bill.tipPercent.formatted()))% ").font(.caption); Spacer(); Text(vm.tipAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(.caption) }
                HStack { Text("Grand Total").font(.caption).fontWeight(.semibold); Spacer(); Text(vm.grandTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).fontWeight(.semibold).font(.caption) }
            }
            Divider()
            
            Text("Generated by BI Splitter. Copyright © 2025 Ricardo Fong. All rights reserved.").font(.footnote).foregroundStyle(.secondary)
        }
        .foregroundStyle(.black)
        .background(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PDF Receipt View Page2
struct ReceiptView2: View {
    @EnvironmentObject var vm: BillViewModel
    var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Text("To Pay Per Person").fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.bill.people) { person in
                    let share = vm.totalForPerson(person.id)
                    HStack {
                        HStack(spacing: 4) {
                            if person.isBirthday { Text("🎂") }
                            Text(person.name)
                                .foregroundStyle(person.isBirthday ? .pink : .primary)
                        }
                        Spacer()
                        if person.isBirthday {
                            Text("$0.00 · Covered by group 🎉")
                                .foregroundStyle(.pink)
                        } else {
                            Text(share.total, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        }
                    }
                    if !person.isBirthday {
                        Text("  Items: \(share.preTax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) | Tax: \(share.tax.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) | Tip: \(share.tip.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            Divider()
            if let email = vm.bill.zelleEmail, !email.isEmpty {
                Text("Zelle to email: \(email)").fontWeight(.semibold)
            }
            if let phone = vm.bill.zellePhone, !phone.isEmpty {
                Text("Zelle Phone: \(phone)").fontWeight(.semibold)
            }
            Spacer(minLength: 0)
            Divider()
            if let data = vm.bill.receiptImageData, let uiImage = UIImage(data: data) {
                Section("Attached Receipt") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                }
            }
                      
            Text("Generated by BI Splitter. Copyright © 2025 Ricardo Fong. All rights reserved.").font(.footnote).foregroundStyle(.secondary)
        }
        .foregroundStyle(.black)
        .background(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Receipt Parser
/// Calls OpenAI's chat completion API to extract line items from raw OCR text.
/// Falls back to the local regex parser if the network call fails.
struct ReceiptParser {

    // Loaded at runtime from the app's Info.plist, which pulls OPENAI_API_KEY from
    // Secrets.xcconfig (git-ignored) via build-setting substitution. Never hard-code the key here.
    static let openAIKey: String = {
        let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String
        return key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    struct ParsedItem: Decodable {
        let name: String
        let price: Double
    }

    /// Attempts AI-powered parsing first; returns regex-parsed items on failure.
    static func parse(lines: [String]) async -> [(name: String, price: Double)] {
        if !openAIKey.isEmpty,
           let aiItems = try? await parseWithAI(lines: lines) {
            return aiItems
        }
        return parseWithRegex(lines: lines)
    }

    // MARK: AI Parser
    private static func parseWithAI(lines: [String]) async throws -> [(name: String, price: Double)] {
        let rawText = lines.joined(separator: "\n")

        let systemPrompt = """
        You are a receipt parser. Extract only the purchased menu items and their prices from the receipt text.
        Exclude tax, tip, subtotal, total, discounts, and any non-item lines.
        Respond ONLY with a valid JSON array, no markdown, no explanation.
        Each element must have exactly two fields: "name" (string) and "price" (number).
        Example: [{"name":"Burger","price":12.99},{"name":"Fries","price":3.49}]
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Pull the content string out of the OpenAI response envelope
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let completion = try JSONDecoder().decode(Completion.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        let parsed = try JSONDecoder().decode([ParsedItem].self, from: jsonData)
        return parsed.filter { $0.price > 0 }.map { ($0.name, $0.price) }
    }

    // MARK: Regex Fallback
    static func parseWithRegex(lines: [String]) -> [(name: String, price: Double)] {
        var results: [(name: String, price: Double)] = []
        for (index, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Drop leading digit+space (e.g. quantity prefix "2 Burger $17.00")
            if let first = line.first, first.isNumber { line = String(line.dropFirst(2)) }
            if let priceRange = line.range(of: "\\$?[0-9]+(\\.[0-9]{1,2})?",
                                           options: .regularExpression) {
                let priceToken = String(line[priceRange]).replacingOccurrences(of: "$", with: "")
                if let price = Double(priceToken) {
                    let name = line.replacingOccurrences(of: String(line[priceRange]), with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    results.append((name.isEmpty ? "Item" : name, price))
                }
            } else if index + 1 < lines.count {
                // Price might be on the next line
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if let priceRange = nextLine.range(of: "\\$?[0-9]+(\\.[0-9]{1,2})?",
                                                   options: .regularExpression) {
                    let priceToken = String(nextLine[priceRange]).replacingOccurrences(of: "$", with: "")
                    if let price = Double(priceToken) {
                        results.append((line.isEmpty ? "Item" : line, price))
                    }
                }
            }
        }
        return results
    }
}
struct ReceiptScannerView: UIViewControllerRepresentable {
    var completion: ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var completion: ([String]) -> Void

        init(completion: @escaping ([String]) -> Void) {
            self.completion = completion
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var recognizedTexts: [String] = []

            let request = VNRecognizeTextRequest { (request, error) in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        recognizedTexts.append(candidate.string)
                    }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let dispatchGroup = DispatchGroup()

            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                if let cgImage = image.cgImage {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    dispatchGroup.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try handler.perform([request])
                        } catch {
                            print("Text recognition failed: \(error)")
                        }
                        dispatchGroup.leave()
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.completion(recognizedTexts)
                controller.dismiss(animated: true)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Scanner failed: \(error.localizedDescription)")
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - ShareSheet helper
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Identifiable URL wrapper (for sheet(item:))
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - ImageRenderer -> PDF helper
/// Lightweight wrapper for ImageRenderer PDF export (iOS 16+)
extension ImageRenderer {
    @MainActor
    func pdfData(pageSize: CGSize, pageMargins: CGFloat = 16) async throws -> Data {
        var data = Data()
        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        data = renderer.pdfData { ctx in
            ctx.beginPage()
            let hosting = UIHostingController(rootView: content)
            hosting.view.backgroundColor = .white
            hosting.view.bounds = bounds.insetBy(dx: pageMargins, dy: pageMargins)
            let fitting = hosting.sizeThatFits(in: bounds.size)
            hosting.view.bounds.size = CGSize(width: bounds.width - pageMargins * 2, height: fitting.height)
            hosting.view.layoutIfNeeded()
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        return data
    }
}

// Simple ImagePicker wrapper
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            parent.completion(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
            picker.dismiss(animated: true)
        }
    }
}
