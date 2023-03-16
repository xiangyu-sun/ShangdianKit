import StoreKit

extension Product {
  public var subscribeText: String {
    guard let subscription else {
      return "unknow"
    }
    let unit: String

    switch subscription.subscriptionPeriod.unit {
    case .day:
      let localized = NSLocalizedString("day_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, subscription.subscriptionPeriod.value)
    case .week:
      let localized = NSLocalizedString("week_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, subscription.subscriptionPeriod.value)
    case .month:
      let localized = NSLocalizedString("month_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, subscription.subscriptionPeriod.value)
    case .year:
      let localized = NSLocalizedString("year_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, subscription.subscriptionPeriod.value)
    @unknown default:
      unit = NSLocalizedString("period", comment: "")
    }

    return "\(displayPrice) / \(unit)"
  }
}

extension Product.SubscriptionOffer {
  public var subscribeText: String {
    let unit: String
    switch period.unit {
    case .day:
      let localized = NSLocalizedString("day_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, period.value)
    case .week:
      let localized = NSLocalizedString("week_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, period.value)
    case .month:
      let localized = NSLocalizedString("month_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, period.value)
    case .year:
      let localized = NSLocalizedString("year_sufix", comment: "")
      unit = String.localizedStringWithFormat(localized, period.value)
    @unknown default:
      unit = NSLocalizedString("period", comment: "")
    }

    return "Start a \(unit) free trial"
  }
}
