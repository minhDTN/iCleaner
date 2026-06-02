import Foundation

// iCleaner AdMob ad unit IDs — from the production ads scenario sheet.
// App pub account: ca-app-pub-5904408074441373
// App ID (GADApplicationIdentifier) lives in Info.plist: ...~8649480938
//
// DEBUG builds route every placement to Google's official TEST ad units so each
// one always fills a test ad (safe to tap, verifiable on device + simulator).
// Release builds use the real units from the sheet.
enum AdUnits {
    private static let pub = "ca-app-pub-5904408074441373"

    // Google official test ad units (per AdMob docs).
    private enum Test {
        static let appOpen      = "ca-app-pub-3940256099942544/5575463023"
        static let banner       = "ca-app-pub-3940256099942544/2934735716"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        static let native       = "ca-app-pub-3940256099942544/3986624511"
    }

#if DEBUG
    // ---- TEST MODE (DEBUG) ----
    static let openSplash            = Test.appOpen
    static let interSplash           = Test.interstitial
    static let openAll               = Test.appOpen
    static let interGlobal           = Test.interstitial

    static let bannerHome            = Test.banner
    static let bannerCompress        = Test.banner
    static let bannerReviewGroup     = Test.banner
    static let bannerVideoCompress   = Test.banner
    static let bannerSuccessCompress = Test.banner
    static let bannerSetting         = Test.banner
    static let bannerContactUs       = Test.banner
    static let bannerPreviewSimilar  = Test.banner
    static let bannerPreviewImage    = Test.banner

    static let nativeVideoCompress   = Test.native
    static let nativeSuccessDelete   = Test.native
    static let nativeSuccessClean    = Test.native
    static let nativeFaq             = Test.native
    static let nativeLanguage        = Test.native
#else
    // ---- REAL UNITS (Release — from the ads sheet) ----
    static let openSplash            = "\(pub)/3063900777"   // appopen_splash
    static let interSplash           = "\(pub)/1750819106"   // inter_splash
    static let openAll               = "\(pub)/2213853535"   // open_all
    static let interGlobal           = "\(pub)/3560770391"   // inter_global

    static let bannerHome            = "\(pub)/2439260411"   // banner_home
    static let bannerCompress        = "\(pub)/1126178744"   // banner_compress
    static let bannerReviewGroup     = "\(pub)/8813097079"   // banner_review_group
    static let bannerVideoCompress   = "\(pub)/7500015400"   // banner_video_compress
    static let bannerSuccessCompress = "\(pub)/6811574096"   // banner_success_view_compress
    static let bannerSetting         = "\(pub)/6186933733"   // banner_setting
    static let bannerContactUs       = "\(pub)/3335363519"   // banner_contact_us
    static let bannerPreviewSimilar  = "\(pub)/2247688725"   // banner_preview_similar
    static let bannerPreviewImage    = "\(pub)/9934607050"   // banner_preview_image

    static let nativeVideoCompress   = "\(pub)/7421644261"   // native_video_compress
    static let nativeSuccessDelete   = "\(pub)/5498492428"   // native_success_view_delete
    static let nativeSuccessClean    = "\(pub)/8587690199"   // native_success_view_clean
    static let nativeFaq             = "\(pub)/5961526858"   // native_faq
    static let nativeLanguage        = "\(pub)/4873852068"   // native_language
#endif
}
