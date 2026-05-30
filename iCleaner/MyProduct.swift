import Foundation
import StoreKit
import LibEarnMoneyIOS

// iCleaner has 3 SKUs in App Store Connect:
//   • weekly       — $1.99/week, no intro offer.
//   • weeklyTrial  — $1.99/week with a 3-day free trial intro offer.
//   • monthly      — $4.99/month.
//
// Paywall toggle "Enable Free Trial" switches between `weekly` and `weeklyTrial`
// at purchase time (same price, different intro). User can also pick `monthly`.
enum MyProduct: String, CaseIterable, BaseProduct {
    case weekly      = "com.minhdtn.icleaner.weekly"
    case weeklyTrial = "com.minhdtn.icleaner.weekly.trial"
    case monthly     = "com.minhdtn.icleaner.monthly"

    var id: String { rawValue }
    var productType: Product.ProductType { .autoRenewable }
    var nonRenewableDuration: Duration? { nil }
    var metadata: [String: Any]? { nil }
}
