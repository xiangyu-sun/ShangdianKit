import Combine
import Foundation
import StoreKit

// MARK: - Store

public class Store: ObservableObject {

  // MARK: Lifecycle

  public init(configuration: Configuration) {
    self.configuration = configuration

    if
      let path = Bundle.main.path(forResource: configuration.productPlistName, ofType: "plist"),
      let plist = FileManager.default.contents(atPath: path)
    {
      productList = (try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Int]) ?? [:]

      subscriptionTiers = productList.map { SubscriptionTier(id: $0.key, rank: $0.value) }
    } else {
      productList = [:]
      subscriptionTiers = []
    }

    // Initialize empty products then do a product request asynchronously to fill them in.
    subscriptions = []

    // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
    updateListenerTask = listenForTransactions()

    Task {
      do {
        try await requestProducts()

        try await updateCustomerProductStatus(type: .autoRenewable)
      } catch {
        print(error)
      }
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  // MARK: Public

  public struct Configuration: Equatable {

    let productPlistName: String

    public static let preview: Configuration = .init(productPlistName: "Preview")

    public init(productPlistName: String) {
      self.productPlistName = productPlistName
    }

  }

  public struct SubscriptionTier: Comparable {
    let id: String
    let rank: Int

    static let empty = SubscriptionTier(id: "", rank: 0)

    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rank < rhs.rank
    }
  }

  @Published
  public private(set) var subscriptions: [Product]

  @Published
  public private(set) var purchasedIdentifiers = Set<String>()

  @Published
  public private(set) var purchasedSubscriptions: [Product] = []
  @Published
  public private(set) var subscriptionGroupStatus: RenewalState?

  public func purchase(_ product: Product) async throws -> Transaction? {
    // Begin a purchase.
    let result = try await product.purchase()

    switch result {
    case .success(let verification):
      let transaction = try checkVerified(verification)

      // Deliver content to the user.
      try await updateCustomerProductStatus(type: product.type)
      await updatePurchasedIdentifiers(transaction)

      // Always finish a transaction.
      await transaction.finish()

      return transaction
    case .userCancelled, .pending:
      return nil
    default:
      return nil
    }
  }

  public func isPurchased(_ productIdentifier: String) async throws -> Bool {
    // Get the most recent transaction receipt for this `productIdentifier`.
    guard let result = await Transaction.latest(for: productIdentifier) else {
      // If there is no latest transaction, the product has not been purchased.
      return false
    }

    let transaction = try checkVerified(result)

    // Ignore revoked transactions, they're no longer purchased.

    // For subscriptions, a user can upgrade in the middle of their subscription period. The lower service
    // tier will then have the `isUpgraded` flag set and there will be a new transaction for the higher service
    // tier. Ignore the lower service tier transactions which have been upgraded.
    return transaction.revocationDate == nil && !transaction.isUpgraded
  }

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

  public func eligibleForIntro(product: Product) async throws -> Bool {
    guard let renewableSubscription = product.subscription else {
      // No renewable subscription is available for this product.
      return false
    }
    if await renewableSubscription.isEligibleForIntroOffer {
      // The product is eligible for an introductory offer.
      return true
    }
    return false
  }

  public func tier(for productId: String) -> SubscriptionTier {
    subscriptionTiers.first { $0.id == productId } ?? .empty
  }

