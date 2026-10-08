import SwiftUI
import UIKit

/// Where the solo strip's cells are, for a strip of a given size. The one
/// place that says so: the strip draws its cells here and reads its
/// fingers against the same frames, so the two cannot disagree.
enum SoloStripCells {
    /// The least a cell is wide where the strip lies flat: about the chord
    /// colors' own cells.
    static let minWidth: CGFloat = 42
    /// The height a row of cells needs; a strip with room for more rows has them.
    static let rowHeight: CGFloat = 80
    static let maxRows = 3
    /// The least a cell is tall where the strip stands upright.
    static let minHeight: CGFloat = 40
    /// The line between cells.
    static let gap: CGFloat = 1

    /// The cells' frames, lowest note first. Flat, a row runs low to high
    /// from the leading edge, and the rows go up from the bottom, as the
    /// notes do. Upright, the cells are one column with the lowest at the bottom.
    static func frames(in size: CGSize, axis: Axis) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let columns = axis == .horizontal ? max(1, Int(size.width / minWidth)) : 1
        let rows = axis == .horizontal
            ? min(maxRows, max(1, Int(size.height / rowHeight)))
            : max(1, Int(size.height / minHeight))
        let width = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return (0..<rows * columns).map { cell in
            let row = CGFloat(cell / columns), column = CGFloat(cell % columns)
            return CGRect(x: column * (width + gap),
                          y: size.height - (row + 1) * height - row * gap,
                          width: width, height: height)
        }
    }
}

/// The solo strip, wired to the live performance: a cell for each note
/// that fits the chord being played (`SoloState`), low to high along `axis`.
/// Like the chord keys it is played with several fingers and by sliding,
/// tracked by the same rules (`KeyTouches`); the cell that sounds is lit.
///
/// It is drawn like the chord-color surfaces. The chord's own tones are
/// tinted, and its root carries a mark, so the eye finds the notes to land on.
struct SoloStripView: View {

    let axis: Axis

    @Environment(PerformanceState.self) private var state

    var body: some View {
        GeometryReader { geo in
            let frames = SoloStripCells.frames(in: geo.size, axis: axis)
            let notes = state.solo.notes(frames.count)
            ZStack(alignment: .topLeading) {
                Color(white: 0.2)
                ForEach(Array(frames.enumerated()), id: \.offset) { cell, frame in
                    SoloCell(note: cell < notes.count ? notes[cell] : nil,
                             isSounding: state.solo.held.last == cell,
                             axis: axis)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                // Only the cells that have a note can be played.
                SoloTouchLayer(frames: Dictionary(uniqueKeysWithValues: zip(notes.indices, frames)),
                               solo: state.solo)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
    }
}

/// One cell of the solo strip: its note's name and octave. A cell past the
/// end of MIDI's range has no note and is left empty.
private struct SoloCell: View {
    let note: SoloNote?
    let isSounding: Bool
    let axis: Axis

    /// The mark on the chord's root, along the cell's low edge.
    private let markWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Color(white: 0.08)
            if isSounding {
                Color.black
                Color.orange.opacity(0.85)
            } else if let note, note.role != .passing {
                Color.orange.opacity(0.25)
            }
            if let note { label(note) }
        }
        .overlay(alignment: axis == .horizontal ? .bottom : .leading) {
            if note?.role == .root, !isSounding {
                Color.orange.frame(width: axis == .vertical ? markWidth : nil,
                                   height: axis == .horizontal ? markWidth : nil)
            }
        }
    }

    @ViewBuilder
    private func label(_ note: SoloNote) -> some View {
        let name = Text(PitchClass(rawValue: note.note % 12)!.name)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(isSounding ? .black.opacity(0.8)
                             : Color(white: note.role == .passing ? 0.5 : 0.85))
        let octave = Text("\(note.note / 12 - 1)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(isSounding ? .black.opacity(0.8)
                             : Color(white: note.role == .passing ? 0.5 : 0.7))
        Group {
            if axis == .horizontal {
                VStack(spacing: 3) { name; octave }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) { name; octave }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(2)
    }
}

/// The handle between the chord keys and the solo strip under them: drag it
/// to give the strip more of the keys' height, or less (`SoloState.share`).
struct SoloStripHandle: View {

    /// The height the strip's share is a share of.
    let screenHeight: CGFloat

    @Environment(PerformanceState.self) private var state
    /// The strip's share when the drag began.
    @State private var shareAtStart: CGFloat?

    static let height: CGFloat = 24

    var body: some View {
        Capsule()
            .fill(Color(white: 0.35))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = shareAtStart ?? state.solo.share
                        shareAtStart = start
                        // Up the screen is more strip.
                        state.solo.resize(to: start - drag.translation.height / screenHeight)
                    }
                    .onEnded { _ in shareAtStart = nil }
            )
            .accessibilityLabel("Solo strip height")
    }
}

private struct SoloTouchLayer: UIViewRepresentable {
    let frames: [Int: CGRect]
    let solo: SoloState

    func makeUIView(context: Context) -> SoloTouchView {
        let view = SoloTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: SoloTouchView, context: Context) {
        view.cellTouches.frames = frames
        view.solo = solo
    }
}

/// Receives the strip's raw touches and reports the resulting cell changes.
/// A cancelled touch, or the view leaving the screen, releases its cells, so
/// a note can never be left sounding.
private final class SoloTouchView: UIView {
    var cellTouches = KeyTouches<ObjectIdentifier, Int>()
    weak var solo: SoloState?

    private let haptic = UIImpactFeedbackGenerator(style: .light)

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
        if newWindow == nil { solo?.release(cellTouches.liftAll()) }
    }

    private func track(_ touches: Set<UITouch>) {
        for touch in touches {
            let change = cellTouches.touch(ObjectIdentifier(touch), at: touch.location(in: self))
            if change.pressed != nil { haptic.impactOccurred() }
            solo?.movePointer(from: change.released, to: change.pressed)
        }
    }

    private func lift(_ touches: Set<UITouch>) {
        solo?.release(cellTouches.lift(touches.map(ObjectIdentifier.init)))
    }
}
