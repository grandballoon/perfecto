import SwiftUI
import UIKit

/// The pads, wired to the live performance (`PadsState`): their row of
/// controls, the grid, and under it, while they are edited, the editor of
/// the pad chosen.
struct PadsView: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            PadsControls()
            PadsBoard()
            if state.pads.isEditing { PadEditor() }
        }
    }
}

/// The pads' row of controls: the switch that plays the grid in sequence,
/// the name of the pad being edited or played, and the switch that edits.
/// A screen that has a row to spare for them puts them there (a phone on
/// its side).
struct PadsControls: View {
    @Environment(PerformanceState.self) private var state

    private static let chitWidth: CGFloat = 52

    var body: some View {
        @Bindable var pads = state.pads
        HStack(spacing: 12) {
            chit(isOn: $pads.isRunning, label: pads.isRunning ? "Stop the sequence" : "Play the pads in sequence") {
                Image(systemName: pads.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(name)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(PadStyle.display)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            chit(isOn: $pads.isEditing, label: "Edit the pads") {
                Text("EDIT")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
        }
    }

    /// The pad the row names: the one being edited, or else the one played
    /// last of those held, or else the one the sequence is at.
    private var name: String {
        let pads = state.pads
        guard let place = pads.edited ?? pads.held.last ?? pads.step else { return "—" }
        guard let sound = pads.grid[place] else { return pads.isEditing ? "No sound" : "—" }
        return "\(sound.label) · \(sound.preset.name)"
    }

    /// A switch of the row, lit while it is on as the screen's others are.
    private func chit<Label: View>(isOn: Binding<Bool>, label: String,
                                   @ViewBuilder content: () -> Label) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            content()
                .foregroundStyle(isOn.wrappedValue ? Color.black : Color(white: 0.85))
                .frame(width: Self.chitWidth, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.orange : Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(isOn.wrappedValue ? Color.orange : Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// Where the pads are, for a board of a given size. The one place that says
/// so: the board draws its pads here and reads its fingers against the same
/// frames, so the two cannot disagree.
enum PadCells {
    /// The space between pads.
    static let gap: CGFloat = 6

    /// Every pad's frame: the board divided evenly, whatever its shape.
    static func frames(in size: CGSize, grid: PadGrid) -> [PadPlace: CGRect] {
        guard size.width > 0, size.height > 0 else { return [:] }
        let width = (size.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
        let height = (size.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return Dictionary(uniqueKeysWithValues: grid.places.map { place in
            (place, CGRect(x: CGFloat(place.column) * (width + gap), y: CGFloat(place.row) * (height + gap),
                           width: width, height: height))
        })
    }
}

/// The grid of pads as it is played. Like the chord keys it is played with
/// several fingers and by sliding, tracked by the same rules (`KeyTouches`);
/// every pad under a finger sounds, and the pad the sequence is at is lit
/// with them.
struct PadsBoard: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let pads = state.pads
        GeometryReader { geo in
            let frames = PadCells.frames(in: geo.size, grid: pads.grid)
            ZStack(alignment: .topLeading) {
                ForEach(pads.grid.places, id: \.self) { place in
                    if let frame = frames[place] {
                        PadCell(sound: pads.grid[place],
                                isSounding: pads.held.contains(place) || pads.step == place,
                                isSelected: pads.edited == place)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                PadTouchLayer(frames: frames, pads: pads)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One pad: the chord it plays, named, and the sound it plays it in. A pad
/// with no sound is left dark.
private struct PadCell: View {
    let sound: PadSound?
    let isSounding: Bool
    let isSelected: Bool

    private static let corner: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(stroke, lineWidth: isSelected ? 2 : 1))
            if let sound {
                VStack(spacing: 2) {
                    Text(sound.label)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSounding ? Color.black.opacity(0.8) : .white)
                    Text(sound.preset.name)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(isSounding ? Color.black.opacity(0.6) : Color(white: 0.6))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(3)
            }
        }
        .scaleEffect(isSounding ? 0.96 : 1)
        .animation(.easeInOut(duration: 0.06), value: isSounding)
    }

    private var fill: Color {
        switch (sound != nil, isSounding) {
        case (true, true):   return Color.orange.opacity(0.9)
        case (true, false):  return Color.orange.opacity(0.3)
        // The sequence passing over a rest.
        case (false, true):  return Color(white: 0.22)
        case (false, false): return Color(white: 0.08)
        }
    }

    private var stroke: Color {
        if isSelected { return .white }
        return sound == nil ? Color(white: 0.22) : Color.orange
    }
}

/// The colors the pads' screen is drawn in.
enum PadStyle {
    /// The keys' display's amber.
    static let display = Color(red: 1, green: 0.65, blue: 0)
}

private struct PadTouchLayer: UIViewRepresentable {
    let frames: [PadPlace: CGRect]
    let pads: PadsState

    func makeUIView(context: Context) -> PadTouchView {
        let view = PadTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: PadTouchView, context: Context) {
        view.padTouches.frames = frames
        view.pads = pads
    }
}

/// Receives the board's raw touches and reports the resulting pad changes.
/// A cancelled touch, or the view leaving the screen, releases its pads, so
/// a pad can never be left sounding.
private final class PadTouchView: UIView {
    var padTouches = KeyTouches<ObjectIdentifier, PadPlace>()
    weak var pads: PadsState?

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
        if newWindow == nil { pads?.release(padTouches.liftAll()) }
    }

    private func track(_ touches: Set<UITouch>) {
        for touch in touches {
            let change = padTouches.touch(ObjectIdentifier(touch), at: touch.location(in: self))
            if change.pressed != nil { haptic.impactOccurred() }
            pads?.movePointer(from: change.released, to: change.pressed)
        }
    }

    private func lift(_ touches: Set<UITouch>) {
        pads?.release(padTouches.lift(touches.map(ObjectIdentifier.init)))
    }
}
