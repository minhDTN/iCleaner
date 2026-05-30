import UIKit
import LibEarnMoneyIOS

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        LibEarnMoneyIOS.shared.installRootWindow(window)
    }

    func sceneWillResignActive(_ scene: UIScene)   { LibEarnMoneyIOS.shared.sceneWillResignActive() }
    func sceneDidEnterBackground(_ scene: UIScene) { LibEarnMoneyIOS.shared.sceneDidEnterBackground() }
    func sceneDidBecomeActive(_ scene: UIScene)    { LibEarnMoneyIOS.shared.sceneDidBecomeActive() }
}
