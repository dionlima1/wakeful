import Foundation
import StoreKit

/// One-time "Wakeful Pro" unlock (non-consumable, Family Sharing enabled in App Store Connect).
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()
    static let productID = "com.dionlima.wakeful.pro"
    private static let cacheKey = "proUnlockedCache"

    enum PurchaseState: Equatable {
        case idle, purchasing, pending, failed(String)
    }

    private(set) var isPro: Bool
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle
    /// Called after the user tries to use a Pro feature without owning Pro.
    var onProRequired: (() -> Void)?

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugUnlockPro") { isPro = true }
        #endif
    }

    func start() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    /// Returns true when Pro is available; otherwise asks the UI to show the upgrade screen.
    func require() -> Bool {
        if !isPro { onProRequired?() }
        return isPro
    }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    func purchase() async {
        guard let product else {
            await loadProduct()
            if self.product == nil { purchaseState = .failed(String(localized: "The App Store is not available right now.")) }
            return
        }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return }
        setPro(transaction.revocationDate == nil)
        await transaction.finish()
    }

    private func setPro(_ value: Bool) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugUnlockPro") { return }
        #endif
        isPro = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }
}
