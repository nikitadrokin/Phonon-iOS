import SwiftUI
import UIKit

extension View {
    /// Slides the enclosing tab bar away while this view is on screen and brings it back when it
    /// is popped, following an interactive swipe-back (and staying hidden if the swipe is cancelled).
    /// The now-playing accessory is hidden and shown at the same moments, through SwiftUI (see
    /// `setNowPlayingAccessoryHidden`), since UIKit cannot take it off a SwiftUI tab view safely.
    func hidesTabBar() -> some View {
        background(TabBarHider().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

private struct TabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.setAccessoryHidden = context.environment.setNowPlayingAccessoryHidden
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.setAccessoryHidden = context.environment.setNowPlayingAccessoryHidden
    }

    final class Controller: UIViewController {
        var setAccessoryHidden: (@MainActor (_ hidden: Bool, _ animated: Bool) -> Void)?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            tabBarController?.setTabBarHidden(true, animated: animated)
            setAccessoryHidden?(true, animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Covers the case where SwiftUI attaches this controller after the push started.
            if tabBarController?.isTabBarHidden == false {
                tabBarController?.setTabBarHidden(true, animated: true)
            }
            setAccessoryHidden?(true, true)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let tabBarController else { return }
            let setAccessoryHidden = setAccessoryHidden
            guard animated, let coordinator = transitionCoordinator, coordinator.isInteractive else {
                tabBarController.setTabBarHidden(false, animated: animated)
                setAccessoryHidden?(false, animated)
                return
            }
            // Interactive swipe-back: show the bars only once the pop actually commits.
            coordinator.notifyWhenInteractionChanges { [weak tabBarController] context in
                guard !context.isCancelled else { return }
                tabBarController?.setTabBarHidden(false, animated: true)
                setAccessoryHidden?(false, true)
            }
            coordinator.animate(alongsideTransition: nil) { [weak tabBarController] context in
                guard !context.isCancelled else { return }
                tabBarController?.setTabBarHidden(false, animated: true)
                setAccessoryHidden?(false, true)
            }
        }
    }
}
