import SwiftUI

/// Play mode's input surface beside the chord keys: the chord colors, in
/// one of two shapes (`SurfaceShape`) that the screen is laid out by. The
/// solo strip takes their place, as a bar, while it is on and placed there
/// (`SoloPlacement.colors`).
struct PlaySurfaceView: View {

    /// Which way a bar runs. A grid ignores it.
    var barAxis: Axis = .horizontal

    @Environment(PerformanceState.self) private var state

    var body: some View {
        if state.solo.takesColorsPlace {
            SoloStripView(axis: barAxis)
        } else {
            ColorSurfaceView(barAxis: barAxis)
        }
    }
}

extension SurfaceShape {
    /// A bar's short side, whichever way it runs.
    static let barThickness: CGFloat = 88

    /// Portrait height: a bar is one strip; a grid has room for the chord
    /// grid's row per mode.
    var portraitHeight: CGFloat {
        switch self {
        case .bar:  return Self.barThickness
        case .grid: return 196
        }
    }
}
