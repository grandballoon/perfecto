import SwiftUI
import UIKit

/// The touch surface every chord layout is played through. The layout inside
/// only draws its keys and marks each with `chordKey(_:)`; this surface owns
/// the fingers. Each finger is tracked on its own (`ChordKeyTouches`), so any
/// layout can be played with several fingers and by sliding between keys.
/// Sliding up and down within a key is a control of its own (the slide),
/// reported alongside the key changes. While the key zones are on, the
/// surface marks where each zone ends on every key, so every layout shows them.
///
/// Keys draw themselves as pressed from `PerformanceState.heldDegrees`, the
/// single record of what is down.
struct ChordKeySurface<Content: View>: View {
    @Environment(PerformanceState.self) private var state
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.overlayPreferenceValue(ChordKeyFrames.self) { anchors in
            GeometryReader { proxy in
                let frames = anchors.mapValues { proxy[$0] }
                KeyZoneEdges(keys: Array(frames.values), edges: state.effects.zones.edges)
                ChordTouchLayer(frames: frames, state: state)
            }
        }
    }
}

extension View {
    /// Marks this view as the key for `degree` on the surface around it
    /// (`ChordKeySurface`, or `DegreeSelector`).
    func chordKey(_ degree: Degree) -> some View {
        anchorPreference(key: ChordKeyFrames.self, value: .bounds) { [degree: $0] }
    }
}

/// Where each key marked with `chordKey(_:)` is.
struct ChordKeyFrames: PreferenceKey {
    static var defaultValue: [Degree: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [Degree: Anchor<CGRect>],
                       nextValue: () -> [Degree: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Marks where one key zone gives way to the next: a tick at each side of
/// every key, clear of its label and inside its outline whatever its shape.
private struct KeyZoneEdges: View {
    let keys: [CGRect]
    /// The edges, as places on the slide.
    let edges: [Float]

    /// A tick's distance from the side of its key, and its length, as shares
    /// of the key's width.
    private static let inset: CGFloat = 0.1
    private static let length: CGFloat = 0.14

    var body: some View {
        Path { path in
            for key in keys {
                let inset = key.width * Self.inset
                let length = key.width * Self.length
                for edge in edges {
                    let y = key.maxY - key.height * ChordKeySlide.share(at: edge)
                    path.move(to: CGPoint(x: key.minX + inset, y: y))
                    path.addLine(to: CGPoint(x: key.minX + inset + length, y: y))
                    path.move(to: CGPoint(x: key.maxX - inset - length, y: y))
                    path.addLine(to: CGPoint(x: key.maxX - inset, y: y))
                }
            }
        }
        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .allowsHitTesting(false)
    }
}

private struct ChordTouchLayer: UIViewRepresentable {
    let frames: [Degree: CGRect]
    let state: PerformanceState

    func makeUIView(context: Context) -> ChordTouchView {
        let view = ChordTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: ChordTouchView, context: Context) {
        view.keyTouches.frames = frames
        view.state = state
    }
}

/// Receives raw touches, which SwiftUI gestures cannot tell apart, and
/// reports the resulting key changes. A cancelled touch, or the view leaving
/// the screen, releases its keys, so a key can never be left down.
private final class ChordTouchView: UIView {
    var keyTouches = ChordKeyTouches<ObjectIdentifier>()
    weak var state: PerformanceState?

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        track(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        track(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { state?.release(keyTouches.liftAll()) }
    }

    private func track(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            let change = keyTouches.touch(id, at: point)
            // Before the key is pressed, so its chord starts where the finger landed.
            if let slide = keyTouches.slide(of: id, at: point) {
                state?.slide(on: slide.key, to: slide.height)
            }
            if change.pressed != nil { haptic.impactOccurred() }
            state?.movePointer(from: change.released, to: change.pressed)
        }
    }

    private func lift(_ touches: Set<UITouch>) {
        state?.release(keyTouches.lift(touches.map(ObjectIdentifier.init)))
    }
}
