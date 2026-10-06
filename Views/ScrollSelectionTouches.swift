import SwiftUI
import UIKit

/// Touch handling for a scroll view whose content is selected by one finger
/// and scrolled by two. Placed behind the scrolling content, it finds the
/// enclosing scroll view, raises its pan to two fingers, and adds a one-finger
/// tap and a one-finger pan (the sweep) of its own.
///
/// It is UIKit because SwiftUI gestures cannot count fingers: a SwiftUI drag
/// on scrolling content either blocks the scroll or fights it. UIKit's
/// recognizers are exclusive by default, so a touch is a tap, a sweep or a
/// scroll, never two of them.
///
/// Points are reported in this view's own coordinates, which are those of the
/// content it backs.
struct ScrollSelectionTouches: UIViewRepresentable {
    /// Whether a tap at this point selects something. Taps elsewhere are left
    /// to the controls in the content (buttons keep working).
    var canTap: (CGPoint) -> Bool
    var onTap: (CGPoint) -> Void
    var onSweepChanged: (_ start: CGPoint, _ current: CGPoint) -> Void
    var onSweepEnded: (_ start: CGPoint, _ current: CGPoint) -> Void
    /// The system took the touch mid-sweep; nothing is to be committed.
    var onSweepCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.handlers = self
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Marks where the content is, and attaches the recognizers once it is in
    /// a scroll view.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            guard let scrollView = ancestor as? UIScrollView else { return }
            coordinator?.attach(to: scrollView, anchor: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: ScrollSelectionTouches
        private weak var scrollView: UIScrollView?
        private weak var anchor: UIView?
        private var scrollTouchesBefore = 1
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        private lazy var sweep = UIPanGestureRecognizer(target: self, action: #selector(swept))

        init(_ handlers: ScrollSelectionTouches) {
            self.handlers = handlers
        }

        func attach(to scrollView: UIScrollView, anchor: UIView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            self.anchor = anchor
            scrollTouchesBefore = scrollView.panGestureRecognizer.minimumNumberOfTouches
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
            sweep.maximumNumberOfTouches = 1
            tap.delegate = self
            // Buttons in the content must still receive their touches.
            tap.cancelsTouchesInView = false
            sweep.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(tap)
            scrollView.addGestureRecognizer(sweep)
        }

        func detach() {
            guard let scrollView else { return }
            scrollView.panGestureRecognizer.minimumNumberOfTouches = scrollTouchesBefore
            scrollView.removeGestureRecognizer(tap)
            scrollView.removeGestureRecognizer(sweep)
            self.scrollView = nil
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            handlers.canTap(recognizer.location(in: anchor))
        }

        @objc private func tapped() {
            handlers.onTap(tap.location(in: anchor))
        }

        @objc private func swept() {
            let current = sweep.location(in: anchor)
            let moved = sweep.translation(in: anchor)
            let start = CGPoint(x: current.x - moved.x, y: current.y - moved.y)
            switch sweep.state {
            case .began, .changed: handlers.onSweepChanged(start, current)
            case .ended:           handlers.onSweepEnded(start, current)
            case .cancelled, .failed: handlers.onSweepCancelled()
            default: break
            }
        }
    }
}
