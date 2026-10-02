import SwiftUI
import MapKit

// MARK: - Restaurant Search Sheet
/// Searches for the restaurant by name using MapKit and lets the user pick
/// a result to populate the bill's address field.
struct RestaurantSearchSheet: View {
    let restaurantName: String
    let onSelect: (String, String) -> Void   // (name, address)

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    init(restaurantName: String, onSelect: @escaping (String, String) -> Void) {
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
                                onSelect(item.name ?? restaurantName, address)
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



