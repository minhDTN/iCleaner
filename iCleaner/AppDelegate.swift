import UIKit
import Firebase
import FirebaseMessaging
import LibEarnMoneyIOS

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LibEarnMoneyIOS.shared.bootstrap(
            with: makeLibConfig(),
            application: application,
            launchOptions: launchOptions
        )

        UNUserNotificationCenter.current().delegate = LibEarnMoneyIOS.shared.notificationDelegate
        Messaging.messaging().delegate = LibEarnMoneyIOS.shared.messagingDelegate
        application.registerForRemoteNotifications()

        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LibEarnMoneyIOS.shared.application(application,
                                           didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        LibEarnMoneyIOS.shared.application(application,
                                           didReceiveRemoteNotification: userInfo,
                                           fetchCompletionHandler: completionHandler)
    }
}
