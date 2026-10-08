import SwiftUI
import Testing
import UIKit

/// Puts `view` on screen in the test host's scene and draws it once.
@MainActor
func show(_ view: some View) throws -> UIWindow {
    let scene = try #require(UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    redraw(window)
    return window
}

/// Runs the SwiftUI update and layout that a frame would, now.
@MainActor
func redraw(_ window: UIWindow) {
    window.setNeedsLayout()
    window.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
