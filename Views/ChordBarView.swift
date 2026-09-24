import SwiftUI

/// Play-mode wrapper around `ChordColorBar`, wired to the live performance
/// direction. The bar itself (layout, labels, gesture) lives in `ChordColorBar`
/// so Play mode and the Sequencer step editor stay pixel-identical.
struct ChordBarView: View {

    let axis: Axis

    @Environment(PerformanceState.self) private var state

    var body: some View {
        ChordColorBar(
            axis: axis,
            mode: state.joystickMode,
            selected: state.joystickDirection,
            onChange: { state.joystickMoved(to: $0) },
            onEnd: { state.joystickMoved(to: .center) }
        )
    }
}
