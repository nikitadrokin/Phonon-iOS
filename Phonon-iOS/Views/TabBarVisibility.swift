import SwiftUI
import UIKit

extension View {
    /// Slides the enclosing tab bar away while this view is on screen and brings it back when it
    /// is popped, following an interactive swipe-back (and staying hidden if the swipe is cancelled).
    func hidesTabBar() -> some View {
        background(TabBarHider().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

private struct TabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            tabBarController?.setTabBarHidden(true, animated: animated)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Covers the case where SwiftUI attaches this controller after the push started.
            if tabBarController?.isTabBarHidden == false {
                tabBarController?.setTabBarHidden(true, animated: true)
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let tabBarController else { return }
            guard animated, let coordinator = transitionCoordinator, coordinator.isInteractive else {
                tabBarController.setTabBarHidden(false, animated: animated)
                return
            }
            // Interactive swipe-back: show the bar only once the pop actually commits.
            coordinator.notifyWhenInteractionChanges { [weak tabBarController] context in
                guard !context.isCancelled else { return }
                tabBarController?.setTabBarHidden(false, animated: true)
            }
            coordinator.animate(alongsideTransition: nil) { [weak tabBarController] context in
                guard !context.isCancelled else { return }
                tabBarController?.setTabBarHidden(false, animated: true)
            }
        }
    }
}
