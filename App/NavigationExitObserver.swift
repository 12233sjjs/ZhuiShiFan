import SwiftUI
import UIKit

// Presenting AVPlayer fullscreen temporarily hides the hosting view, but leaves
// it in the navigation stack. Only a real navigation exit releases playback.
struct NavigationExitObserver: UIViewControllerRepresentable {
    let onExit: () -> Void
    func makeUIViewController(context: Context) -> ExitController {
        let controller = ExitController()
        controller.onExit = onExit
        return controller
    }
    func updateUIViewController(_ controller: ExitController, context: Context) {
        controller.onExit = onExit
    }

    final class ExitController: UIViewController {
        var onExit: (() -> Void)?
        private weak var owner: UIViewController?
        private weak var navigation: UINavigationController?
        private var exited = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var current: UIViewController? = parent
            while let candidate = current {
                if let navigation = candidate.navigationController,
                   navigation.viewControllers.contains(where: { $0 === candidate }) {
                    self.owner = candidate
                    self.navigation = navigation
                    break
                }
                current = candidate.parent
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // Wait for interactive pop transitions to settle, including cancellation.
            if let transition = owner?.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { [weak self] context in
                    if !context.isCancelled { self?.checkExit() }
                }
            } else { checkExit() }
        }

        private func checkExit() {
            guard !exited, let owner, let navigation else { return }
            if Self.hasExited(owner: owner, navigation: navigation) {
                exited = true
                onExit?()
            }
        }

        static func hasExited(owner: UIViewController, navigation: UINavigationController) -> Bool {
            !navigation.viewControllers.contains(where: { $0 === owner })
        }
    }
}
