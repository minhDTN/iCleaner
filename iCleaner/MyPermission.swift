import Foundation
import LibEarnMoneyIOS

enum MyPermission: String, CaseIterable, BasePermission {
    case premium

    var id: String { rawValue }

    var products: [any BaseProduct] {
        switch self {
        case .premium: return [MyProduct.weekly, MyProduct.yearlyTrial]
        }
    }
}
