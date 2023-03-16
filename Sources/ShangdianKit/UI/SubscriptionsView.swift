import StoreKit
import SwiftUI

// MARK: - SubscriptionsView

public struct SubscriptionsView: View {
  
  public init() {
    
  }
  
  // MARK: Public

  public var body: some View {
    Group {
      if let currentSubscription {
        Section(header: Text("My Subscription")) {
          ListCellView(product: currentSubscription, purchasingEnabled: false)

          if let status {
            StatusInfoView(
              product: currentSubscription,
              status: status)
          }
        }
        .listStyle(GroupedListStyle())
      }

      Section(header: Text("Subscription Options")) {
        if let product = offerProduct, let trial = product.subscription?.introductoryOffer, hasOffer {
          Button {
            Task {
              await purchaseModel.buy(product: product ,store: store)
            }
          } label: {
            Text("\(trial.subscribeText)")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
        }

        ForEach(availableSubscriptions, id: \.id) { product in
          ListCellView(product: product)
        }
      }
      .listStyle(GroupedListStyle())
    }
    .onAppear {
      Task {
        // When this view appears, get the latest subscription status.
        await updateSubscriptionStatus()
        await updateOffer()
      }
    }
    .onChange(of: store.subscriptions) { _ in
      Task {
        await updateOffer()
      }
    }
    .onChange(of: purchaseModel.errorTitle) { title in
      if let title, !title.isEmpty {
        isShowingError = true
      }
    }
    .onChange(of: store.purchasedSubscriptions) { _ in
      Task {
        // When `purchasedIdentifiers` changes, get the latest subscription status.
        await updateSubscriptionStatus()
      }
    }
    .onChange(of: purchaseModel.isPurchased) { hasPurchased in
      hasOffer = !hasPurchased
    }
    .alert(isPresented: $isShowingError, content: {
      Alert(title: Text(purchaseModel.errorTitle ?? ""), message: nil, dismissButton: .default(Text("Okay")))
    })
  }

  // MARK: Internal

  @EnvironmentObject var store: Store

  @State var currentSubscription: Product?
  @State var status: Product.SubscriptionInfo.Status?
  @State var hasOffer = false

  @State var isShowingError = false
  @StateObject var purchaseModel: PurchaseModel = .init()

  var availableSubscriptions: [Product] {
    store.subscriptions.filter { $0.id != currentSubscription?.id }
  }

  @MainActor
  func updateOffer() async {
    do {
      guard let offerProduct else {
        return
      }
      hasOffer = try await store.eligibleForIntro(product: offerProduct)
    } catch {
      purchaseModel.errorTitle = error.localizedDescription
    }
  }

  @MainActor
  func updateSubscriptionStatus() async {
    do {
      let (highestStatus, highestProduct) = try await store.updateSubscriptionStatus()

      status = highestStatus
      currentSubscription = highestProduct
    } catch {
      purchaseModel.errorTitle = error.localizedDescription
    }
  }

  // MARK: Private

  private var offerProduct: Product? {
    store.subscriptions.first(where: { $0.subscription?.introductoryOffer != nil })
  }

}

// MARK: - SubscriptionsView_Previews

struct SubscriptionsView_Previews: PreviewProvider {
  static var previews: some View {
    List {
      SubscriptionsView()
        .environmentObject(Store(configuration: .init(productPlistName: "Products")))
    }
  }
}
