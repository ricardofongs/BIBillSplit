import SwiftUI

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
                    let excludedPeople = bill.people.filter { $0.isExcluded && !$0.isBirthday }
                    if !excludedPeople.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.badge.minus")
                            Text(excludedPeople.map { $0.name }.joined(separator: ", ") + " · only pay own items")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    let notPayingLines = bill.people.compactMap { person -> String? in
                        guard let payerID = person.notPayingAssignedToID,
                              let payerName = bill.people.first(where: { $0.id == payerID })?.name
                        else { return nil }
                        return "\(person.name) paid by \(payerName)"
                    }
                    if !notPayingLines.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.right.circle")
                            Text(notPayingLines.joined(separator: ", "))
                                .foregroundStyle(.purple)
                        }
                        .font(.caption)
                        .foregroundStyle(.purple)
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

