import Foundation

// iCleaner AdMob ad unit IDs.
// AdMob App ID: <TODO: replace with real iCleaner app ID before release — currently using QRCode's>
// Currently using Google's official test IDs so dev builds always get fill.
// Replace each with the real iCleaner ad unit ID before App Store submission.
enum AdUnits {
    // App Open / Splash
    static let openSplash    = "ca-app-pub-3940256099942544/5575463023"   // TODO: open_splash
    static let openAll       = "ca-app-pub-3940256099942544/5575463023"   // TODO: open_all (Settings return)
    static let interSplash   = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_splash

    // Banners
    static let bannerHome        = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_home
    static let bannerContacts    = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_contacts
    static let bannerVault       = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_vault
    static let bannerCompress    = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_compress
    static let bannerSettings    = "ca-app-pub-3940256099942544/2934735716"   // TODO: banner_settings

    // Interstitials
    static let interQuickClean        = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_quick_clean (after Quick Clean success)
    static let interSimilarClean      = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_similar_clean (after Delete N Selected)
    static let interCompressResult    = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_compress_result (Replace/Keep Both → return)
    static let interVaultUnlock       = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_vault_unlock (after biometric/passcode)
    static let interContactsAction    = "ca-app-pub-3940256099942544/4411468910"   // TODO: inter_contacts_action (merge/delete/backup)

    // Natives
    static let nativeHome             = "ca-app-pub-3940256099942544/3986624511"   // TODO: native_home (between category cards)
    static let nativeSimilarList      = "ca-app-pub-3940256099942544/3986624511"   // TODO: native_similar_list (in Similar/Duplicates review)
    static let nativeContactsList     = "ca-app-pub-3940256099942544/3986624511"   // TODO: native_contacts_list
}
