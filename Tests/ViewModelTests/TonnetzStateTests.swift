import CoreGraphics
import Testing
@testable import Perfecto

@Suite("TonnetzState")
@MainActor
struct TonnetzStateTests {

    // MARK: – Helpers

    /// A performance in octave 4 whose Tonnetz sounds through a sink of its own.
    private func makeState() -> (state: PerformanceState, keys: RecordingSink, tonnetz: RecordingSink) {
        let keys = RecordingSink(), tonnetz = RecordingSink()
        let state = PerformanceState(sink: keys, tonnetzSink: tonnetz, clock: ManualClock())
        return (state, keys, tonnetz)
    }

    private func cell(_ fifths: Int, _ thirds: Int, up: Bool) -> TonnetzCell {
        TonnetzCell(corner: TonnetzPoint(fifths: fifths, thirds: thirds), pointsUp: up)
    }

    /// A performance in octave 4 whose Tonnetz sounds its triads and its
    /// notes through sinks of their own, with the clock and a sequencer that
    /// saves nowhere the next test can see.
    @MainActor
    private final class Rig {
        let triads = RecordingSink()
        let notes = RecordingSink()
        /// What the timeline's layers sound, as notes.
        let layers = RecordingNoteSink()
        let clock = ManualClock()
        let logger = RecordingLogger()
        let sequencer = SequencerState(defaults: isolatedDefaults())
        let state: PerformanceState

        init() {
            let clock = clock, layers = layers
            state = PerformanceState(sink: RecordingSink(),
                                     layerSink: { NotePlayer([layers], clock: clock) },
                                     tonnetzSink: triads, tonnetzNoteSink: notes,
                                     sequencer: sequencer, clock: clock, logger: logger)
        }

        var tonnetz: TonnetzState { state.tonnetz }
        var loops: QuickLoopState { state.quickLoopState }
        var timeline: Timeline { sequencer.timeline }

        /// Presses `target` for `beats`, then lifts.
        func play(_ target: TonnetzTarget, beats: Double) {
            tonnetz.pointerDown(on: target)
            clock.advance(beats: beats)
            tonnetz.pointerUp()
        }
    }

    // MARK: – On a phone's screen

    @Test func theTonnetzTakesAPhonesScreenOverTheModeThatIsOn() {
        let (state, _, _) = makeState()
        state.show(.sequencer)
        #expect(state.phoneScreen == .sequencer)
        #expect(!state.tonnetz.isShown)

        state.show(.tonnetz)

        #expect(state.phoneScreen == .tonnetz)
        #expect(state.tonnetz.isShown)
        #expect(state.mode.kind == .sequencer)
    }

    @Test func theScreenGivenBackToTheKeysSilencesTheTonnetz() {
        let (state, _, sink) = makeState()
        state.show(.sequencer)
        state.show(.tonnetz)
        state.tonnetz.press(.home)

        state.show(.play)

        #expect(state.phoneScreen == .play)
        #expect(state.mode.kind == .play)
        #expect(!state.tonnetz.isSounding)
        #expect(sink.stopCount == 1)
    }

    @Test func theDesksTonnetzStaysOnAPhonesScreen() {
        let (state, _, _) = makeState()
        state.deskPane = .tonnetz
        #expect(state.phoneScreen == .tonnetz)
    }

    // MARK: – Playing

    @Test func aTrianglePressedSoundsItsTriadBesideTheKeys() {
        let (state, keys, sink) = makeState()

        state.tonnetz.press(.home)

        #expect(sink.playCalls == [Voicing(notes: [60, 64, 67])])
        #expect(state.tonnetz.isSounding)
        #expect(keys.calls.isEmpty)
        // A triad is in no key of the performance's: it is its own tonic.
        let context = sink.playEvents.first?.context
        #expect(context?.key == Key(root: .C, scale: .major))
        #expect(context?.spec == ChordSpec(degree: .I, color: .base))
    }

    @Test func aMinorTriadIsTheTonicOfItsMinorKey() {
        let (state, _, sink) = makeState()
        state.tonnetz.press(cell(0, 0, up: false))   // E minor
        #expect(sink.playCalls == [Voicing(notes: [64, 67, 71])])
        #expect(sink.playEvents.first?.context.key == Key(root: .E, scale: .naturalMinor))
    }

