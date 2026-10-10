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
        SpecScreen(name: "play-color-grid") { $0.colorSurface = .grid },
        SpecScreen(name: "play-chord-held") {
            $0.joystickMoved(to: .right)
            $0.press(degree: .V)
        },
        SpecScreen(name: "play-key-zones") {
            $0.effects.zones.count = 3
            $0.effects.zones.isOn = true
        },
        SpecScreen(name: "play-effect-slider-bar") { showEffectSlider(in: $0, shape: .bar) },
        SpecScreen(name: "play-effect-slider-grid") { showEffectSlider(in: $0, shape: .grid) },
        SpecScreen(name: "play-effect-slider-upright") {
            $0.chordGridLayout = .horizontalBar
            showEffectSlider(in: $0, shape: .bar)
        },
        SpecScreen(name: "play-effect-slider-empty") { $0.playSurface = .effects },
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
    ] + SidePanelPage.allCases.map { SpecScreen(name: "menu-\($0.rawValue)", menu: $0) }

    /// The menu's pages at their whole length, which the phone only shows a
    /// screen of at a time, with every effect on so that every control shows.
    static let menuPages: [SpecScreen] = SidePanelPage.allCases.map { page in
        SpecScreen(name: "menu-\(page.rawValue)-whole", menu: page) { state in
            let effects = state.effects
            effects.arpeggiator.isOn = true
            effects.filter.isOn = true
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

    /// The effect slider in place of the chord colors, with three effects
    /// on and a finger on the filter's lane.
    private static func showEffectSlider(in state: PerformanceState, shape: SurfaceShape) {
        state.playSurface = .effects
        state.effectSliderShape = shape
        state.effects.arpeggiator.isOn = true
        state.effects.filter.isOn = true
        state.effects.reverb.isOn = true
        state.effects.sliderMoved(.filter, to: 0.7)
    }

    /// The solo strip at `placement` beside the grid of keys (the row of
    /// them, where the layout asks for it), with a major seventh held and a
    /// note of the strip sounding over it.
    private static func showSolo(in state: PerformanceState, _ placement: SoloPlacement) {
        if state.chordGridLayout == .circle { state.chordGridLayout = .grid }
        state.solo.placement = placement
        state.solo.isOn = true
        state.joystickMoved(to: .right)
        state.press(degree: .I)
        state.solo.press(cell: 7)
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
