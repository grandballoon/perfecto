import SwiftUI
import UIKit

/// The touch surface every chord layout is played through. The layout inside
/// only draws its keys and marks each with `chordKey(_:)`; this surface owns
/// the fingers. Each finger is tracked on its own (`ChordKeyTouches`), so any
/// layout can be played with several fingers and by sliding between keys.
/// Sliding up and down within a key is a control of its own (the slide),
/// reported alongside the key changes. While the key zones are on, the
/// surface marks where each zone ends on every key, by that key's own zones
/// if it has them, so every layout shows them.
///
/// Keys draw themselves as pressed from `PerformanceState.heldKeys`, the
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
                let shapes = anchors.mapValues { $0.shape(in: proxy) }
                KeyZoneEdges(keys: shapes.map { ($0.value, state.effects.zones(of: state.zonedDegree(of: $0.key)).edges) })
                ChordTouchLayer(shapes: shapes, state: state)
            }
        }
    }
}

extension View {
    /// Marks this view as `key` on the surface around it
    /// (`ChordKeySurface`, or `DegreeSelector`). With no key it is only drawn.
    /// The key is the part of the view its `outline` says: all of it, unless
    /// it is drawn as another shape.
    func chordKey(_ key: ChordKey?, outline: KeyOutline = .rect) -> some View {
        anchorPreference(key: ChordKeyFrames.self, value: .bounds) { anchor in
            key.map { [$0: ChordKeyAnchor(bounds: anchor, outline: outline)] } ?? [:]
        }
    }
}

/// The part of its view that a key is.
enum KeyOutline: Equatable {
    /// The whole view.
    case rect
    /// The circle that fills the view.
    case disc
    /// A piece of the ring that fills the view: between `angles`, in radians
    /// clockwise from the top, and from `inner` of the way out from the
    /// centre to the edge.
    case segment(angles: ClosedRange<CGFloat>, inner: CGFloat)

    /// The key's shape in a view at `frame`.
    func shape(in frame: CGRect) -> KeyShape {
        switch self {
        case .rect: return .rect(frame)
        case .disc: return .disc(frame)
        case .segment(let angles, let inner):
            let outer = min(frame.width, frame.height) / 2
            return .segment(RingSegment(center: CGPoint(x: frame.midX, y: frame.midY),
                                        radii: outer * inner...outer, angles: angles))
        }
    }
}

/// Where a key marked with `chordKey(_:outline:)` is.
struct ChordKeyAnchor {
    let bounds: Anchor<CGRect>
    let outline: KeyOutline

    func shape(in proxy: GeometryProxy) -> KeyShape {
        outline.shape(in: proxy[bounds])
    }
}

/// Every key marked with `chordKey(_:outline:)`.
struct ChordKeyFrames: PreferenceKey {
    static var defaultValue: [ChordKey: ChordKeyAnchor] { [:] }

    static func reduce(value: inout [ChordKey: ChordKeyAnchor],
                       nextValue: () -> [ChordKey: ChordKeyAnchor]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Marks where one key zone gives way to the next: a tick at each side of
/// every key, clear of its label and inside its outline whatever its shape.
/// Where a smaller key lies over a key (a piano's black keys), the ticks are
/// at the sides of what shows of it. A segment of a ring is played outwards,
/// so its ticks are pieces of the circle a zone ends at.
private struct KeyZoneEdges: View {
    /// Each key, and its zones' edges as places on the slide.
    let keys: [(shape: KeyShape, edges: [Float])]

    /// A tick's distance from the side of its key, and its length, as shares
    /// of the key's width.
    private static let inset: CGFloat = 0.1
    private static let length: CGFloat = 0.14

    var body: some View {
        Path { path in
            for (key, edges) in keys {
                for edge in edges {
                    let share = ChordKeySlide.share(at: edge)
                    switch key {
                    case .rect(let frame):
                        let y = frame.maxY - frame.height * share
                        let (minX, maxX) = showing(of: frame, at: y)
                        Self.ticks(in: &path, from: minX, to: maxX, at: y)
                    case .disc(let frame):
                        let y = frame.maxY - frame.height * share
                        let radius = frame.width / 2
                        let half = max(radius * radius - (y - frame.midY) * (y - frame.midY), 0).squareRoot()
                        Self.ticks(in: &path, from: frame.midX - half, to: frame.midX + half, at: y)
                    case .segment(let segment):
                        Self.ticks(in: &path, of: segment, at: share)
                    }
                }
            }
        }
        .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .allowsHitTesting(false)
    }

    private static func ticks(in path: inout Path, from minX: CGFloat, to maxX: CGFloat, at y: CGFloat) {
        let inset = (maxX - minX) * Self.inset
        let length = (maxX - minX) * Self.length
        path.move(to: CGPoint(x: minX + inset, y: y))
        path.addLine(to: CGPoint(x: minX + inset + length, y: y))
        path.move(to: CGPoint(x: maxX - inset - length, y: y))
        path.addLine(to: CGPoint(x: maxX - inset, y: y))
    }

    /// The ticks `share` of the way out across `segment`.
    private static func ticks(in path: inout Path, of segment: RingSegment, at share: CGFloat) {
        let radius = segment.radii.lowerBound + (segment.radii.upperBound - segment.radii.lowerBound) * share
        let (from, to) = (segment.angles.lowerBound, segment.angles.upperBound)
        let inset = (to - from) * Self.inset
        let length = (to - from) * Self.length
        for start in [from + inset, to - inset - length] {
            path.move(to: segment.point(at: start, radius: radius))
            // An angle here is from the top, and a path's is from the right.
            path.addArc(center: segment.center, radius: radius, startAngle: .radians(start - .pi / 2),
                        endAngle: .radians(start + length - .pi / 2), clockwise: false)
        }
    }

    /// The span of the key at `key` that shows at the height `y`: its width,
    /// less what the smaller keys lying over its sides there cover.
    private func showing(of key: CGRect, at y: CGFloat) -> (minX: CGFloat, maxX: CGFloat) {
        var (minX, maxX) = (key.minX, key.maxX)
        for case (.rect(let other), _) in keys where other.width < key.width && other.intersects(key)
            && (other.minY...other.maxY).contains(y) {
            if other.midX < key.midX { minX = max(minX, other.maxX) } else { maxX = min(maxX, other.minX) }
        }
        return (minX, maxX)
    }
}

private struct ChordTouchLayer: UIViewRepresentable {
    let shapes: [ChordKey: KeyShape]
    let state: PerformanceState

    func makeUIView(context: Context) -> ChordTouchView {
        let view = ChordTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: ChordTouchView, context: Context) {
        view.keyTouches.shapes = shapes
        view.state = state
    }
}

/// Receives raw touches, which SwiftUI gestures cannot tell apart, and
/// reports the resulting key changes. A cancelled touch, or the view leaving
/// the screen, releases its keys, so a key can never be left down.
private final class ChordTouchView: UIView {
    var keyTouches = ChordKeyTouches<ObjectIdentifier>()
    weak var state: PerformanceState?

    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { haptic.prepare() }
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
            if change.pressed != nil {
                haptic.impactOccurred()
                // Kept ready, so the next key's is as strong and as prompt.
                haptic.prepare()
            }
            state?.movePointer(from: change.released, to: change.pressed)
        }
    }

    private func lift(_ touches: Set<UITouch>) {
        state?.release(keyTouches.lift(touches.map(ObjectIdentifier.init)))
    }
}
