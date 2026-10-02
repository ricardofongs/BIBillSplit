import Foundation

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
