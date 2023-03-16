import StoreKit
import SwiftUI

public struct ListCellView: View {

  // MARK: Lifecycle
  
  public init(product: Product, purchasingEnabled: Bool = true) {
    self.product = product
    self.purchasingEnabled = purchasingEnabled
  }

  // MARK: Internal

  @EnvironmentObject var store: Store

  @State var isShowingError = false
  @StateObject var purchaseModel: PurchaseModel = .init()

  let product: Product
  let purchasingEnabled: Bool

  public var body: some View {
    HStack {
      if purchasingEnabled {
        productDetail
        Spacer()
        buyButton
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .disabled(purchaseModel.isPurchased)
      } else {
        productDetail
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.blue.opacity(0.1))
          .cornerRadius(12)
      }
    }
    .frame(maxWidth: .infinity)
    .alert(isPresented: $isShowingError, content: {
      Alert(title: Text(purchaseModel.errorTitle ?? ""), message: nil, dismissButton: .default(Text("Okay")))
    })
  }

  @ViewBuilder
  var productDetail: some View {
    if product.type == .autoRenewable {
      VStack(alignment: .leading) {
        Text(product.displayName)
          .bold()
        Text(product.description)
      }
    } else {
      Text(product.description)
        .frame(alignment: .leading)
    }
  }

  var buyButton: some View {
    Button(action: {
      Task {
        await purchaseModel.buy(product: product,store: store)
      }
    }) {
      if purchaseModel.isPurchased {
        Text(Image(systemName: "checkmark"))
          .bold()
          .foregroundColor(.white)
      } else {
        if let subscription = product.subscription {
          Text(product.subscribeText)
        } else {
          Text(product.displayPrice)
            .foregroundColor(.white)
            .bold()
        }
      }
    }
    .onAppear {
      Task {
        do {
          if let state = try await product.subscription?.status.first?.state {
            switch state {
            case .expired, .revoked, .inBillingRetryPeriod:
              purchaseModel.isPurchased = false
            default:
              purchaseModel.isPurchased = try await store.isPurchased(product.id)
              
            }
          }
        } catch {
          purchaseModel.errorTitle = error.localizedDescription
        }
      }
    }
    .onChange(of: purchaseModel.errorTitle) { identifiers in
      isShowingError.toggle()
    }
  }
}