  @MainActor
  public func updateSubscriptionStatus() async throws -> (Product.SubscriptionInfo.Status?, Product?) {
    // This app has only one subscription group so products in the subscriptions
    // array all belong to the same group. The statuses returned by
    // `product.subscription.status` apply to the entire subscription group.
    guard
      let product = subscriptions.first,
      let statuses = try await product.subscription?.status else
    {
      return (nil, nil)
    }

    var highestStatus: Product.SubscriptionInfo.Status? = nil
    var highestProduct: Product? = nil

    // Iterate through `statuses` for this subscription group and find
    // the `Status` with the highest level of service which isn't
    // expired or revoked.
    for status in statuses {
      switch status.state {
      case .expired, .revoked:
        continue
      default:
        let renewalInfo = try checkVerified(status.renewalInfo)

        guard let newSubscription = subscriptions.first(where: { $0.id == renewalInfo.currentProductID }) else {
          continue
        }

        guard let currentProduct = highestProduct else {
          highestStatus = status
          highestProduct = newSubscription
          continue
        }

        let highestTier = tier(for: currentProduct.id)
        let newTier = tier(for: renewalInfo.currentProductID)

        if newTier > highestTier {
          highestStatus = status
          highestProduct = newSubscription
        }
      }
    }

    return (highestStatus, highestProduct)
  }

  @MainActor
  public func updateCustomerProductStatus(type: Product.ProductType) async throws {
    var purchasedSubscriptions: [Product] = []

    // Iterate through all of the user's purchased products.
    for await result in Transaction.currentEntitlements {
      // Check whether the transaction is verified. If it isn’t, catch `failedVerification` error.
      let transaction = try checkVerified(result)

      if let subscription = subscriptions.first(where: { $0.id == transaction.productID }), transaction.productType == type {
        purchasedSubscriptions.append(subscription)
      }
    }

    // Update the store information with auto-renewable subscription products.
    self.purchasedSubscriptions = purchasedSubscriptions

    // Check the `subscriptionGroupStatus` to learn the auto-renewable subscription state to determine whether the customer
    // is new (never subscribed), active, or inactive (expired subscription). This app has only one subscription
    // group, so products in the subscriptions array all belong to the same group. The statuses that
    // `product.subscription.status` returns apply to the entire subscription group.
    subscriptionGroupStatus = try await subscriptions.first?.subscription?.status.first?.state
  }

  // MARK: Internal

  let configuration: Configuration

  var updateListenerTask: Task<Void, Error>? = nil

  func listenForTransactions() -> Task<Void, Error> {
    Task.detached {
      // Iterate through any transactions which didn't come from a direct call to `purchase()`.
      for await result in Transaction.updates {
        do {
          let transaction = try self.checkVerified(result)

          // Deliver content to the user.
          try await self.updateCustomerProductStatus(type: .autoRenewable)
          await self.updatePurchasedIdentifiers(transaction)

          // Always finish a transaction.
          await transaction.finish()
        } catch {
          // StoreKit has a receipt it can read but it failed verification. Don't deliver content to the user.
          print("Transaction failed verification")
        }
      }
    }
  }

  /// Request products from the App Store using the identifiers defined in the configuration plist
  @MainActor
  func requestProducts() async throws {
    let storeProducts = try await Product.products(for: productList.keys)

    var newSubscriptions: [Product] = []

    // Filter the products into different categories based on their type.
    for product in storeProducts {
      switch product.type {
      case .autoRenewable:
        newSubscriptions.append(product)
      default:
        // Ignore this product.
        print("Unknown product")
      }
    }

    // Sort each product category by price, lowest to highest, to update the store.
    subscriptions = sortByPrice(newSubscriptions)
    print("recieved \(subscriptions)")
  }

  @MainActor
  func updatePurchasedIdentifiers(_ transaction: Transaction) async {
    if transaction.revocationDate == nil {
      // If the App Store has not revoked the transaction, add it to the list of `purchasedIdentifiers`.
      purchasedIdentifiers.insert(transaction.productID)
    } else {
      // If the App Store has revoked this transaction, remove it from the list of `purchasedIdentifiers`.
      purchasedIdentifiers.remove(transaction.productID)
    }
  }

  func sortByPrice(_ products: [Product]) -> [Product] {
    products.sorted(by: { $0.price < $1.price })
  }

  // MARK: Private

  private let subscriptionTiers: [SubscriptionTier]

  private let productList: [String: Int]
}
