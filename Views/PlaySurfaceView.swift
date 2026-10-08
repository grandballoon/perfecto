import SwiftUI

/// Play mode's input surface beside the chord keys: the chord colors or the
/// effect slider, whichever Setup selects. Both come in the same two shapes
/// (`SurfaceShape`), so the screen is laid out by shape and does not care
/// which of them it is showing. The solo strip takes their place, as a bar,
/// while it is on and placed there (`SoloPlacement.colors`).
struct PlaySurfaceView: View {

    /// Which way a bar runs. A grid ignores it.
    var barAxis: Axis = .horizontal

    @Environment(PerformanceState.self) private var state

    var body: some View {
        if state.solo.takesColorsPlace {
            SoloStripView(axis: barAxis)
        } else {
            switch state.playSurface {
            case .color:
                ColorSurfaceView(barAxis: barAxis)
            case .effects:
                EffectSliderView(axis: state.effectSliderShape == .bar ? barAxis : .horizontal)
            }
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
