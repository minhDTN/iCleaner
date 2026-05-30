import Foundation
import StoreKit
import LibEarnMoneyIOS

enum MyProduct: String, CaseIterable, BaseProduct {
    case weekly      = "com.minhdtn.qrcode.weekly"
    case yearlyTrial = "com.minhdtn.qrcode.yearly.trial"

    var id: String { rawValue }
    var productType: Product.ProductType { .autoRenewable }
    var nonRenewableDuration: Duration? { nil }
    var metadata: [String: Any]? { nil }
}
