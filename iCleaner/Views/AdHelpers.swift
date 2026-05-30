import UIKit

enum AdHelpers {
    /// Returns the top-most presented view controller — needed by AdMob interstitial presentation.
    static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var current = keyWindow?.rootViewController
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}
