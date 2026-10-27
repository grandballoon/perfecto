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
        SpecScreen(name: "play-piano") {
            $0.piano.isOn = true
            showSeventh(in: $0)
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
        SpecScreen(name: "play-loops-deleting") { state in
            state.sequencerState.addLayers([progression, progression])
            state.quickLoopState.toggleDeleting()
        },
        SpecScreen(name: "play-loop-lengths") { $0.quickLoopState.triggerTapped() },
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

    /// A major seventh held, on the grid of keys.
    private static func showSeventh(in state: PerformanceState) {
        if state.chordGridLayout == .circle { state.chordGridLayout = .grid }
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.I))
    }
}
