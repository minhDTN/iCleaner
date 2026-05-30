import Foundation
import StoreKit
import LibEarnMoneyIOS

enum MyProduct: String, CaseIterable, BaseProduct {
    case weekly      = "com.minhdtn.icleaner.weekly"
    case yearlyTrial = "com.minhdtn.icleaner.yearly.trial"

    var id: String { rawValue }
    var productType: Product.ProductType { .autoRenewable }
    var nonRenewableDuration: Duration? { nil }
    var metadata: [String: Any]? { nil }
}