    @Test func theTriadsAreBuiltInTheOctaveSet() {
        let (state, _, sink) = makeState()
        state.octave = 3
        state.tonnetz.press(.home)
        #expect(sink.playCalls == [Voicing(notes: [48, 52, 55])])
    }

    /// Each move keeps two notes where they are and moves the third by a step.
    @Test(arguments: [
        (TonnetzMove.parallel, "Cm", [60, 63, 67]),
        (TonnetzMove.relative, "Am", [60, 64, 69]),
        (TonnetzMove.leading, "Em", [59, 64, 67]),
    ])
    func aMoveIsHeardAsTheOneNoteThatChanges(_ move: TonnetzMove, name: String, notes: [Int]) {
        let (state, _, sink) = makeState()
        state.tonnetz.press(.home)
        sink.reset()

        state.tonnetz.apply(move)

        #expect(state.tonnetz.cell == TonnetzCell.home.flipped(move))
        #expect(state.tonnetz.cell.triad.name == name)
        // The new triad replaces the old; nothing is stopped in between.
        #expect(sink.calls.count == 1)
        #expect(sink.playCalls == [Voicing(notes: notes)])
    }

    @Test func aMoveMadeTwiceComesBackToTheSameNotes() {
        let (state, _, sink) = makeState()
        state.tonnetz.press(.home)
        for move in TonnetzMove.allCases {
            state.tonnetz.apply(move)
            state.tonnetz.apply(move)
            #expect(state.tonnetz.cell == .home)
            #expect(sink.lastPlay == Voicing(notes: [60, 64, 67]))
        }
    }

    @Test func liftingEndsTheTriadAndLeavesTheTonnetzWhereItIs() {
        let (state, _, sink) = makeState()
        state.tonnetz.apply(.relative)
        sink.reset()

        state.tonnetz.release()
        state.tonnetz.release()

        #expect(sink.calls == [.stop])
        #expect(!state.tonnetz.isSounding)
        #expect(state.tonnetz.cell.triad == Triad(root: .A, quality: .minor))
    }

    @Test func aTriadTakesTheKeysPresetAndTheEffectsAsSet() {
        let notes = RecordingNoteSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: RecordingSink(), tonnetzSink: NotePlayer([notes], clock: clock),
                                     clock: clock)
        state.effects.reverb.isOn = true

        state.tonnetz.press(.home)

