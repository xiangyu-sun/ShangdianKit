import StoreKit
import SwiftUI

// MARK: - StatusInfoView

public struct StatusInfoView: View {

  // MARK: Internal

  @EnvironmentObject var store: Store

  let product: Product
  let status: Product.SubscriptionInfo.Status

  public var body: some View {
    Text(statusDescription())
      .font(.callout)
      .padding()
      .background(Color.orange.opacity(0.1))
      .multilineTextAlignment(.center)
      .cornerRadius(12)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  // MARK: Fileprivate

  // Build a string description of the subscription status to display to the user.
  fileprivate func statusDescription() -> String {
    guard
      case .verified(let renewalInfo) = status.renewalInfo,
      case .verified(let transaction) = status.transaction else
    {
      return NSLocalizedString("The App Store could not verify your subscription status.", comment: "")
    }

    var description = ""

    switch status.state {
    case .subscribed:
      description = subscribedDescription()
    case .expired:
      if
        let expirationDate = transaction.expirationDate,
        let expirationReason = renewalInfo.expirationReason
      {
        description = expirationDescription(expirationReason, expirationDate: expirationDate)
      }
    case .revoked:
      if let revokedDate = transaction.revocationDate {
        description = String.localizedStringWithFormat(NSLocalizedString("The App Store refunded your subscription to %1$@ on %2$@.", comment: ""), product.displayName, revokedDate.formattedDate())
      }
    case .inGracePeriod:
      description = gracePeriodDescription(renewalInfo)
    case .inBillingRetryPeriod:
      description = billingRetryDescription()
    default:
      break
    }

    if let expirationDate = transaction.expirationDate {
      description += renewalDescription(renewalInfo, expirationDate)
    }
    return description
  }

  fileprivate func billingRetryDescription() -> String {
    let description =  String.localizedStringWithFormat(NSLocalizedString("The App Store could not confirm your billing information for %1$@. Please verify your billing information to resume service.", comment: ""), product.displayName)
    return description
  }

  fileprivate func gracePeriodDescription(_ renewalInfo: RenewalInfo) -> String {
    var description = String.localizedStringWithFormat(NSLocalizedString("The App Store could not confirm your billing information for %1$@.", comment: ""), product.displayName)
    if let untilDate = renewalInfo.gracePeriodExpirationDate {
      description += String.localizedStringWithFormat(NSLocalizedString(" Please verify your billing information to continue service after %1$@.", comment: ""),untilDate.formattedDate())
    }

    return description
  }

  fileprivate func subscribedDescription() -> String {
    String.localizedStringWithFormat(NSLocalizedString("You are currently subscribed to %1$@.", comment: ""), product.displayName)
  }

  fileprivate func renewalDescription(_ renewalInfo: RenewalInfo, _ expirationDate: Date) -> String {
    var description = ""

    if let newProductID = renewalInfo.autoRenewPreference {
      if let newProduct = store.subscriptions.first(where: { $0.id == newProductID }) {
        description += String.localizedStringWithFormat(NSLocalizedString("\nYour subscription to %1$@ will begin when your current subscription expires on %2$@.", comment: ""), newProduct.displayName , expirationDate.formattedDate())
      }
    } else if renewalInfo.willAutoRenew {
      description +=  String.localizedStringWithFormat(NSLocalizedString("\nNext billing date: %1$@.", comment: ""), expirationDate.formattedDate())
    }

    return description
  }

  // Build a string description of the `expirationReason` to display to the user.
  fileprivate func expirationDescription(_ expirationReason: RenewalInfo.ExpirationReason, expirationDate: Date) -> String {
    var description = ""

    switch expirationReason {
    case .autoRenewDisabled:
      if expirationDate > Date() {
        description += String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ will expire on %2$@.", comment: ""), product.displayName, (expirationDate.formattedDate()))
      } else {
        description +=  String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ expired on %2$@.", comment: ""), product.displayName, (expirationDate.formattedDate()))
      }
    case .billingError:
      description =  String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ was not renewed due to a billing error.", comment: ""), product.displayName)
    case .didNotConsentToPriceIncrease:
      description =
      String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ was not renewed due to a price increase that you disapproved.", comment: ""), product.displayName)

    case .productUnavailable:
      description =  String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ was not renewed because the product is no longer available.", comment: ""), product.displayName)

    default:
      
      description =  String.localizedStringWithFormat(NSLocalizedString("Your subscription to %1$@ was not renewed.", comment: ""), product.displayName)
    }

    return description
  }
}

extension Date {
  func formattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MMM dd, yyyy"
    return dateFormatter.string(from: self)
  }
}
