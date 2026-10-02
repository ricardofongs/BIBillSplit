import SwiftUI
import UniformTypeIdentifiers

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
    /// Uses the same `Bill.totalForPerson` math as the current bill and Spending charts,
    /// so birthday/exclude rules and pre-tax-tip are honored consistently.
    private func personShare(in bill: Bill, query: String) -> Double? {
        guard bill.subtotal > 0,
              let person = bill.people.first(where: { $0.name.lowercased().contains(query) })
        else { return nil }
        let total = bill.totalForPerson(person.id).total
        guard total > 0 else { return nil }
        return total
    }

    var body: some View {
        NavigationStack {
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
                    let idsToDelete = Set(offsets.map { filteredBills[$0].id })
                    vm.deleteBills(ids: idsToDelete)
                }
            }
            .searchable(text: $searchText, prompt: "Filter by person name")
            .navigationTitle("Saved Bills")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                if let url = bill.shareURL() {
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

