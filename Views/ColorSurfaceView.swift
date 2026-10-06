import SwiftUI

/// Play mode's chord-color input: the joystick bar or the chord grid,
/// whichever Settings selects, wired to the live performance.
struct ColorSurfaceView: View {

    /// Which way the joystick bar runs. The chord grid ignores it.
    var barAxis: Axis = .horizontal

    @Environment(PerformanceState.self) private var state

    /// The joystick bar's short side, whichever way it runs.
    static let barThickness: CGFloat = 88

    /// Portrait height: the bar is one strip, the grid a row per mode.
    static func portraitHeight(_ surface: ColorSurface) -> CGFloat {
        switch surface {
        case .joystick: return barThickness
        case .grid:     return 196
        }
    }

    var body: some View {
        switch state.colorSurface {
        case .joystick:
            ChordBarView(axis: barAxis)
        case .grid:
            // Labels follow the held chord; with none held, the tonic's.
            ChordGridPad(
                key: state.key,
                degree: state.activeDegree ?? .I,
                selected: state.gridPosition,
                onChange: { state.gridMoved(to: $0) },
                onEnd: { state.gridMoved(to: nil) }
            )
        }
    }
}
