import SwiftUI
import UIKit

/// A display connected by cable or AirPlay (screen mirroring) while a prototype plays: it
/// shows the prototype alone, full size, without the phone's bars, buttons or pins, and
/// follows the phone, where the presenter taps through it (``PrototypeStageView/mirror``).
///
/// iOS hands an app that wants one a scene of the role
/// `windowExternalDisplayNonInteractive` (``ExternalDisplaySceneDelegate``). The window on
/// it only shows while a prototype plays; the rest of the time it is hidden, and the
/// display mirrors the phone as it would without the app.
@MainActor
@Observable
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    /// A display is there to present on.
    private(set) var isConnected = false

    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var mirror: PrototypeStageView?
    @ObservationIgnored private weak var presenter: PrototypeStageView?

    func connect(_ scene: UIWindowScene) {
        self.scene = scene
        isConnected = true
        update()
    }

    func disconnect(_ scene: UIScene) {
        guard scene === self.scene else { return }
        presenter?.mirror = nil
        window?.isHidden = true
        window = nil
        mirror = nil
        self.scene = nil
        isConnected = false
    }

    /// The stage on the phone to show, or, with `isOn` false, not that one any more.
    func present(_ stage: PrototypeStageView, isOn: Bool) {
        if isOn {
            guard presenter !== stage else { return }
            presenter?.mirror = nil
            presenter = stage
        } else {
            guard presenter === stage else { return }
            stage.mirror = nil
            presenter = nil
        }
        update()
    }

    private func update() {
        guard let scene, let presenter else {
            window?.isHidden = true
            mirror = nil
            window?.rootViewController = nil
            return
        }
        let window = self.window ?? UIWindow(windowScene: scene)
        self.window = window
        // The phone's appearance: Penpot's viewer is dark or light with the app.
        window.overrideUserInterfaceStyle = presenter.traitCollection.userInterfaceStyle
        if mirror == nil {
            let controller = UIViewController()
            controller.view.backgroundColor = .penpotPage
            let stage = PrototypeStageView()
            stage.isUserInteractionEnabled = false
            stage.showsNavigation = false
            stage.frame = controller.view.bounds
            stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            stage.accessibilityElementsHidden = true
            controller.view.addSubview(stage)
            window.rootViewController = controller
            mirror = stage
        }
        window.isHidden = false
        window.layoutIfNeeded()
        presenter.mirror = mirror
    }
}

/// The external display's scene (see ``ExternalDisplay``).
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        ExternalDisplay.shared.connect(scene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplay.shared.disconnect(scene)
    }
}

/// Gives an external display its own scene; every other scene stays SwiftUI's.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Not `connectingSceneSession.configuration`: reading it asks this method again,
        // without end. A configuration without a delegate class gets SwiftUI's.
        guard connectingSceneSession.role == .windowExternalDisplayNonInteractive else {
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }
}
