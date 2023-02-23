import Foundation
import StoreKit
import Combine

public typealias Transaction = StoreKit.Transaction
public typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
public typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

public typealias ProdictID = String

// MARK: - StoreError

public enum StoreError: Error {
  case failedVerification
}

// MARK: - Store

public final class Store: ObservableObject {
  
  public struct SubscriptionTier: Comparable {
    let id: String
    let rank: Int
    
    static let empty = SubscriptionTier(id: "", rank: 0)
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rank < rhs.rank
    }
  }

  // MARK: Lifecycle
  
  private let subscriptionTiers: [SubscriptionTier]

  init() {
    if
      let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
      let plist = FileManager.default.contents(atPath: path)
    {
      productList = (try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Int]) ?? [:]
      
      subscriptionTiers = productList.map{ SubscriptionTier(id: $0.key, rank: $0.value) }
    } else {
      productList = [:]
      subscriptionTiers = []
      print("product list not found")
    }
    
    // Initialize empty products then do a product request asynchronously to fill them in.
    subscriptions = []

    // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
    updateListenerTask = listenForTransactions()

    Task {
      await requestProducts()
    }
  }

  deinit {
    updateListenerTask?.cancel()
  }

  // MARK: Internal

  public static let current = Store()

  @Published
  public private(set) var subscriptions: [Product]

  @Published
  public private(set) var purchasedIdentifiers = Set<String>()

  var updateListenerTask: Task<Void, Error>? = nil

  func listenForTransactions() -> Task<Void, Error> {
    Task.detached {
      // Iterate through any transactions which didn't come from a direct call to `purchase()`.
      for await result in Transaction.updates {
        do {
          let transaction = try self.checkVerified(result)

          // Deliver content to the user.
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

  @MainActor
  func requestProducts() async {
    do {
      // Request products from the App Store using the identifiers defined in the Products.plist file.
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
    } catch {
      print("Failed product request: \(error)")
    }
  }

  public func purchase(_ product: Product) async throws -> Transaction? {
    // Begin a purchase.
    let result = try await product.purchase()

    switch result {
    case .success(let verification):
      let transaction = try checkVerified(verification)

      // Deliver content to the user.
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

  func sortByPrice(_ products: [Product]) -> [Product] {
    products.sorted(by: { $0.price < $1.price })
  }

  public func tier(for productId: String) -> SubscriptionTier {
    subscriptionTiers.first{ $0.id == productId} ?? .empty
  }


  private let productList: [String: Int]
}