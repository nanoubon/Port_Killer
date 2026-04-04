import AppKit
import Combine
import Foundation
import StoreKit

@MainActor
final class ProPurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isProUnlocked = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let productIDs = [
        "com.nanodev1987.port-killer.pro.monthly",
        "com.nanodev1987.port-killer.pro.lifetime"
    ]

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForTransactionUpdates()
        }

        Task {
            await refreshCatalog()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            productRank(lhs.id) < productRank(rhs.id)
        }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == productIDs[0] }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == productIDs[1] }
    }

    func refreshCatalog() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: productIDs)
            await refreshEntitlementStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try verify(verificationResult)
                await transaction.finish()
                await refreshEntitlementStatus()
                statusMessage = "Pro unlocked successfully."
                return true
            case .pending:
                statusMessage = "Purchase pending approval."
                return false
            case .userCancelled:
                statusMessage = "Purchase cancelled."
                return false
            @unknown default:
                statusMessage = "Purchase failed."
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlementStatus()
            statusMessage = "Purchases restored."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlockProImmediately() {
        isProUnlocked = true
        statusMessage = "Pro unlocked instantly."
        errorMessage = nil
    }

    func openManageSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
    }

    private func listenForTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            do {
                let transaction = try verify(verificationResult)
                await transaction.finish()
                await refreshEntitlementStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshEntitlementStatus() async {
        var unlocked = false

        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? verify(verificationResult) else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            unlocked = true
            break
        }

        isProUnlocked = unlocked
    }

    private func verify(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let transaction):
            return transaction
        }
    }

    private func productRank(_ id: String) -> Int {
        productIDs.firstIndex(of: id) ?? productIDs.count
    }
}
