import SwiftUI

/// The chord keys as a choice of one degree: the keys Play mode shows
/// (`ChordKeysView`, in the same arrangement), driven by a selection instead
/// of the live performance. The octave's keys choose the degree each is the
/// root of, so there only the notes of the key are keys.
///
/// Used by the Sequencer step editor to pick a step's scale degree. It owns
/// no persistent state: the caller decides what
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
        ChordKeysView(arrangement: arrangement, key: key, lit: selected.map { [.degree($0)] } ?? [],
                      degreesOnly: true)
            .overlayPreferenceValue(ChordKeyFrames.self) { anchors in
                GeometryReader { proxy in
                    let shapes = anchors.mapValues { $0.shape(in: proxy) }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    guard let degree = Self.nearest(to: value.location, in: shapes)?
                                            .degree(in: key),
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

    /// The key closest to `point`; nil only with no keys.
    static func nearest<PlayedKey: Hashable>(to point: CGPoint, in shapes: [PlayedKey: KeyShape]) -> PlayedKey? {
        shapes.min { $0.value.distance(from: point) < $1.value.distance(from: point) }?.key
    }
}
