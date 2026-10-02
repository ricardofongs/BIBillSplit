import SwiftUI
import StoreKit

// MARK: - Paywall Sheet
/// Presented from any Pro-gated entry point (Settings, "Not Paying" picker)
/// when the user isn't unlocked yet.
struct PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
                    .padding(.top, 24)

                Text("Unlock Pro")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "envelope", text: "Save default Zelle email & phone so every new bill is pre-filled.")
                    featureRow(icon: "person.crop.circle.badge.xmark", text: "Flag someone as not paying and pick exactly who covers their share.")
                }
                .padding(.horizontal)

                Spacer()

                if let message = purchaseManager.purchaseErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        isPurchasing = true
                        await purchaseManager.purchase()
                        isPurchasing = false
                        if purchaseManager.isUnlocked { dismiss() }
                    }
                } label: {
                    HStack {
                        if isPurchasing { ProgressView().tint(.white) }
                        Text(purchaseButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isPurchasing || purchaseManager.proProduct == nil)
                .padding(.horizontal)

                Button("Restore Purchases") {
                    Task {
                        await purchaseManager.restorePurchases()
                        if purchaseManager.isUnlocked { dismiss() }
                    }
                }
                .font(.footnote)
                .padding(.bottom, 8)
            }
            .navigationTitle("Pro Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = purchaseManager.proProduct?.displayPrice {
            return "Unlock for \(price)"
        }
        return "Unlock Pro"
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pro Status Row (for Settings)
struct ProStatusRow: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showPaywall = false

    var body: some View {
        Group {
            if purchaseManager.isUnlocked {
                Label("Pro Unlocked", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Unlock Pro", systemImage: "sparkles")
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
