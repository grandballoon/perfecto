import SwiftUI
import UIKit

/// The piano's touches, which move what is in view and play nothing: a
/// pinch brings it closer or farther around the fingers, a drag moves it
/// along (one finger or two, or a trackpad's or a mouse wheel's scroll),
/// and a double tap expands or shrinks it.
///
/// It is UIKit because SwiftUI's pinch does not say where the fingers are
/// as they move, so it could not also be a drag. Each change is reported as
/// it happens, from the last, in this view's points.
struct PianoTouches: UIViewRepresentable {
    /// The piano is `scale` times closer around `x`.
    var onZoom: (_ scale: CGFloat, _ x: CGFloat) -> Void
    /// The piano is moved `dx` along, toward the high end if negative.
    var onDrag: (_ dx: CGFloat) -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.handlers = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: PianoTouches
        /// The fingers the drag had at its last change.
        private var fingers = 0

        init(_ handlers: PianoTouches) {
            self.handlers = handlers
        }

        func attach(to view: UIView) {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
            let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
            drag.maximumNumberOfTouches = 2
            drag.allowedScrollTypesMask = .all
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
            doubleTap.numberOfTapsRequired = 2
            for recognizer in [pinch, drag, doubleTap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        /// A pinch is also a drag, so the fingers' middle moves the piano
        /// as they spread.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            recognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
        }

        @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
            guard pinch.state == .changed, let view = pinch.view else { return }
            handlers.onZoom(pinch.scale, pinch.location(in: view).x)
            pinch.scale = 1
        }

        @objc private func dragged(_ drag: UIPanGestureRecognizer) {
            guard let view = drag.view else { return }
            let moved = drag.translation(in: view)
            drag.setTranslation(.zero, in: view)
            // A finger put down or lifted moves the fingers' middle without
            // dragging anything.
            let count = drag.numberOfTouches
            defer { fingers = count }
            guard drag.state == .changed, count == fingers else { return }
            // A scroll has no fingers; a mouse wheel's, up and down, moves
            // the piano along too.
            let dx = count == 0 && abs(moved.y) > abs(moved.x) ? moved.y : moved.x
            handlers.onDrag(dx)
        }

        @objc private func doubleTapped() {
            handlers.onDoubleTap()
        }
    }
}
