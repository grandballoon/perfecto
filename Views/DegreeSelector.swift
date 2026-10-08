import SwiftUI

/// The seven chord keys as a choice of one degree: the keys Play mode shows
/// (`ChordKeysView`, in the same arrangement), driven by a selection instead
/// of the live performance.
///
/// Used by the Sequencer step editor to pick a step's scale degree. Like
/// `ChordColorBar`, it owns no persistent state: the caller decides what
/// "selected" means and records undo. A drag slides the highlight between
/// degrees (a plain tap is included, since `minimumDistance` is 0). There is
/// nothing to play between the keys here, so a finger chooses the key it is
/// nearest wherever it is.
struct DegreeSelector: View {
    let arrangement: ChordKeyArrangement
    /// The key, which decides each degree's numeral (e.g. "ii" vs "ii°").
    let key: Key
    /// The highlighted degree, or `nil` when the step is a rest (nothing lit).
    let selected: Degree?
    /// Called as the finger crosses into a new degree.
    let onChange: (Degree) -> Void
    /// Called when the gesture ends (lets the caller close its undo group).
    var onEnd: (() -> Void)? = nil

    @State private var lastDegree: Degree? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ChordKeysView(arrangement: arrangement, key: key, lit: selected.map { [$0] } ?? [])
            .overlayPreferenceValue(ChordKeyFrames.self) { anchors in
                GeometryReader { proxy in
                    let frames = anchors.mapValues { proxy[$0] }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    guard let degree = Self.nearest(to: value.location, in: frames),
                                          degree != lastDegree else { return }
                                    lastDegree = degree
                                    haptic.impactOccurred()
                                    onChange(degree)
                                }
                                .onEnded { _ in
                                    lastDegree = nil
                                    onEnd?()
                                }
                        )
                }
            }
    }

    /// The degree whose key is closest to `point`; nil only with no keys.
    static func nearest(to point: CGPoint, in frames: [Degree: CGRect]) -> Degree? {
        frames.min { point.distance(to: $0.value) < point.distance(to: $1.value) }?.key
    }
}
