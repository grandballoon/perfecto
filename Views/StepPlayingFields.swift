import SwiftUI

/// The step editor's own key strip: the key and the voicing of the selected
/// notes, changed as the key strip changes the keys' (`SwipeField`,
/// `VoicingField`). A field shows the note the editor shows
/// (`SequencerState.primaryNote`): its own setting, marked ◆, or the one
/// chosen for the keys while it follows that. A change gives every selected
/// note the setting as its own (`NotePlaying`), counted from what the field
/// showed, and one finger's worth is one undo, as is a value chosen from
/// the key's list. Of the voicing, only what the finger changed becomes the
/// notes' own: the octave, the inversion, or both. Following again is in
/// the ◆ OWN menu. The scale of a note's key is the one it has, or the
/// keys'; only the root is swiped.
struct StepPlayingFields: View {
    @Environment(PerformanceState.self) private var perfState
    @Environment(SequencerState.self) private var seqState

    static let height: CGFloat = 34
    private static let roots = PitchClass.allCases
    private static let voicingWidth: CGFloat = 104

    /// Guards the undo snapshot so one swipe is one undo step.
    @State private var editActive = false

    var body: some View {
        let playing = seqState.primaryNote?.playing
        let key = playing?.key ?? perfState.key
        let octave = playing?.octave ?? perfState.octave
        let inversion = playing?.inversion ?? perfState.inversion
        return HStack(spacing: 8) {
            SwipeField(name: name("KEY", isOwn: playing?.key != nil),
                       value: key.root.rawValue, range: 0...(Self.roots.count - 1),
                       textSize: 12, wraps: true, onEnd: end,
                       label: { "\(Self.roots[$0].name) \(key.scale.displayName)" }) { root in
                edit { $0.key = Key(root: Self.roots[root], scale: key.scale) }
            }
            VoicingField(name: [name("OCT", isOwn: playing?.octave != nil),
                                name("INV", isOwn: playing?.inversion != nil)].joined(separator: " · "),
                         voicing: KeyVoicing(octave: octave, inversion: inversion), onEnd: end) { voicing in
                edit {
                    if voicing.octave != octave { $0.octave = voicing.octave }
                    if voicing.inversion != inversion { $0.inversion = voicing.inversion }
                }
            }
            .frame(width: Self.voicingWidth)
        }
        .frame(height: Self.height)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    /// There is a note to change, and its chord is built in a key: a note
    /// played from the net is its own notes whatever the key and octave.
    private var isEnabled: Bool {
        guard let primary = seqState.primaryNote else { return false }
        if case .notes = primary.pitch { return false }
        return true
    }

    private func name(_ name: String, isOwn: Bool) -> String {
        isOwn ? "◆ \(name)" : name
    }

    private func edit(_ change: (inout NotePlaying) -> Void) {
        if !editActive {
            seqState.snapshot()
            editActive = true
        }
        seqState.changeSelectedPlaying(change)
    }

    private func end() {
        editActive = false
    }
}
