import SwiftUI
import CoreData
import UIKit

// MARK: - ViewModel
@MainActor
final class BillViewModel: ObservableObject {
    // Reads the user's saved defaults (falling back to 8 % tax / 18 % tip if never set).
    static func defaultBill() -> Bill {
        let tax = UserDefaults.standard.object(forKey: "defaultTaxPercent") as? Double ?? 8.0
        let tip = UserDefaults.standard.object(forKey: "defaultTipPercent") as? Double ?? 18.0
        let zelleEmail = UserDefaults.standard.string(forKey: "defaultZelleEmail")
        let zellePhone = UserDefaults.standard.string(forKey: "defaultZellePhone")
        let venmoUsername = UserDefaults.standard.string(forKey: "defaultVenmoUsername")
        let cashAppTag = UserDefaults.standard.string(forKey: "defaultCashAppTag")
        return Bill(people: [], items: [], taxPercent: tax, tipPercent: tip,
                    restaurantName: "", date: Date(), receiptImageData: nil,
                    zelleEmail: zelleEmail?.isEmpty == false ? zelleEmail : nil,
                    zellePhone: zellePhone?.isEmpty == false ? zellePhone : nil,
                    venmoUsername: venmoUsername?.isEmpty == false ? venmoUsername : nil,
                    cashAppTag: cashAppTag?.isEmpty == false ? cashAppTag : nil)
    }

    // bill uses willSet/didSet (instead of @Published) so we can hook sync.
    var bill: Bill = BillViewModel.defaultBill() {
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
    // Cached menu items keyed by "restaurantName|address" — avoids repeat API calls within a session.
    var menuItemCache: [String: [MenuFetchedItem]] = [:]
    @Published var syncPeerNames: [String] = []
    /// Queued rather than a single optional — a second invitation (e.g. from a
    /// different nearby device) used to silently overwrite and lose the first
    /// one's `respond` handler, leaving that peer's invite hanging forever.
    @Published var pendingSyncInvitations: [SyncInvitation] = []
    private var isReceivingSync = false
    private var syncDebounceTask: Task<Void, Never>? = nil

    /// A bill received via `billsplit://import` deep link, staged for the user
    /// to confirm before it silently overwrites whatever is in the Bill tab.
    @Published var pendingImportedBill: Bill? = nil

    @Published var savedBills: [Bill] = []
    @Published var restaurantName: String = ""
    /// Surfaces Core Data load/save/delete failures to the UI — previously these
    /// were only printed to the console, so a save could fail with no visible
    /// sign to the user that their bill wasn't actually persisted.
    @Published var storageErrorMessage: String? = nil
    private let billsKey = "savedBills"
    private var savedBillEntities: [SavedBillEntity] = []
    /// `Bill.id` → its backing entity, rebuilt whenever `loadBills()` runs.
    /// Lets `saveCurrentBill`/`deleteBills` look up an existing entity in O(1)
    /// instead of re-fetching and JSON-decoding every saved bill each time.
    private var entityByBillID: [UUID: SavedBillEntity] = [:]

    private let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "BillModel")
        container.loadPersistentStores { [weak self] _, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.storageErrorMessage = "Couldn't open saved bills storage. Saving and loading bills won't work until the app is restarted."
                }
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
            self?.pendingSyncInvitations.append(SyncInvitation(peerName: peerName, respond: respond))
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
    // Forwarded to `Bill` so the same math backs the current bill, Saved Bills,
    // and the Spending charts — see the `Bill` extension near `ReceiptView`.
    var subtotal: Double { bill.subtotal }
    var taxAmount: Double { bill.taxAmount }
    var tipAmount: Double { bill.tipAmount }
    var grandTotal: Double { bill.grandTotal }

    func toggleBirthday(for personID: UUID) {
        guard let idx = bill.people.firstIndex(where: { $0.id == personID }) else { return }
        bill.people[idx].isBirthday.toggle()
        if bill.people[idx].isBirthday { bill.people[idx].notPayingAssignedToID = nil }
    }