        #expect(Set(notes.started) == [60, 64, 67])
        // The middle note of the three, which the player leaves in the middle.
        #expect(notes.sounds.dropFirst().first
                == NoteSound(preset: state.synthPreset, effects: state.effects.asSet))
    }

    // MARK: – Notes by themselves

    @Test func aNotePressedSoundsByItselfOverTheTriad() {
        let rig = Rig()
        rig.tonnetz.press(.home)

        rig.tonnetz.pointerDown(on: .note(.B))

        #expect(rig.notes.playCalls == [Voicing(notes: [71])])
        #expect(rig.tonnetz.sounds(.B))
        #expect(rig.tonnetz.soundingNotes == [.B])
        // The triad is neither struck again nor ended, and is where it was.
        #expect(rig.triads.calls.count == 1)
        #expect(rig.tonnetz.cell == .home)

        rig.tonnetz.pointerUp()

        #expect(rig.notes.calls.last == .stop)
        #expect(!rig.tonnetz.sounds(.B))
        #expect(rig.tonnetz.isSounding)
        #expect(rig.triads.stopCount == 0)
    }

    @Test func aNoteIsInTheOctaveSet() {
        let rig = Rig()
        rig.state.octave = 2
        rig.tonnetz.pointerDown(on: .note(.D))
        #expect(rig.notes.playCalls == [Voicing(notes: [38])])
    }

    /// The next note starts before the last ends, and what is sent is tied,
    /// so nothing is struck twice and there is no gap.
    @Test func slidingFromNoteToNotePlaysARun() {
        let rig = Rig()
        rig.tonnetz.pointerDown(on: .note(.C))
        rig.tonnetz.pointerMoved(to: .note(.C))
        rig.tonnetz.pointerMoved(to: .cell(.home))      // between two notes
        rig.tonnetz.pointerMoved(to: .note(.G))

        #expect(rig.notes.playCalls == [[60], [60, 67], [67]].map { Voicing(notes: $0) })
        #expect(rig.notes.playEvents.allSatisfy { $0.articulation == .tied })
        #expect(rig.notes.stopCount == 0)
        #expect(rig.triads.calls.isEmpty)

        rig.tonnetz.pointerUp()
        #expect(rig.notes.stopCount == 1)
        #expect(rig.tonnetz.notes.isEmpty)
    }

    /// A pointer that came down on a triangle plays triangles: it passes
    /// over the notes at their corners, and a slide across a side is a move.
    @Test func aPointerOnATrianglePassesOverTheNotes() {
        let rig = Rig()
        rig.tonnetz.pointerDown(on: .cell(.home))
        rig.tonnetz.pointerMoved(to: .note(.E))
        rig.tonnetz.pointerMoved(to: .cell(TonnetzCell.home.flipped(.leading)))

        #expect(rig.triads.playCalls == [[60, 64, 67], [59, 64, 67]].map { Voicing(notes: $0) })
        #expect(rig.notes.calls.isEmpty)
        #expect(rig.logger.events.contains {
            if case .tonnetz_moved(move: "L", to: "Em") = $0 { true } else { false }
        })

        rig.tonnetz.pointerUp()
        #expect(!rig.tonnetz.isSounding)
    }

    // MARK: – Holding

    @Test func aTriangleHeldStaysOnUntilItIsPressedAgain() {
        let rig = Rig()
        rig.tonnetz.holds = true
        rig.tonnetz.pointerDown(on: .cell(.home))
        rig.tonnetz.pointerUp()
        #expect(rig.tonnetz.isSounding)
        #expect(rig.triads.stopCount == 0)

        // Another triangle takes its place.
        rig.tonnetz.pointerDown(on: .cell(cell(1, 0, up: true)))
        rig.tonnetz.pointerUp()
        #expect(rig.tonnetz.cell.triad == Triad(root: .G, quality: .major))
        #expect(rig.tonnetz.isSounding)

        rig.tonnetz.pointerDown(on: .cell(cell(1, 0, up: true)))
        rig.tonnetz.pointerUp()
        #expect(!rig.tonnetz.isSounding)
        #expect(rig.triads.calls.last == .stop)
    }

    /// Notes that make no triangle: each stays on until it is pressed again.
    @Test func notesHeldAddUpAndEachIsPressedAgainToEndIt() {
        let rig = Rig()
        rig.tonnetz.holds = true
        for note in [PitchClass.C, .G, .D] {
            rig.tonnetz.pointerDown(on: .note(note))
            rig.tonnetz.pointerUp()
        }
        #expect(rig.tonnetz.soundingNotes == [.C, .G, .D])
        #expect(rig.notes.lastPlay == Voicing(notes: [60, 62, 67]))
        #expect(rig.notes.stopCount == 0)

        rig.tonnetz.pointerDown(on: .note(.G))
        rig.tonnetz.pointerUp()
        #expect(rig.notes.lastPlay == Voicing(notes: [60, 62]))
        #expect(!rig.tonnetz.sounds(.G))
    }

    @Test func aTriadAndNotesAreHeldTogether() {
        let rig = Rig()
        rig.tonnetz.holds = true
        rig.tonnetz.pointerDown(on: .cell(.home))
        rig.tonnetz.pointerUp()
        rig.tonnetz.pointerDown(on: .note(.B))
        rig.tonnetz.pointerUp()

        #expect(rig.tonnetz.isSounding)
        #expect(rig.tonnetz.sounds(.B))
        #expect(rig.triads.calls.count == 1)
    }

    @Test func switchingHoldOffEndsWhatWasLeftOn() {
        let rig = Rig()
        rig.tonnetz.holds = true
        rig.tonnetz.pointerDown(on: .cell(.home))
        rig.tonnetz.pointerUp()
        rig.tonnetz.pointerDown(on: .note(.B))
        rig.tonnetz.pointerUp()

        rig.tonnetz.holds = false

        #expect(!rig.tonnetz.isSounding)
        #expect(rig.tonnetz.notes.isEmpty)
        #expect(rig.triads.calls.last == .stop)
        #expect(rig.notes.calls.last == .stop)
    }

    @Test func theTonnetzOffScreenIsSilentWhateverItHeld() {
        let rig = Rig()
        rig.state.deskPane = .tonnetz
        rig.tonnetz.holds = true
        rig.tonnetz.pointerDown(on: .cell(.home))
        rig.tonnetz.pointerUp()
        rig.tonnetz.pointerDown(on: .note(.B))
        rig.tonnetz.pointerUp()

        rig.state.deskPane = .sequencer

        #expect(!rig.tonnetz.isSounding)
        #expect(rig.tonnetz.notes.isEmpty)
    }

    /// A move's key lets go of nothing while the Tonnetz holds.
    @Test func aTriadHeldOutlastsThePressThatMadeIt() {
        let rig = Rig()
        rig.tonnetz.holds = true
        rig.tonnetz.apply(.relative)
        rig.tonnetz.release()
        #expect(rig.tonnetz.isSounding)
    }

    // MARK: – Loops

    /// The LOOP button records the Tonnetz as it does the keys: the triads
    /// are one layer and the notes played by themselves another, each as
    /// the notes that were heard.
    @Test func aLoopKeepsTheTriadsAndTheNotesAsLayersOfTheirOwn() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.play(.cell(.home), beats: 1)
        rig.play(.cell(TonnetzCell.home.flipped(.relative)), beats: 1)
        rig.play(.note(.B), beats: 2)
        rig.loops.triggerTapped()

        #expect(rig.loops.loops.count == 2)
        #expect(rig.timeline.barCount == 1)
        let triads = rig.timeline.layers[0].notes, notes = rig.timeline.layers[1].notes
        #expect(triads.map(\.start) == [0, 480])
        #expect(triads.map(\.length) == [480, 480])
        #expect(triads.map(\.pitch) == [.notes([60, 64, 67]), .notes([60, 64, 69])])
        // Each triad is the tonic of its own key, which is what it is shown as.
        #expect(triads.map(\.playing.key) == [Key(root: .C, scale: .major), Key(root: .A, scale: .naturalMinor)])
        #expect(notes.map(\.start) == [960])
        #expect(notes.map(\.length) == [960])
        #expect(notes.map(\.pitch) == [.notes([71])])
    }

    /// Played back, a loop of the Tonnetz is the notes that were heard:
    /// the triads voiced as they were, and a note held while others came
    /// and went is not struck again.
    @Test func aLoopOfHeldNotesPlaysBackWithoutStrikingThemAgain() {
        let rig = Rig()
        rig.tonnetz.holds = true
        rig.loops.triggerTapped()
        rig.tonnetz.pointerDown(on: .note(.C))
        rig.tonnetz.pointerUp()
        rig.clock.advance(beats: 1)
        rig.tonnetz.pointerDown(on: .note(.G))
        rig.tonnetz.pointerUp()
        rig.clock.advance(beats: 1)
        rig.tonnetz.pointerDown(on: .note(.C))       // lets C go
        rig.tonnetz.pointerUp()
        rig.clock.advance(beats: 2)
        rig.loops.triggerTapped()
        rig.tonnetz.holds = false

        let notes = rig.timeline.layers[0].notes
        #expect(notes.map(\.pitch) == [.notes([60]), .notes([60, 67]), .notes([67])])
        #expect(notes.map(\.start) == [0, 480, 960])
        #expect(notes.allSatisfy { $0.articulation == .tied })

        // The loop started as it was closed.
        #expect(rig.layers.sounding == [60])
        rig.clock.advance(beats: 1)
        #expect(rig.layers.sounding == [60, 67])
        rig.clock.advance(beats: 1)
        #expect(rig.layers.sounding == [67])
        #expect(rig.layers.started == [60, 67])
    }

    /// The Tonnetz is never arpeggiated, so its loop is not either, whatever
    /// is set for the keys.
    @Test func aLoopOfTheTonnetzKeepsItsSoundAndIsNotArpeggiated() {
        let rig = Rig()
        rig.state.effects.arpeggiator.isOn = true
        rig.state.effects.reverb.isOn = true
        rig.loops.triggerTapped()
        rig.play(.cell(.home), beats: 4)
        rig.loops.triggerTapped()

        let playing = rig.timeline.layers[0].notes[0].playing
        #expect(playing.preset == rig.state.synthPreset)
        #expect(playing.octave == 4)
        #expect(playing.effects?.reverb.isOn == true)
        #expect(playing.effects?.arpeggiator.isOn == false)
    }

    @Test func theKeysAndTheTonnetzPlayedInOneTakeAreALayerEach() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.state.press(degree: .V)
        rig.play(.cell(.home), beats: 4)
        rig.state.release(degree: .V)
        rig.loops.triggerTapped()

        #expect(rig.timeline.layers.map { $0.notes.map(\.pitch) } == [[.chord], [.notes([60, 64, 67])]])
    }

    /// A later take is folded onto the loop where it was played, as the keys' is.
    @Test func aTonnetzTakeIsLayeredOverALoop() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.play(.cell(.home), beats: 4)
        rig.loops.triggerTapped()

        rig.loops.triggerTapped()
        rig.clock.advance(beats: 1)
        rig.play(.note(.E), beats: 1)
        rig.loops.triggerTapped()

        #expect(rig.loops.loops.count == 2)
        #expect(rig.timeline.layers[1].notes.map(\.start) == [480])
        #expect(rig.timeline.layers[1].notes.map(\.pitch) == [.notes([64])])
    }

    @Test func notesAndTheHoldSwitchAreLogged() {
        let rig = Rig()
        rig.logger.reset()
        rig.tonnetz.holds = true
        rig.tonnetz.pointerDown(on: .note(.A))

        let logged = rig.logger.events.compactMap { event -> String? in
            switch event {
            case let .tonnetz_hold_switched(isOn): return "hold \(isOn)"
            case let .tonnetz_note_played(note):   return "note \(note)"
            default:                               return nil
            }
        }
        #expect(logged == ["hold true", "note 69"])
    }

    // MARK: – The views

    @Test func changingTheViewEndsTheTriadAndShowsTheNetAroundIt() {
        let (state, _, sink) = makeState()
        state.tonnetz.view = .triad
        state.tonnetz.apply(.leading)
        state.tonnetz.apply(.parallel)
        #expect(state.tonnetz.netCenter == .home)
        sink.reset()

        state.tonnetz.view = .net

        #expect(sink.calls == [.stop])
        #expect(state.tonnetz.netCenter == state.tonnetz.cell)
        #expect(state.tonnetz.cell.triad == Triad(root: .E, quality: .major))
    }

    @Test func aTrianglePressedOnTheNetLeavesTheNetWhereItIs() {
        let (state, _, _) = makeState()
        state.tonnetz.press(cell(3, -1, up: false))
        #expect(state.tonnetz.netCenter == .home)
    }

    @Test func theNetIsZoomedNoFurtherThanItsRange() {
        let (state, _, _) = makeState()
        state.tonnetz.zoomNet(to: 1000)
        #expect(state.tonnetz.netEdge == TonnetzState.netEdgeRange.upperBound)
        state.tonnetz.zoomNet(to: 0)
        #expect(state.tonnetz.netEdge == TonnetzState.netEdgeRange.lowerBound)
    }

    // MARK: – Logging

    @Test func movesAndTriadsAreLogged() {
        let logger = RecordingLogger()
        let state = PerformanceState(sink: RecordingSink(), tonnetzSink: RecordingSink(),
                                     clock: ManualClock(), logger: logger)
        logger.reset()

        state.tonnetz.apply(.relative)

        let logged = logger.events.compactMap { event -> String? in
            switch event {
            case let .tonnetz_moved(move, to):           return "\(move) to \(to)"
            case let .tonnetz_triad_played(triad, notes): return "\(triad) \(notes)"
            default:                                      return nil
            }
        }
        #expect(logged == ["R to Am", "Am [69, 72, 76]"])
    }
}
