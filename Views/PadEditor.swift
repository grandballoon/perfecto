import SwiftUI

/// The editor of the pad chosen (`PadsState.selected`): the chord keys, as
/// Play mode shows them, and the chord grid set its chord, and the row
/// above them gives it what is chosen for the keys now. A pad's key, octave
/// and effects are changed as a sequencer note's are: by choosing them for
/// the keys and giving them to the pad. Its sound is chosen from every
/// sound there is, since the pads' screen has no sound field to choose the
/// keys' from, and its effects are also set by themselves: FX opens the
/// menu's Effects page at them.
///
/// A pad with no sound gets one from the first chord chosen for it, in
/// everything the keys are set to. The pad sounds while a finger is on the
/// keys or the colors, so each choice is heard.
struct PadEditor: View {
    @Environment(PerformanceState.self) private var state
    @Environment(SidePanelState.self) private var sidePanel

    /// The chord grid's cell under the finger, lit only while it is there.
    @State private var gridTransient: GridPosition? = nil

    private static let keysHeight: CGFloat = 150
    /// The chord grid has a row per mode.
    private static let gridHeight: CGFloat = 196

    private var sound: PadSound? {
        state.pads.selected.flatMap { state.pads.grid[$0] }
    }

    var body: some View {
        VStack(spacing: 10) {
            actions
            // Both give up height where there is little (a phone on its side).
            degreeSelector
                .frame(minHeight: 80, maxHeight: Self.keysHeight)
            colorGrid
                .frame(maxHeight: Self.gridHeight)
        }
    }

    // MARK: – What the keys are set to

    private var actions: some View {
        HStack(spacing: 8) {
            button("TAKE KEYS", label: "Give the pad the chord the keys played last, and their key, octave, sound and effects") {
                state.pads.takeFromKeys()
            }
            takeMenu
            // Lit while the pad has an effect on.
            button("FX", enabled: sound != nil, isLit: sound?.effects.hasAnyOn == true,
                   label: "Set the pad's own effects") {
                sidePanel.showEffects(of: .pad)
            }
            Spacer(minLength: 0)
            button("CLEAR", enabled: sound != nil, label: "Leave the pad with no sound") {
                state.pads.clearSelected()
            }
        }
    }

    /// Gives the pad one of the things chosen for the keys now, or any
    /// sound, and says what it has of its own.
    private var takeMenu: some View {
        let pads = state.pads
        let (key, octave) = (state.key, state.octave)
        let effects = state.effects.asSet
        return Menu {
            Section("Key: \(sound.map { keyName($0.key) } ?? "none")") {
                Button("Set to \(keyName(key))") { pads.edit { $0.key = key } }
            }
            Section("Octave: \(sound.map { String($0.octave) } ?? "none")") {
                Button("Set to octave \(octave)") { pads.edit { $0.octave = octave } }
            }
            Section("Sound: \(sound?.preset.name ?? "none")") {
                Menu("Choose a sound") {
                    ForEach(SynthPreset.Category.allCases) { category in
                        Section(category.displayName) {
                            ForEach(category.presets) { preset in
                                Button { pads.edit { $0.preset = preset } } label: {
                                    if sound?.preset == preset {
                                        Label(preset.name, systemImage: "checkmark")
                                    } else {
                                        Text(preset.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("Effects") {
                Button("Set to the effects as set now") { pads.edit { $0.effects = effects } }
            }
        } label: {
            chit("SET…", enabled: true)
        }
        .accessibilityLabel("Give the pad the key, octave or effects chosen now, or any sound")
    }

    private func keyName(_ key: Key) -> String {
        "\(key.root.name) \(key.scale.displayName)"
    }

    private func button(_ title: String, enabled: Bool = true, isLit: Bool = false, label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) { chit(title, enabled: enabled, isLit: isLit) }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(label)
    }

    private func chit(_ title: String, enabled: Bool, isLit: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isLit ? Color.orange : enabled ? Color(white: 0.7) : Color(white: 0.3))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.12)))
    }

    // MARK: – The pad's chord

    /// The chord keys, in the layout Play mode shows them in, named in the
    /// pad's key. Nothing is lit for a pad with no sound.
    private var degreeSelector: some View {
        let pads = state.pads
        return DegreeSelector(
            arrangement: state.chordGridLayout.arrangement(isLandscape: false),
            key: sound?.key ?? state.key,
            selected: sound?.chord.degree,
            onChange: { degree in
                // As on the keys, a color held while the degree is chosen
                // is the chord's.
                pads.edit { $0.chord = ChordSpec(degree: degree, color: heldColor(for: degree, in: $0.key) ?? $0.chord.color) }
                pads.audition()
            },
            onEnd: { pads.endAudition() }
        )
    }

    /// The color a finger is holding on the chord grid now, if one is.
    private func heldColor(for degree: Degree, in key: Key) -> ChordColor? {
        gridTransient.map { ChordGrid.color(at: $0, key: key, degree: degree) }
    }

    /// The chord grid, here coloring the pad's chord (the compass is for
    /// playing).
    private var colorGrid: some View {
        let pads = state.pads
        return ChordGridPad(
            key: sound?.key ?? state.key,
            degree: sound?.chord.degree ?? .I,
            selected: gridTransient,
            onChange: { position in
                gridTransient = position
                pads.edit {
                    $0.chord = ChordSpec(degree: $0.chord.degree,
                                         color: ChordGrid.color(at: position, key: $0.key, degree: $0.chord.degree))
                }
                pads.audition()
            },
            onEnd: {
                gridTransient = nil
                pads.endAudition()
            }
        )
    }
}