    func toggleExcluded(for personID: UUID) {
        guard let idx = bill.people.firstIndex(where: { $0.id == personID }) else { return }
        bill.people[idx].isExcluded.toggle()
        if bill.people[idx].isExcluded { bill.people[idx].notPayingAssignedToID = nil }
    }

    /// Pro feature: designates `payerID` to cover `personID`'s entire share,
    /// or clears the designation when `payerID` is nil. Mutually exclusive
    /// with Birthday/Exclude — assigning a payer clears those flags.
    func setNotPayingPayer(for personID: UUID, payerID: UUID?) {
        guard let idx = bill.people.firstIndex(where: { $0.id == personID }) else { return }
        bill.people[idx].notPayingAssignedToID = payerID
        if payerID != nil {
            bill.people[idx].isBirthday = false
            bill.people[idx].isExcluded = false
        }
    }

    /// Distribute tax and tip proportionally to each person's pre-tax share.
    func totalForPerson(_ personID: UUID) -> (preTax: Double, tax: Double, tip: Double, total: Double) {
        bill.totalForPerson(personID)
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
        let ids = Set(offsets.map { bill.people[$0].id })
        bill.items = bill.items.map { item in
            var copy = item
            copy.consumers.subtract(ids)
            return copy
        }
        // Clear any "Not Paying" designation that pointed at a person being removed.
        bill.people = bill.people.map { person in
            var copy = person
            if let payerID = copy.notPayingAssignedToID, ids.contains(payerID) {
                copy.notPayingAssignedToID = nil
            }
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
            let entity = entityByBillID[bill.id] ?? SavedBillEntity(context: context)
            guard let data = try? JSONEncoder().encode(bill) else {
                storageErrorMessage = "Couldn't prepare this bill for saving. Please try again."
                return
            }
            entity.billData = data
            do {
                try context.save()
                storageErrorMessage = nil
                loadBills()
            } catch {
                storageErrorMessage = "Couldn't save this bill: \(error.localizedDescription)"
            }
        }

        private func loadBills() {
            let request = NSFetchRequest<SavedBillEntity>(entityName: "SavedBillEntity")
            do {
                let entities = try container.viewContext.fetch(request)
                savedBillEntities = entities
                var decodedBills: [Bill] = []
                var lookup: [UUID: SavedBillEntity] = [:]
                for entity in entities {
                    guard let data = entity.billData,
                          let bill = try? JSONDecoder().decode(Bill.self, from: data)
                    else { continue }
                    decodedBills.append(bill)
                    lookup[bill.id] = entity
                }
                savedBills = decodedBills
                entityByBillID = lookup
            } catch {
                storageErrorMessage = "Couldn't load saved bills: \(error.localizedDescription)"
            }
        }

    /// Deletes saved bills by their stable `Bill.id`, not by array position.
    /// `savedBills` is built by filtering out any entity that fails to decode,
    /// so the two arrays can fall out of index alignment — deleting by position
    /// risked removing the wrong saved bill.
    func deleteBills(ids: Set<UUID>) {
            guard !ids.isEmpty else { return }
            let context = container.viewContext
            for id in ids {
                guard let entity = entityByBillID[id] else { continue }
                context.delete(entity)
            }
            do {
                try context.save()
                storageErrorMessage = nil
                loadBills()
            } catch {
                storageErrorMessage = "Couldn't delete this bill: \(error.localizedDescription)"
            }
        }
    func clearCurrentBill() {
        bill = BillViewModel.defaultBill()
        menuItemCache = [:]
    }

    // MARK: - Deep-link import confirmation

    /// Stages a bill received via `billsplit://import` for the user to confirm —
    /// opening the link shouldn't silently discard whatever is in the Bill tab.
    func stageImportedBill(_ imported: Bill) {
        pendingImportedBill = imported
    }

    func confirmPendingImport() {
        guard let imported = pendingImportedBill else { return }
        bill = imported
        pendingImportedBill = nil
    }

    func cancelPendingImport() {
        pendingImportedBill = nil
    }
    
    // MARK: - Bill Sharing (deep link)

    /// Encodes the current bill as a `billsplit://import?data=<base64>` URL
    /// that any device running this app can open to load the full bill.
    func shareBillURL() -> URL? {
        bill.shareURL()
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

