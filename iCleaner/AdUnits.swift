import Foundation

// QRCode AdMob ad unit IDs.
// AdMob App ID: <TODO: replace with real QRCode app ID before release>
// Currently using Google's official test IDs so dev builds always get fill.
// Replace each with the real QRCode ad unit ID before App Store submission.
enum AdUnits {
    // App Open / Splash
    static let openSplash    = "ca-app-pub-3940256099942544/5575463023"   // TODO: open_splash
    static let openAll       = "ca-app-pub-3940256099942544/5575463023"   // TODO: open_all (Settings return)
    static let interSplash   = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_splash

    // Banners
    static let bannerScanResult  = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_scan_result
    static let bannerBatchResult = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_batch_result
    static let bannerHistory     = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_history
    static let bannerCreate      = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_create
    static let bannerSetting     = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_setting

    // Interstitials
    static let interScanResult   = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_scan_result
    static let interBatchResult  = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_batch_result
    static let interHistoryView  = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_history_view (after Detail view)
    static let interCreateDone   = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_create_done (Continue on completion)

    // Natives
    static let nativeScanResult  = "ca-app-pub-3940256099942544/3986624511"   // TODO: native_scan_result
    static let nativeHistory     = "ca-app-pub-3940256099942544/3986624511"   // TODO: native_history (both tabs + Delete state)
}
