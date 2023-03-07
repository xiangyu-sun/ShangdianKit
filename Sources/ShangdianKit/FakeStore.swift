import Combine
import StoreKit

public final class FakeStore: StoreProtocol {

  // MARK: Public

  @Published
  public private(set) var subscriptions: [Product]

  @Published
  public private(set) var purchasedIdentifiers = Set<String>()
  
  public init() {
    if
      let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
      let plist = FileManager.default.contents(atPath: path)
    {
      productList = (try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Int]) ?? [:]

      subscriptionTiers = productList.map { Store.SubscriptionTier(id: $0.key, rank: $0.value) }
    } else {
      productList = [:]
      subscriptionTiers = []
      print("product list not found")
    }
    subscriptions = []
  }

  // MARK: Internal

  public func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    // Check if the transaction passes StoreKit verification.
    switch result {
    case .unverified:
      // StoreKit has parsed the JWS but failed verification. Don't deliver content to the user.
      throw StoreError.failedVerification
    case .verified(let safe):
      // If the transaction is verified, unwrap and return it.
      return safe
    }
  }

  public func eligibleForIntro(product _: Product) async throws -> Bool {
    true
  }

  public func tier(for productId: String) -> Store.SubscriptionTier {
    subscriptionTiers.first { $0.id == productId } ?? .empty
  }

  public func isPurchased(_: String) async throws -> Bool {
    true
  }

  public func purchase(_ product: Product) async throws -> Transaction? {
    // Begin a purchase.
    let result = try await product.purchase()

    switch result {
    case .success(let verification):
      let transaction = try checkVerified(verification)

      purchasedIdentifiers.insert(transaction.productID)
      
      // Always finish a transaction.
      await transaction.finish()

      return transaction
    case .userCancelled, .pending:
      return nil
    default:
      return nil
    }
  }
  
  // MARK: Private

  private let subscriptionTiers: [Store.SubscriptionTier]

  private let productList: [String: Int]
}
