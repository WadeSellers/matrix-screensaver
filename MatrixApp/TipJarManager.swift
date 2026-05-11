import Foundation
import StoreKit
import os.log

private let log = OSLog(subsystem: "com.wadesellers.cipherfall", category: "tipjar")

/// Owns the three "Support development" Consumable IAP products and the
/// StoreKit 2 purchase / transaction-update plumbing. Mirrors the
/// `@MainActor` manager-class shape used by `MatrixWallpaperManager` /
/// `MatrixSession` — one instance lives on `AppDelegate`, the SwiftUI
/// `SupportView` reads its `@Observable` state.
///
/// Why Consumable and not Non-Consumable:
/// - Users can re-tip the same tier as many times as they want.
/// - Apple only mandates a "Restore Purchases" button for Non-Consumables,
///   so the UI stays minimal.
/// - The tip jar gates no functionality; there's nothing to "own."
@MainActor
@Observable
final class TipJarManager {
    /// The three IAP product identifiers, in priced order. These MUST match
    /// the records configured in App Store Connect (and the local
    /// `Configuration.storekit` file used for dev testing).
    static let productIDs: [String] = [
        "com.wadesellers.cipherfall.tip.coffee",   // $2.99
        "com.wadesellers.cipherfall.tip.lunch",    // $9.99
        "com.wadesellers.cipherfall.tip.awesome",  // $19.99
    ]

    /// Products as returned by `Product.products(for:)`, sorted by price
    /// ascending so the SupportView can render them left-to-right without
    /// re-sorting.
    private(set) var products: [Product] = []

    /// `productID` of the tier currently mid-purchase. Used by SupportView
    /// to show a spinner on the right card. `nil` when no purchase is
    /// running.
    private(set) var purchaseInFlightID: String?

    /// `productID` of the last tier that successfully purchased. SupportView
    /// uses this to flip the card to a "Thank you ❤️" state for ~2 seconds.
    /// Reset to `nil` automatically after the thank-you window expires.
    private(set) var lastThankYouTier: String?

    /// User-presentable error string from the most recent failed purchase
    /// (network failure, verification failure, etc.). User-cancelled
    /// purchases do NOT populate this — cancel is not an error.
    private(set) var lastError: String?

    /// True until the first `Product.products(for:)` call completes (success
    /// or failure). Used to show a one-time loading spinner instead of an
    /// empty card grid when the window first opens.
    private(set) var isLoadingProducts: Bool = true

    /// Fired immediately after a verified, finished purchase. AppDelegate
    /// hooks this to launch the fullscreen "Decode" thank-you Easter egg.
    /// The argument is the purchased `Product` so the receiver can
    /// differentiate (e.g., a $19 "you're a legend" signature vs a
    /// $2.99 "for the coffee").
    var onPurchaseSucceeded: ((Product) -> Void)?

    // nonisolated so deinit (which is implicitly nonisolated) can call
    // .cancel() on the listener. `Task` is Sendable and .cancel() is
    // thread-safe.
    private nonisolated(unsafe) var transactionListener: Task<Void, Never>? = nil

    init() {
        // Start the transaction listener first so any transactions Apple
        // delivers during the initial product fetch (or before we finish
        // an in-flight purchase from a previous launch) are finished
        // properly. StoreKit 2 requires every Transaction to be finished
        // explicitly or it will redeliver forever.
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }

        Task { [weak self] in
            await self?.loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product loading

    private func loadProducts() async {
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            // Price-ascending sort. Apple doesn't guarantee return order.
            products = fetched.sorted { $0.price < $1.price }
            os_log("loaded %{public}d product(s)", log: log, type: .info, products.count)
        } catch {
            os_log("product fetch failed: %{public}@",
                   log: log, type: .error, String(describing: error))
            lastError = "Couldn't reach the App Store. Check your network and try again."
        }
    }

    /// Re-fetch products. Called by SupportView's "Try again" button when
    /// the initial fetch failed.
    func reloadProducts() {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        lastError = nil
        Task { await loadProducts() }
    }

    // MARK: - Purchase flow

    func purchase(_ product: Product) async {
        guard purchaseInFlightID == nil else { return }
        purchaseInFlightID = product.id
        lastError = nil
        defer { purchaseInFlightID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    os_log("purchase verified: %{public}@",
                           log: log, type: .info, transaction.productID)
                    await transaction.finish()
                    showThankYou(forTier: transaction.productID)
                    onPurchaseSucceeded?(product)
                case .unverified(_, let error):
                    os_log("purchase unverified: %{public}@",
                           log: log, type: .error, String(describing: error))
                    lastError = "Apple couldn't verify the purchase. No charge was made."
                }
            case .userCancelled:
                // Not an error — silent return so the card flips back to idle.
                os_log("purchase cancelled by user", log: log, type: .info)
            case .pending:
                // Awaiting external action (e.g. Ask to Buy approval). The
                // transaction listener will pick up the eventual completion.
                os_log("purchase pending external approval",
                       log: log, type: .info)
                lastError = "Your purchase is pending approval and will complete shortly."
            @unknown default:
                lastError = "Unexpected purchase result from the App Store."
            }
        } catch {
            os_log("purchase threw: %{public}@",
                   log: log, type: .error, String(describing: error))
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Transaction listener (background completion)

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            os_log("background transaction: %{public}@",
                   log: log, type: .info, transaction.productID)
            await transaction.finish()
            // Don't show the thank-you for background completions — the
            // user may not be looking at the Support tab.
        case .unverified(_, let error):
            os_log("background transaction unverified: %{public}@",
                   log: log, type: .error, String(describing: error))
        }
    }

    // MARK: - Thank-you state

    private func showThankYou(forTier productID: String) {
        lastThankYouTier = productID
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                if self?.lastThankYouTier == productID {
                    self?.lastThankYouTier = nil
                }
            }
        }
    }
}
