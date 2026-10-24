@testable import Perfecto

/// One drawing of the UI spec: a screen of the app in a state worth showing.
/// `SpecScreen.screens` and `SpecScreen.menuPages` are the spec's contents;
/// a screen or state the spec should show is one more entry there.
@MainActor
struct SpecScreen {
    /// The drawing's file name.
    let name: String
    /// The menu page that is open, if the menu is.
    var menu: SidePanelPage? = nil
    /// Puts the app in the state drawn.
    var arrange: @MainActor (PerformanceState) -> Void = { _ in }
}

extension SpecScreen {
    /// The app's screens, each drawn as the phone shows it, upright and on
    /// its side.
    static let screens: [SpecScreen] = [
        SpecScreen(name: "play-circle"),
        SpecScreen(name: "play-grid") { $0.chordGridLayout = .grid },
        SpecScreen(name: "play-bar") { $0.chordGridLayout = .horizontalBar },
        SpecScreen(name: "play-octave") { $0.chordGridLayout = .octave },
        SpecScreen(name: "play-compass-held") { state in
            state.compassPressed(CompassPlace(.add, 1))
            state.press(.degree(.V))
        },
        SpecScreen(name: "play-compass-kept") { state in
            state.keepsCompassColor = true
            state.compassPressed(CompassPlace(.add, 1))
            state.compassPressed(CompassPlace(.raise, 1))
            state.press(.degree(.ii))
        },
        SpecScreen(name: "play-chord-held") { $0.press(.degree(.V)) },
        SpecScreen(name: "play-key-zones") {
            $0.effects.zones.count = 3
            $0.effects.zones.isOn = true
        },
        SpecScreen(name: "play-effects-arpeggio") { $0.effects.setSlot(0, to: .arpeggio(.up)) },
        SpecScreen(name: "play-effects-all") { state in
            for choice in [EffectChoice.arpeggio(.down), .chorus, .reverb, .vocoder] {
                state.effects.asSet.switchOn(choice)
            }
        },
        SpecScreen(name: "play-solo-under") { showSolo(in: $0, .underKeys) },
        SpecScreen(name: "play-solo-beside") { showSolo(in: $0, .besideKeys) },
        SpecScreen(name: "play-solo-colors") { showSolo(in: $0, .colors) },
        SpecScreen(name: "play-solo-under-bar") {
            $0.chordGridLayout = .horizontalBar
            showSolo(in: $0, .underKeys)
        },
        SpecScreen(name: "play-solo-colors-bar") {
            $0.chordGridLayout = .horizontalBar
            showSolo(in: $0, .colors)
        },
        SpecScreen(name: "play-piano") {
            $0.piano.isOn = true
            showSolo(in: $0, .besideKeys)
        },
        SpecScreen(name: "piano-expanded") {
            $0.piano.isOn = true
            $0.piano.isExpanded = true
            // Two octaves from C3.
            $0.piano.span = PianoSpan(start: Double(PianoKeys.whitesBelow(48)), count: 15)
        },
        SpecScreen(name: "play-loops") { state in
            let sequencer = state.sequencerState
            sequencer.addLayers([progression, progression, progression])
            sequencer.setLayer(sequencer.layers[1].id, muted: true)
        },
        SpecScreen(name: "sequencer-pages") { showSequence(in: $0, layout: .paged) },
        SpecScreen(name: "sequencer-scroll") { showSequence(in: $0, layout: .scroll) },
        SpecScreen(name: "sequencer-keys-grid") {
            $0.chordGridLayout = .grid
            showSequence(in: $0, layout: .paged)
        },
        SpecScreen(name: "sequencer-keys-bar") {
            $0.chordGridLayout = .horizontalBar
            showSequence(in: $0, layout: .paged)
        },
        SpecScreen(name: "tonnetz-net") { $0.show(.tonnetz) },
        SpecScreen(name: "tonnetz-triad") {
            $0.show(.tonnetz)
            $0.tonnetz.view = .triad
        },
        // A triad held, with a note outside it and one of its own held over it.
        SpecScreen(name: "tonnetz-net-held") {
            $0.show(.tonnetz)
            $0.tonnetz.holds = true
            $0.tonnetz.pointerDown(on: .cell(.home))
            $0.tonnetz.pointerUp()
            for note in [PitchClass.B, .E] {
                $0.tonnetz.pointerDown(on: .note(note))
                $0.tonnetz.pointerUp()
            }
        },
        // Some pads with sounds, two held, and the sequence at its first pad.
        SpecScreen(name: "pads") {
            showPads(in: $0)
            $0.pads.isRunning = true
            $0.pads.press(PadPlace(row: 1, column: 1))
            $0.pads.press(PadPlace(row: 2, column: 3))
        },
        SpecScreen(name: "pads-editing") {
            showPads(in: $0)
            $0.pads.isEditing = true
            $0.pads.select(PadPlace(row: 1, column: 1))
        },
        SpecScreen(name: "pads-eight-by-six") {
            $0.pads.setRows(8)
            $0.pads.setColumns(6)
            showPads(in: $0)
        },
        SpecScreen(name: "trautonium") { $0.show(.trautonium) },
        // Both bars sounding, the low one softly and off its note.
        SpecScreen(name: "trautonium-played") {
            $0.show(.trautonium)
            $0.trautonium.press(.low, at: BarPlace(along: 0.3, across: 0.35))
            $0.trautonium.move(.low, to: BarPlace(along: 0.33, across: 0.35))
            $0.trautonium.press(.high, at: BarPlace(along: 0.62, across: 0.9))
        },
        SpecScreen(name: "tree") { $0.show(.tree) },
        // A way through the tree, and a chord on from it held: a tier on from it.
        SpecScreen(name: "tree-played") { state in
            state.show(.tree)
            for label in ["Am", "Dm"] {
                let spot = state.tree.spots(on: state.tree.tier).next.joined().first { $0.chord.label == label }!
                state.tree.press(spot)
                state.tree.release(spot)
            }
            state.tree.press(state.tree.spots(on: state.tree.tier).next[3][0])
        },
        SpecScreen(name: "tree-sevenths") {
            $0.show(.tree)
            $0.tree.size = .sevenths
        },
        SpecScreen(name: "lab") { $0.show(.lab) },
        // A fifth held at the first level: spotlit, beatless in just
        // intonation, over its root.
        SpecScreen(name: "lab-fifth") {
            $0.show(.lab)
            $0.lab.pressPad(.perfectFifth)
        },
        // A minor second at the third level: the fundamentals beating.
        SpecScreen(name: "lab-second") {
            $0.show(.lab)
            $0.lab.choose(.three)
            $0.lab.pressPad(.minorSecond)
        },
    ] + SidePanelPage.allCases.map { SpecScreen(name: "menu-\($0.rawValue)", menu: $0) }

