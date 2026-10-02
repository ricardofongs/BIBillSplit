import Foundation

// MARK: - Models
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var phone: String?
    var isBirthday: Bool
    /// When true this person only pays for what they personally consumed;
    /// they are excluded from absorbing any birthday-person redistribution.
    var isExcluded: Bool
    /// Pro feature: when set, this person pays nothing and the person with
    /// this ID (another `Person.id` in the same bill) absorbs their entire
    /// share instead of it being redistributed evenly among everyone else.
    var notPayingAssignedToID: UUID?

    init(id: UUID = UUID(), name: String, phone: String? = nil, isBirthday: Bool = false, isExcluded: Bool = false, notPayingAssignedToID: UUID? = nil) {
        self.id = id; self.name = name; self.phone = phone; self.isBirthday = isBirthday; self.isExcluded = isExcluded
        self.notPayingAssignedToID = notPayingAssignedToID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = (try? c.decode(UUID.self,   forKey: .id))   ?? UUID()
        name       = (try? c.decode(String.self, forKey: .name)) ?? ""
        phone      = try? c.decodeIfPresent(String.self, forKey: .phone)
        isBirthday = (try? c.decode(Bool.self,   forKey: .isBirthday)) ?? false
        isExcluded = (try? c.decode(Bool.self,   forKey: .isExcluded)) ?? false
        notPayingAssignedToID = try? c.decodeIfPresent(UUID.self, forKey: .notPayingAssignedToID)
    }

    enum CodingKeys: String, CodingKey { case id, name, phone, isBirthday, isExcluded, notPayingAssignedToID }
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
    var venmoUsername: String?
    var cashAppTag: String?

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
        zellePhone: String? = nil,
        venmoUsername: String? = nil,
        cashAppTag: String? = nil
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
        self.venmoUsername = venmoUsername
        self.cashAppTag = cashAppTag
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
        venmoUsername    = try? c.decodeIfPresent(String.self, forKey: .venmoUsername)
        cashAppTag       = try? c.decodeIfPresent(String.self, forKey: .cashAppTag)
    }

    enum CodingKeys: String, CodingKey {
        case id, people, items, taxPercent, tipPercent, isPreTaxCalc
        case restaurantName, restaurantAddress, date, receiptImageData, zelleEmail, zellePhone
        case venmoUsername, cashAppTag
    }
}

// MARK: - Bill Sharing (deep link)
extension Bill {
    /// A copy of this bill with the attached receipt photo removed. The photo
    /// can be close to 1 MB, which would make the base64-encoded share link
    /// far too long for Messages/AirDrop to carry reliably.
    private var strippedForSharing: Bill {
        var copy = self
        copy.receiptImageData = nil
        return copy
    }

    /// Encodes this bill (without its receipt photo) as a `billsplit://import?data=<base64>`
    /// URL that any device running this app can open to load the full bill.
    func shareURL() -> URL? {
        guard let jsonData = try? JSONEncoder().encode(strippedForSharing) else { return nil }
        let base64 = jsonData.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "billsplit://import?data=\(base64)")
    }
}

// ContactGroup — stored in UserDefaults as JSON, no Core Data needed
struct ContactGroup: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var members: [Person]
}

// MARK: - Bill split math
// Single source of truth for all split math, shared by the current-bill
// view model, Saved Bills, and the Spending charts — so birthday/exclude
// rules and the pre-tax-tip setting are honored consistently everywhere.
extension Bill {
    var subtotal: Double { items.reduce(0) { $0 + $1.price } }
    var taxAmount: Double { subtotal * taxPercent / 100.0 }
    var tipAmount: Double { (subtotal + (isPreTaxCalc ? 0 : taxAmount)) * tipPercent / 100.0 }
    var grandTotal: Double { subtotal + taxAmount + tipAmount }
    /// Bill-level total, used by Saved Bills and the Spending charts.
    var totalAmount: Double { grandTotal }

