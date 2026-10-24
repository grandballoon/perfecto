import SwiftUI

/// The menu's Setup page: how the chord keys, the chord colors beside them,
/// the solo strip and the sequencer's bars are laid out, whether the play
/// screen has the key strip, whether a finger's place on a chord key plays
/// its brightness, the size of the grid of pads, and whether the piano is
/// shown under them.
struct SetupPanel: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var state = state
        @Bindable var solo = state.solo
        @Bindable var sequencer = state.sequencerState
        VStack(alignment: .leading, spacing: 24) {
            chordLayoutSection

            keyStripSection

            keySlideSection

            choiceSection("SOLO STRIP",
                          detail: "Where the SOLO button puts the strip of notes that fit the chord, for runs over it: under the chord keys, which give up some of their height (drag the handle between them); upright beside them; or in the chord colors' place. On its side, a phone with room beside the keys puts the strip there.") {
                Picker("Place", selection: $solo.placement) {
                    ForEach(SoloPlacement.allCases, id: \.self) { placement in
                        Text(placement.displayName).tag(placement)
                    }
                }
            }

            choiceSection("COMPASS ORDER",
                          detail: "Which two of each kind of step the compass offers, near and far: up adds a tone, right raises one, left lowers one, down takes one away. Theory: in the key first, then the chord's own next tone (its 7th, then its 9th). Common: the chords played most first (7, maj7, min7, sus4, add9, 6), in the key or not.") {
                Picker("Order", selection: $state.compassRanking) {
                    ForEach(ColorStepRanking.allCases, id: \.self) { ranking in
                        Text(ranking.displayName).tag(ranking)
                    }
                }
            }
            compassNamesSection

            choiceSection("SEQUENCER BARS",
                          detail: "How the sequencer shows its bars: one at a time behind numbered tabs, or all of them in one scrolling column (there, one finger selects and two fingers scroll).") {
                Picker("Layout", selection: $sequencer.layout) {
                    ForEach(SequencerLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
            }

            padsSection

            pianoSection

            // Where there is a keyboard to play: the Mac.
            if ProcessInfo.processInfo.isMacCatalystApp { KeyboardMapEditor(keyboard: state.keyboard) }
            // While there is a controller to play.
            if let controller = state.gamepad.controller {
                KeyboardMapEditor(gamepad: state.gamepad, named: controller)
            }
        }
    }

    // MARK: – Chord layout

    private var chordLayoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("CHORD LAYOUT")
            VStack(spacing: 8) {
                ForEach(ChordGridLayout.allCases, id: \.self) { layout in
                    chordLayoutRow(layout)
                }
            }
        }
    }

    private func chordLayoutRow(_ layout: ChordGridLayout) -> some View {
        let selected = state.chordGridLayout == layout
        return Button {
            state.chordGridLayout = layout
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(layout.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? .black : .white)
                Text(layout.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(selected ? Color.black.opacity(0.65) : Color(white: 0.45))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.orange : Color(white: 0.15))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Key strip

    private var keyStripSection: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("KEY STRIP")
            Toggle(isOn: $state.showsKeyStrip) {
                Text("Show the key strip")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .tint(.orange)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("The key, the octave and the inversion on the play screen, so they can be changed while playing. A swipe to the right along the key is a semitone up, to the left a semitone down. The octave and the inversion are one field: while a finger is on it, moving along takes a chord's lowest note up an octave, or its highest note down one (a 9th, 11th or 13th stays on top), and moving up or down takes the whole chord up or down an octave. A chord that is being held follows the finger. With the pin beside it off, the field is played and not set: the chords go back to where they were when the finger lifts. The scale is on the Key page.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Compass names

    private var compassNamesSection: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("COMPASS NAMES")
            Toggle(isOn: $state.compassShowsChords) {
                Text("Name the compass's chords")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .tint(.orange)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("While a chord is held, each place on the compass is named by the chord it would play (G 7, G sus4). Off, the places keep their own names (plain, + tone, raise, lower, − tone) whatever chord is held, so the compass is played by where a place is and heard, not read. What sounds is the same either way.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Key slide

    private var keySlideSection: some View {
        @Bindable var effects = state.effects
        return VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("KEY SLIDE")
            Toggle(isOn: $effects.slidePlaysBrightness) {
                Text("Slide plays brightness")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .tint(.orange)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("Where a finger is on a chord key plays how bright its chord is: dark at the bottom of the key, and the whole sound at the top. Sliding while the chord is held sweeps it, and a loop keeps what was played.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $effects.slidePlaysInversion) {
                Text("Slide plays inversion")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .tint(.orange)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("Where a finger is on a chord key plays how its chord is voiced: as the key strip's inversion has it in the middle of the key, with the lowest note taken up an octave for each step above that, and the highest note down an octave for each step below. Sliding while the chord is held rolls it, striking only the note that moves.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Pads

    private var padsSection: some View {
        let pads = state.pads
        return VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("PADS")
            VStack(alignment: .leading, spacing: 14) {
                padsChoice("Rows", options: Array(PadGrid.sizes), label: \.description,
                           selection: Binding(get: { pads.grid.rows }, set: { pads.setRows($0) }))
                padsChoice("Columns", options: Array(PadGrid.sizes), label: \.description,
                           selection: Binding(get: { pads.grid.columns }, set: { pads.setColumns($0) }))
                padsChoice("Step of the sequence", options: PadRate.allCases, label: \.label,
                           selection: Binding(get: { pads.grid.rate }, set: { pads.setRate($0) }))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("The grid of pads on the PADS screen, each with a sound of its own. A pad keeps its place when the grid changes size, and one left outside a smaller grid comes back when the grid is made larger again. In sequence, the pads are played one to a step, along each row from the top, at the tempo; a pad with no sound is a rest.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func padsChoice<Option: Hashable>(_ name: String, options: [Option],
                                              label: KeyPath<Option, String>,
                                              selection: Binding<Option>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
            Picker(name, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: – Piano

    private var pianoSection: some View {
        @Bindable var piano = state.piano
        return VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("PIANO")
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $piano.isOn) {
                    Text("Show the piano")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .tint(.orange)
                if piano.isOn {
                    ForEach(PianoSource.allCases, id: \.self) { source in
                        Toggle(isOn: Binding(get: { piano.lit.contains(source) },
                                             set: { piano.light(source, $0) })) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(source.color)
                                    .frame(width: 12, height: 12)
                                Text(source.displayName)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.6))
                            }
                        }
                        .tint(.orange)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("A piano's 88 keys along the bottom of the screen, lit with the notes being sounded: each part of the app in its own color, and a key several are sounding in all of theirs. It is only looked at: pinch it to see fewer keys or more, drag it along, and double-tap it or use its corner button to give it the whole screen.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Choices

    private func choiceSection<Choice: View>(_ title: String,
                                             detail: String,
                                             @ViewBuilder picker: () -> Choice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel(title)
            picker()
                .pickerStyle(.segmented)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
