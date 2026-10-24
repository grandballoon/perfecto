import SwiftUI

/// Play mode's input surface beside the chord keys: the step compass, or
/// the solo strip in its place, as a bar, while it is on and placed there
/// (`SoloPlacement.colors`). The screen is laid out by their shapes
/// (`SurfaceShape`).
struct PlaySurfaceView: View {

    /// Which way a bar runs. The compass ignores it.
    var barAxis: Axis = .horizontal

    @Environment(PerformanceState.self) private var state

    var body: some View {
        if state.solo.takesColorsPlace {
            SoloStripView(axis: barAxis)
        } else {
            StepCompassSurface()
        }
    }
}

extension SurfaceShape {
    /// A bar's short side, whichever way it runs.
    static let barThickness: CGFloat = 88

    /// Portrait height: a bar is one strip; the compass is five rows of
    /// places.
    var portraitHeight: CGFloat {
        switch self {
        case .bar:     return Self.barThickness
        case .compass: return 250
        }
    }
}
