import Foundation
import StoreKit

/// Tracks ownership of the one-time "Pro Unlock" non-consumable IAP that
/// gates default-Zelle settings and the "Not Paying" payer reassignment
/// feature. Entitlement state is derived from StoreKit's own transaction
/// log (`Transaction.currentEntitlements`), not a locally-persisted flag,
/// so a restore on a new device reflects the real purchase state.
@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductID = "com.rf.BI-Bill-Split.prounlock"

    @Published private(set) var isUnlocked = false
    @Published private(set) var proProduct: Product?
    @Published var purchaseErrorMessage: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlementStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            purchaseErrorMessage = "Couldn't load Pro Unlock: \(error.localizedDescription)"
        }
    }

    func purchase() async {
        guard let product = proProduct else {
            purchaseErrorMessage = "Pro Unlock isn't available right now. Please try again later."
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlementStatus()
        } catch {
            purchaseErrorMessage = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if transaction.productID == Self.proProductID, transaction.revocationDate == nil {
            isUnlocked = true
        }
        await transaction.finish()
    }

    private func refreshEntitlementStatus() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.proProductID, transaction.revocationDate == nil {
                isUnlocked = true
                return
            }
        }
        isUnlocked = false
    }
}
