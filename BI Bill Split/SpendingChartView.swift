import SwiftUI
import Charts

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
            guard bill.subtotal > 0 else { continue }
            for person in bill.people {
                // Uses the same Bill.totalForPerson math as the current bill and
                // Saved Bills, so birthday/exclude rules and pre-tax-tip are honored.
                let share = bill.totalForPerson(person.id).total
                guard share > 0 else { continue }
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
                        // Every other currency display in the app follows the
                        // user's locale (falling back to USD only if the locale
                        // has none) — this axis was the one spot hard-coded to USD.
                        AxisMarks(format: Decimal.FormatStyle.Currency(code: Locale.current.currency?.identifier ?? "USD"))
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