    /// Per-person share for items, including the "Not Paying" redirect: a
    /// person flagged `notPayingAssignedToID` pays $0, and their full raw
    /// share (computed as if they had no such flag) is added to the person
    /// they designated instead of being spread across everyone else.
    func preTaxShare(for personID: UUID) -> Double {
        let redirects = Dictionary(uniqueKeysWithValues: people.compactMap { person -> (UUID, UUID)? in
            guard let payerID = person.notPayingAssignedToID,
                  people.contains(where: { $0.id == payerID }) else { return nil }
            return (person.id, payerID)
        })

        if redirects[personID] != nil { return 0 }

        let delegatedShare = redirects
            .filter { $0.value == personID }
            .keys
            .reduce(0.0) { $0 + rawPreTaxShare(for: $1) }

        return rawPreTaxShare(for: personID) + delegatedShare
    }

    /// Rules:
    /// - Birthday people always pay $0; their portions are redistributed.
    /// - Excluded people pay only their own fair base share (item.price / total consumers),
    ///   never absorbing any birthday-person redistribution.
    /// - Everyone else absorbs the birthday portions left uncovered by excluded people.
    /// - An item with no assigned consumers is treated the same as one consumed only
    ///   by birthday people — its cost still goes to the bill-level absorbers rather
    ///   than vanishing from everyone's total.
    private func rawPreTaxShare(for personID: UUID) -> Double {
        let birthdayIDs = Set(people.filter { $0.isBirthday }.map { $0.id })
        // isExcluded is irrelevant when birthday is also set — birthday takes precedence
        let excludedIDs = Set(people.filter { $0.isExcluded && !$0.isBirthday }.map { $0.id })
        let billAbsorbers = Set(people.filter { !$0.isBirthday && !$0.isExcluded }.map { $0.id })
        let allNonBirthday = Set(people.filter { !$0.isBirthday }.map { $0.id })

        if birthdayIDs.contains(personID) { return 0 }

        /// Splits an item nobody effectively claims — either genuinely unassigned,
        /// or assigned only to birthday people — among the bill-level absorbers,
        /// falling back further if everyone non-birthday happens to be excluded.
        func redistributedShare(of item: Item) -> Double {
            if billAbsorbers.isEmpty {
                guard allNonBirthday.contains(personID) else { return 0 }
                return item.price / Double(allNonBirthday.count)
            }
            guard billAbsorbers.contains(personID) else { return 0 }
            return item.price / Double(billAbsorbers.count)
        }

        return items.reduce(0.0) { partial, item in
            guard !item.consumers.isEmpty else {
                return partial + redistributedShare(of: item)
            }

            let fairShare = item.price / Double(item.consumers.count)

            if birthdayIDs.isEmpty {
                // No birthday people — normal split, excluded flag has no effect
                guard item.consumers.contains(personID) else { return partial }
                return partial + fairShare
            }

            let nonBirthdayConsumers = item.consumers.subtracting(birthdayIDs)

            if nonBirthdayConsumers.isEmpty {
                // All consumers of this item are birthday people — redistribute to bill-level absorbers
                return partial + redistributedShare(of: item)
            }

            // At least one non-birthday consumer exists for this item
            guard nonBirthdayConsumers.contains(personID) else { return partial }

            if excludedIDs.contains(personID) {
                // Excluded: only pay the base fair share regardless of birthday redistribution
                return partial + fairShare
            }

            // Absorbing person: covers their own share plus a slice of the birthday redistribution
            let excludedConsumersOfItem = nonBirthdayConsumers.intersection(excludedIDs)
            let absorbingConsumersOfItem = nonBirthdayConsumers.subtracting(excludedIDs)

            if absorbingConsumersOfItem.isEmpty {
                // All non-birthday consumers of this item are excluded — split evenly among them
                return partial + item.price / Double(nonBirthdayConsumers.count)
            }

            guard absorbingConsumersOfItem.contains(personID) else { return partial }

            // Excluded people cover their own base shares; absorbers split the rest
            let excludedCoverage = Double(excludedConsumersOfItem.count) * fairShare
            let remaining = item.price - excludedCoverage
            return partial + remaining / Double(absorbingConsumersOfItem.count)
        }
    }

    /// Distribute tax and tip proportionally to each person's pre-tax share.
    func totalForPerson(_ personID: UUID) -> (preTax: Double, tax: Double, tip: Double, total: Double) {
        let share = preTaxShare(for: personID)
        guard subtotal > 0 else { return (0, 0, 0, 0) }
        let ratio = share / subtotal
        let tax = taxAmount * ratio
        let tip = tipAmount * ratio
        return (share, tax, tip, share + tax + tip)
    }
}

