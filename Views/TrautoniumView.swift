import SwiftUI
import UIKit

/// Where the Trautonium's bars are, for a board of a given size, and where
/// a point is on one. The one place that says so: the board draws its bars
/// here and reads its fingers against the same frames, so the two cannot
/// disagree.
///
/// The bars run along the board's longer side, so they are as long as the
/// screen lets them be however it is held. Lying flat, the high bar is over
/// the low one, pitch goes up to the right, and a bar is loud at its top
/// edge. Upright, the low bar is the leading one, pitch goes up the screen,
/// and a bar is loud at its trailing edge.
enum TrautoniumBars {
    /// The space between the bars.
    static let gap: CGFloat = 12

    static func axis(in size: CGSize) -> Axis {
        size.width >= size.height ? .horizontal : .vertical
    }

    static func frames(in size: CGSize) -> [TrautoniumBar: CGRect] {
        guard size.width > 0, size.height > 0 else { return [:] }
        switch axis(in: size) {
        case .horizontal:
            let height = (size.height - gap) / 2
            return [.high: CGRect(x: 0, y: 0, width: size.width, height: height),
                    .low: CGRect(x: 0, y: height + gap, width: size.width, height: height)]
        case .vertical:
            let width = (size.width - gap) / 2
            return [.low: CGRect(x: 0, y: 0, width: width, height: size.height),
                    .high: CGRect(x: width + gap, y: 0, width: width, height: size.height)]
        }
    }

    /// Where `point` is on the bar at `frame`. A point off the bar is at
    /// the nearest place on it.
    static func place(of point: CGPoint, in frame: CGRect, axis: Axis) -> BarPlace {
        let right = Double((point.x - frame.minX) / frame.width).clamped(to: 0...1)
        let up = Double((frame.maxY - point.y) / frame.height).clamped(to: 0...1)
        return axis == .horizontal ? BarPlace(along: right, across: up) : BarPlace(along: up, across: right)
    }

    /// The point of the bar at `frame` that `place` is.
    static func point(of place: BarPlace, in frame: CGRect, axis: Axis) -> CGPoint {
        let (right, up) = axis == .horizontal ? (place.along, place.across) : (place.across, place.along)
        return CGPoint(x: frame.minX + frame.width * right, y: frame.maxY - frame.height * up)
    }
}

/// Which finger plays each bar. A bar is one voice, so of the fingers on it
/// the one that came down last plays it, and lifting that one hands the bar
/// back to the finger beneath, as the chord keys do. A finger stays with
/// the bar it came down on wherever it goes, so one that slides past a
/// bar's end or edge goes on playing it from there.
struct BarTouches<Pointer: Hashable> {

    /// What a touch did to a bar.
    enum Change: Equatable {
        /// A finger took the bar, at this place.
        case pressed(TrautoniumBar, BarPlace)
        /// The bar's finger moved there.
        case moved(TrautoniumBar, BarPlace)
        /// The bar's last finger lifted.
        case released(TrautoniumBar)
    }

    var frames: [TrautoniumBar: CGRect] = [:]
    var axis: Axis = .horizontal

    /// The fingers on each bar, the oldest first, each where it is.
    private var held: [TrautoniumBar: [(pointer: Pointer, place: BarPlace)]] = [:]

    /// A finger comes down. One that is on no bar plays nothing.
    mutating func down(_ pointer: Pointer, at point: CGPoint) -> Change? {
        guard let (bar, frame) = frames.first(where: { $0.value.contains(point) }) else { return nil }
        let place = TrautoniumBars.place(of: point, in: frame, axis: axis)
        held[bar, default: []].append((pointer, place))
        return .pressed(bar, place)
    }

    mutating func move(_ pointer: Pointer, to point: CGPoint) -> Change? {
        for (bar, fingers) in held {
            guard let index = fingers.firstIndex(where: { $0.pointer == pointer }),
                  let frame = frames[bar] else { continue }
            let place = TrautoniumBars.place(of: point, in: frame, axis: axis)
            held[bar]?[index].place = place
            return index == fingers.count - 1 ? .moved(bar, place) : nil
        }
        return nil
    }

    mutating func lift(_ pointer: Pointer) -> Change? {
        for (bar, fingers) in held {
            guard let index = fingers.firstIndex(where: { $0.pointer == pointer }) else { continue }
            held[bar]?.remove(at: index)
            guard index == fingers.count - 1 else { return nil }
            if let beneath = held[bar]?.last { return .pressed(bar, beneath.place) }
            return .released(bar)
        }
        return nil
    }

    /// Every finger lifts at once. The bars that were being played.
    mutating func liftAll() -> [TrautoniumBar] {
        defer { held = [:] }
        return held.filter { !$0.value.isEmpty }.map(\.key)
    }
}

