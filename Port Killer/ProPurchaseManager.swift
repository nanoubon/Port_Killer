import Combine
import Foundation
import StoreKit

@MainActor
final class ProPurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isProUnlocked = true
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    init() {
        statusMessage = "All Pro features are included for free in this build."
    }

    var sortedProducts: [Product] {
        []
    }

    var monthlyProduct: Product? {
        nil
    }

    var lifetimeProduct: Product? {
        nil
    }

    func refreshCatalog() async {
        statusMessage = "All Pro features are already unlocked."
        errorMessage = nil
    }

    func purchase(_ product: Product) async -> Bool {
        _ = product
        statusMessage = "All Pro features are already unlocked."
        errorMessage = nil
        return true
    }

    func restorePurchases() async {
        statusMessage = "Nothing to restore. All Pro features are already unlocked."
        errorMessage = nil
    }

    func openManageSubscriptions() {
        statusMessage = "Nothing to manage. All Pro features are already available."
        errorMessage = nil
    }
}
