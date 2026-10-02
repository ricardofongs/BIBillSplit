import SwiftUI

// MARK: - Menu Browser

struct MenuFetchedItem: Identifiable, Decodable {
    let id: UUID
    let name: String
    let price: Double
    let category: String
    let description: String
    let isPopular: Bool
    let tags: [String]   // "vegetarian" | "vegan" | "gluten-free" | "spicy"

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        id          = UUID()
        name        = try  c.decode(String.self,   forKey: .name)
        price       = try  c.decode(Double.self,   forKey: .price)
        category    = (try? c.decode(String.self,  forKey: .category))    ?? "Other"
        description = (try? c.decode(String.self,  forKey: .description)) ?? ""
        isPopular   = (try? c.decode(Bool.self,    forKey: .isPopular))   ?? false
        tags        = (try? c.decode([String].self, forKey: .tags))       ?? []
    }

    enum CodingKeys: String, CodingKey { case name, price, category, description, isPopular, tags }
}

struct MenuFetcher {
    static let openAIKey: String = ReceiptParser.openAIKey

    static func fetch(restaurantName: String, address: String?) async throws -> [MenuFetchedItem] {
        guard !openAIKey.isEmpty else { throw URLError(.userAuthenticationRequired) }

        let location = address.map { " located at \($0)" } ?? ""
        let systemPrompt = """
        You are a restaurant menu expert. Generate a comprehensive, realistic menu for "\(restaurantName)"\(location).

        Return ONLY a valid JSON array — no markdown, no explanation, no code fences.
        Each element must have these fields:
          "name":        string  — dish or drink name
          "price":       number  — realistic USD price matching this restaurant's style and price tier
          "category":    string  — one of: Appetizers, Soups & Salads, Entrees, Pasta & Pizza, Sandwiches & Burgers, Sushi & Rolls, Tacos & Burritos, Sides, Desserts, Beverages, Cocktails & Beer, Brunch (use only the categories that fit this restaurant's cuisine)
          "description": string  — one sentence describing the dish and its key ingredients
          "isPopular":   boolean — true for ~15% of items that are signature or most-ordered dishes
          "tags":        array   — any subset of ["vegetarian","vegan","gluten-free","spicy"] that apply

        Return 40-55 items spanning all relevant categories. Match the cuisine, style, and price tier accurately.
        If the restaurant is a known chain, use its actual menu. Otherwise infer from the name and location.
        """

        let body: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": "Generate the full menu now."]
            ]
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod  = "POST"
        req.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.httpBody    = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let completion = try JSONDecoder().decode(Completion.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        // Strip markdown code fences if the model wraps the JSON anyway
        let stripped = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^```\\s*",     with: "", options: .regularExpression)
            .replacingOccurrences(of: "```$",          with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = stripped.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        let items = try JSONDecoder().decode([MenuFetchedItem].self, from: jsonData)
        return items.filter { $0.price > 0 }
    }
}

struct MenuBrowserSheet: View {
    let restaurantName: String
    let restaurantAddress: String?
    let onAdd: ([MenuFetchedItem]) -> Void

    @EnvironmentObject private var vm: BillViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MenuFetchedItem] = []
    @State private var selected: Set<UUID> = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var searchText = ""
    @State private var activeCategory: String? = nil   // nil = All

    private var cacheKey: String { "\(restaurantName)|\(restaurantAddress ?? "")" }

    private var allCategories: [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    private var displayedCategories: [String] {
        guard searchText.isEmpty else {
            // While searching ignore the chip filter — show everything that matches
            var seen = Set<String>()
            return filteredItems(category: nil)
                .compactMap { seen.insert($0.category).inserted ? $0.category : nil }
        }
        if let cat = activeCategory { return [cat] }
        return allCategories
    }

    private func filteredItems(category: String?) -> [MenuFetchedItem] {
        var result = items
        if let cat = category { result = result.filter { $0.category == cat } }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4)
                        Text("Building menu for \(restaurantName)…")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Text("This may take a few seconds")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Category filter chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                categoryChip(label: "All", isActive: activeCategory == nil) {
                                    activeCategory = nil
                                }
                                ForEach(allCategories, id: \.self) { cat in
                                    categoryChip(label: cat, isActive: activeCategory == cat) {
                                        activeCategory = (activeCategory == cat) ? nil : cat
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .background(Color(.systemGroupedBackground))

                        Divider()

                        List {
                            // Disclaimer
                            Section {
                                Label("Prices are AI-estimated. Tap any item to edit after adding.",
                                      systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(displayedCategories, id: \.self) { category in
                                let rows = filteredItems(category: category)
                                if !rows.isEmpty {
                                    Section(category) {
                                        ForEach(rows) { item in
                                            menuItemRow(item)
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .searchable(text: $searchText, prompt: "Search dishes or ingredients")
                    }
                }
            }
            .navigationTitle(restaurantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add Items" : "Add \(selected.count)") {
                        onAdd(items.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func menuItemRow(_ item: MenuFetchedItem) -> some View {
        Button {
            if selected.contains(item.id) { selected.remove(item.id) }
            else                          { selected.insert(item.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Selection circle
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(item.id) ? Color.accentColor : Color.secondary.opacity(0.4))
                    .font(.title3)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Name row
                    HStack(spacing: 6) {
                        Text(item.name)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        if item.isPopular {
                            Text("⭐ Popular")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    // Description
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Dietary tags + price
                    HStack(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            dietaryBadge(tag)
                        }
                        Spacer()
                        Text(item.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dietaryBadge(_ tag: String) -> some View {
        let (label, color): (String, Color) = switch tag {
        case "vegetarian":  ("🌱 Veg",    .green)
        case "vegan":       ("🌿 Vegan",  .green)
        case "gluten-free": ("GF",        .orange)
        case "spicy":       ("🌶 Spicy",  .red)
        default:            ("",          .clear)
        }
        if !label.isEmpty {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func categoryChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? Color.accentColor : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        // Return immediately if already cached for this restaurant + address combo
        if let cached = vm.menuItemCache[cacheKey] {
            items = cached
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await MenuFetcher.fetch(restaurantName: restaurantName, address: restaurantAddress)
            vm.menuItemCache[cacheKey] = fetched
            items = fetched
        } catch {
            errorMessage = "Couldn't load the menu. Check your connection and try again."
        }
        isLoading = false
    }
}

