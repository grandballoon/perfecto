import SwiftUI

/// Play mode's chord-color input: the joystick bar or the chord grid,
/// whichever Setup selects, wired to the live performance. `PlaySurfaceView`
/// places it.
struct ColorSurfaceView: View {

    /// Which way the joystick bar runs. The chord grid ignores it.
    var barAxis: Axis = .horizontal

    @Environment(PerformanceState.self) private var state

    var body: some View {
        switch state.colorSurface {
        case .joystick:
            ChordBarView(axis: barAxis)
        case .grid:
            // Labels follow the held chord; with none held, the tonic's.
            ChordGridPad(
                key: state.playedKey,
                degree: state.activeDegree ?? .I,
                selected: state.gridPosition,
                onChange: { state.gridMoved(to: $0) },
                onEnd: { state.gridMoved(to: nil) }
            )
        }
    }
}
