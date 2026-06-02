import Foundation

// iCleaner AdMob ad unit IDs — from the production ads scenario sheet.
// App pub account: ca-app-pub-5904408074441373
// NOTE: the AdMob App ID (GADApplicationIdentifier, the "~" id) is set in
// Info.plist and is NOT in the sheet — replace it there with the real iCleaner
// app id before release.
enum AdUnits {
    private static let pub = "ca-app-pub-5904408074441373"

    // 1 — Splash
    static let openSplash  = "\(pub)/3063900777"   // appopen_splash
    static let interSplash = "\(pub)/1750819106"   // inter_splash

    // 2 — App open on return from background (all screens)
    static let openAll     = "\(pub)/2213853535"   // open_all

    // 12 — Shared interstitial for every action button
    static let interGlobal = "\(pub)/3560770391"   // inter_global

    // 3-14 — Banners
    static let bannerHome             = "\(pub)/2439260411"   // banner_home (Home tab)
    static let bannerCompress         = "\(pub)/1126178744"   // banner_compress (Compress tab)
    static let bannerReviewGroup      = "\(pub)/8813097079"   // banner_review_group (similar review list)
    static let bannerVideoCompress    = "\(pub)/7500015400"   // banner_video_compress (compress ready screen)
    static let bannerSuccessCompress  = "\(pub)/6811574096"   // banner_success_view_compress
    static let bannerSetting          = "\(pub)/6186933733"   // banner_setting
    static let bannerContactUs        = "\(pub)/3335363519"   // banner_contact_us
    static let bannerPreviewSimilar   = "\(pub)/2247688725"   // banner_preview_similar (similar preview, bottom)
    static let bannerPreviewImage     = "\(pub)/9934607050"   // banner_preview_image (vault preview, bottom)

    // 6-10 — Natives
    static let nativeVideoCompress    = "\(pub)/7421644261"   // native_video_compress (Compressing screen)
    static let nativeSuccessDelete    = "\(pub)/5498492428"   // native_success_view_delete
    static let nativeSuccessClean     = "\(pub)/8587690199"   // native_success_view_clean (Congratulations)
    static let nativeFaq              = "\(pub)/5961526858"   // native_faq
    static let nativeLanguage         = "\(pub)/4873852068"   // native_language
}
