import Combine
import StoreKit

public typealias Transaction = StoreKit.Transaction
public typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
public typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

// MARK: - StoreProtocol

public protocol StoreProtocol: ObservableObject {

  var subscriptions: [Product] { get }

  var purchasedIdentifiers: Set<String> { get }

  func checkVerified<T>(_ result: VerificationResult<T>) throws -> T

  func eligibleForIntro(product: Product) async throws -> Bool

  func tier(for productId: String) -> Store.SubscriptionTier

  func isPurchased(_ productIdentifier: String) async throws -> Bool

  func purchase(_ product: Product) async throws -> Transaction?
}