/// The Trautonium, wired to the live performance (`TrautoniumState`): its
/// two bars, each played by where a finger is on it. Along a bar is pitch
/// and across it how loud; the notes of the key are marked, and a finger
/// comes down on the nearest.
struct TrautoniumView: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let trautonium = state.trautonium
        GeometryReader { geo in
            let axis = TrautoniumBars.axis(in: geo.size)
            let frames = TrautoniumBars.frames(in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(TrautoniumBar.allCases, id: \.self) { bar in
                    if let frame = frames[bar] {
                        BarView(range: trautonium.range(of: bar), notes: trautonium.notes(of: bar),
                                playing: trautonium.playing[bar], axis: axis)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                BarTouchLayer(frames: frames, axis: axis, trautonium: trautonium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One bar: darker at its quiet edge than at its loud one, with a line
/// across it at each note of the key, named at the quiet edge, the tonic's
/// in the display's color. While it sounds, a line marks the pitch that is
/// heard, the stronger the louder, and a ring the finger.
private struct BarView: View {
    let range: BarRange
    let notes: [Int]
    let playing: TrautoniumState.Playing?
    let axis: Axis

    private static let corner: CGFloat = 8
    /// How far from the quiet edge the notes' names are.
    private static let nameInset: CGFloat = 12
    private static let ring: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let frame = CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(white: 0.05), Color(white: 0.17)],
                               startPoint: axis == .horizontal ? .bottom : .leading,
                               endPoint: axis == .horizontal ? .top : .trailing)
                ForEach(notes, id: \.self) { note in
                    let isTonic = (note - range.lowest) % 12 == 0
                    line(at: Double(note), in: frame, width: 1)
                        .foregroundStyle(isTonic ? Color.orange.opacity(0.7) : Color(white: 0.32))
                    Text(PitchClass(rawValue: note % 12)!.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isTonic ? Color.orange : Color(white: 0.6))
                        .fixedSize()
                        .position(TrautoniumBars.point(of: BarPlace(along: range.place(of: Double(note)), across: 0),
                                                       in: frame.insetBy(dx: axis == .vertical ? Self.nameInset : 0,
                                                                         dy: axis == .horizontal ? Self.nameInset : 0),
                                                       axis: axis))
                }
                if let playing {
                    line(at: playing.pitch, in: frame, width: 3)
                        .foregroundStyle(Color.orange.opacity(0.35 + 0.65 * Double(playing.level)))
                    Circle()
                        .strokeBorder(Color.orange, lineWidth: 2)
                        .frame(width: Self.ring, height: Self.ring)
                        .position(TrautoniumBars.point(of: playing.place, in: frame, axis: axis))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(Color(white: 0.25), lineWidth: 1))
    }

    /// A line across the bar where `pitch` is.
    private func line(at pitch: Double, in frame: CGRect, width: CGFloat) -> some View {
        let middle = TrautoniumBars.point(of: BarPlace(along: range.place(of: pitch), across: 0.5),
                                          in: frame, axis: axis)
        return Rectangle()
            .frame(width: axis == .horizontal ? width : frame.width,
                   height: axis == .horizontal ? frame.height : width)
            .position(middle)
    }
}

private struct BarTouchLayer: UIViewRepresentable {
    let frames: [TrautoniumBar: CGRect]
    let axis: Axis
    let trautonium: TrautoniumState

    func makeUIView(context: Context) -> BarTouchView {
        let view = BarTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: BarTouchView, context: Context) {
        view.barTouches.frames = frames
        view.barTouches.axis = axis
        view.trautonium = trautonium
    }
}

/// Receives the board's raw touches and plays the bars by them. A cancelled
/// touch, or the view leaving the screen, releases its bar, so a note can
/// never be left sounding.
private final class BarTouchView: UIView {
    var barTouches = BarTouches<ObjectIdentifier>()
    weak var trautonium: TrautoniumState?

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let change = barTouches.down(ObjectIdentifier(touch), at: touch.location(in: self))
            if change != nil { haptic.impactOccurred() }
            play(change)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { play(barTouches.move(ObjectIdentifier(touch), to: touch.location(in: self))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { play(barTouches.lift(ObjectIdentifier(touch))) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { play(barTouches.lift(ObjectIdentifier(touch))) }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { barTouches.liftAll().forEach { trautonium?.release($0) } }
    }

    private func play(_ change: BarTouches<ObjectIdentifier>.Change?) {
        switch change {
        case let .pressed(bar, place)?: trautonium?.press(bar, at: place)
        case let .moved(bar, place)?:   trautonium?.move(bar, to: place)
        case let .released(bar)?:       trautonium?.release(bar)
        case nil:                       break
        }
    }
}
