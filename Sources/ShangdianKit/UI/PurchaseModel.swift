import StoreKit
import SwiftUI

public final class PurchaseModel: ObservableObject {

  @Published
  var errorTitle: String? = nil
  @Published
  var isPurchased = false

  @MainActor
  func buy(product: Product, store: Store) async {
    do {
      if try await store.purchase(product) != nil {
        withAnimation {
          isPurchased = true
        }
      }
    } catch StoreError.failedVerification {
      errorTitle = NSLocalizedString("Your purchase could not be verified by the App Store.", comment: "")
    } catch {
      errorTitle = error.localizedDescription
    }
  }

}
