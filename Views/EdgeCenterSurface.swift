import SwiftUI

/// The edge layout's middle: the surface chosen to color the chord held
/// (`PerformanceState.centerSurface`). It is the one place the edge layout
/// asks which, so another surface is a `CenterSurface` case and a line here.
struct EdgeCenterSurface: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        switch state.centerSurface {
        case .compass: StepCompassSurface(hasCorners: true)
        case .table:   ColorTableSurface()
        case .tree:    ColorTreeSurface()
        }
    }
}