    /// The menu's pages at their whole length, which the phone only shows a
    /// screen of at a time, with every effect on so that every control shows.
    static let menuPages: [SpecScreen] = SidePanelPage.allCases.map { page in
        SpecScreen(name: "menu-\(page.rawValue)-whole", menu: page) { state in
            let effects = state.effects
            effects.arpeggiator.isOn = true
            effects.chorus.isOn = true
            effects.reverb.isOn = true
            effects.vocoder.isOn = true
            effects.zones.isOn = true
        }
    }

    // MARK: – States

    /// A chord on each beat of the first bar.
    private static let progression: [TimelineNote] = [Degree.I, .vi, .IV, .V].enumerated().map { beat, degree in
        TimelineNote(start: beat * TimelineTime.ticksPerBeat, length: TimelineTime.ticksPerBeat / 2,
                     chord: ChordSpec(degree: degree, color: .base))
    }

    /// The solo strip at `placement` beside the grid of keys (the row of
    /// them, where the layout asks for it), with a major seventh held and a
    /// note of the strip sounding over it.
    private static func showSolo(in state: PerformanceState, _ placement: SoloPlacement) {
        if state.chordGridLayout == .circle { state.chordGridLayout = .grid }
        state.solo.placement = placement
        state.solo.isOn = true
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.I))
        state.solo.press(cell: 7)
    }

    /// The pads on screen, a chord on each pad of the first two rows and
    /// one in another key and sound further down.
    private static func showPads(in state: PerformanceState) {
        state.show(.pads)
        for (index, degree) in (Degree.allCases + [.I]).enumerated() {
            state.pads.select(PadPlace(row: index / 4, column: index % 4))
            state.pads.edit { $0.chord = ChordSpec(degree: degree, color: .base) }
        }
        state.pads.select(PadPlace(row: 2, column: 3))
        state.pads.edit {
            $0.key = Key(root: .A, scale: .naturalMinor)
            $0.preset = .strings
        }
        state.pads.select(PadPlace(row: 0, column: 0))
    }

    /// The sequencer with two bars and two layers: chords entered on steps,
    /// one of them held across several, and a step selected.
    private static func showSequence(in state: PerformanceState, layout: SequencerLayout) {
        let sequencer = state.sequencerState
        state.selectMode(.sequencer)
        sequencer.layout = layout
        sequencer.addBar()
        sequencer.addLayers([progression])
        sequencer.addLayer()
        for (step, degree) in [(0, Degree.ii), (6, .V), (7, .V), (8, .V), (12, .I)] {
            sequencer.selectedSteps = [step]
            sequencer.primaryStep = step
            sequencer.editSelectedChords { ChordSpec(degree: degree, color: $0.color) }
        }
        sequencer.selectedSteps = [6, 7, 8]
        sequencer.primaryStep = 6
        sequencer.joinSelected()
        sequencer.focusedBar = 0
    }
}
