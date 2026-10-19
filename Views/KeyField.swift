import SwiftUI

/// The key field: the key the keys are in, on the key strip, whose root is
/// changed by swiping along it (`SwipeField`): every step to the right is a
/// semitone up and to the left a semitone down, round the twelve notes, so
/// B is followed by C. It is the Key page's root, within reach while
/// playing, and the scale it shows is still set there.
struct KeyField: View {
    @Environment(PerformanceState.self) private var state

    /// The sound field's width: room for the longest key's name.
    static let width: CGFloat = SoundField.width
    private static let roots = PitchClass.allCases

    var body: some View {
        let scale = state.key.scale
        SwipeField(name: "KEY", value: state.key.root.rawValue,
                   range: 0...(Self.roots.count - 1), textSize: 12, wraps: true,
                   label: { "\(Self.roots[$0].name) \(scale.displayName)" }) {
            state.key = Key(root: Self.roots[$0], scale: state.key.scale)
        }
        .frame(width: Self.width)
    }
}
