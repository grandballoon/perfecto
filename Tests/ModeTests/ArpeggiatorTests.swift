import Testing
@testable import Perfecto

/// The arpeggiator, played the way the app plays it: chord buttons and the
/// sequencer go in at `PerformanceState`, and the notes that reach the sink
/// are what would sound. C major at octave 4 throughout: I is 60 64 67 and
/// IV is 65 69 72. The cycle is one beat unless a test says otherwise.
@Suite("Arpeggiator")
@MainActor
struct ArpeggiatorTests {

    private func makeState(cycle: ArpeggioCycle = .beat,
                           pattern: ArpeggioPattern = .up,
                           isOn: Bool = true)
        -> (PerformanceState, RecordingSink, ManualClock) {
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.effects.arpeggiator = ArpeggiatorSettings(isOn: isOn, pattern: pattern, cycle: cycle)
        return (state, sink, clock)
    }

    private func notes(_ sink: RecordingSink) -> [[Int]] { sink.playCalls.map(\.notes) }

    /// A moment too short to matter musically, for looking just before a beat.
    private static let moment = 0.001

    // MARK: – Off

    @Test func whileOffChordsSoundWhole() {
        let (state, sink, clock) = makeState(isOn: false)
        state.press(degree: .I)
        clock.advance(beats: 4)
        #expect(notes(sink) == [[60, 64, 67]])
        #expect(clock.repeatCount == 0)
    }

    // MARK: – Timing

    @Test func theFirstNoteSoundsOnThePress() {
        let (state, sink, _) = makeState()
        state.press(degree: .I)
        #expect(notes(sink) == [[60]])
    }

    @Test func theNotesShareTheCycleEvenly() {
        let (state, sink, clock) = makeState()
        state.press(degree: .I)

        clock.advance(beats: 1.0 / 3 - Self.moment)
        #expect(notes(sink) == [[60]])
        clock.advance(beats: Self.moment)
        #expect(notes(sink) == [[60], [64]])
        clock.advance(beats: 1.0 / 3)
        #expect(notes(sink) == [[60], [64], [67]])
    }

    @Test(arguments: [(ArpeggioCycle.halfBeat, 0.5), (.beat, 1.0), (.twoBeats, 2.0), (.bar, 4.0)])
    func onePassTakesTheCycle(cycle: ArpeggioCycle, beats: Double) {
        let (state, sink, clock) = makeState(cycle: cycle)
        state.press(degree: .I)

        clock.advance(beats: beats - Self.moment)
        #expect(notes(sink) == [[60], [64], [67]])
        clock.advance(beats: Self.moment)
        #expect(notes(sink) == [[60], [64], [67], [60]])   // round again, on the beat
    }

    /// A coloration adds notes to the chord. The pass must still take one
    /// cycle: the notes come faster, and the pattern comes round on the beat.
    @Test func aChordWithMoreNotesTakesTheSameTime() {
        let (state, sink, clock) = makeState()
        state.joystickMoved(to: .right)             // I becomes Cmaj7: 60 64 67 71
        state.press(degree: .I)

        clock.advance(beats: 1 - Self.moment)
        #expect(notes(sink) == [[60], [64], [67], [71]])
        clock.advance(beats: Self.moment)
        #expect(notes(sink).last == [60])
        #expect(notes(sink).count == 5)
    }

    /// The same, with the coloration added while the chord is held.
    @Test func colouringAHeldChordKeepsThePassLength() {
        let (state, sink, clock) = makeState()
        state.press(degree: .I)
        clock.advance(beats: 2)
        sink.reset()

        state.joystickMoved(to: .right)             // starts again as Cmaj7
        clock.advance(beats: 1 - Self.moment)
        #expect(notes(sink) == [[60], [64], [67], [71]])
        clock.advance(beats: Self.moment)
        #expect(notes(sink).count == 5)
    }

    // MARK: – Patterns

    @Test(arguments: [
        (ArpeggioPattern.up,     [60, 64, 67, 60, 64, 67, 60]),
        (.down,                  [67, 64, 60, 67, 64, 60, 67]),
        (.upDown,                [60, 64, 67, 64, 60, 64, 67]),
    ])
    func thePatternSetsTheOrder(pattern: ArpeggioPattern, expected: [Int]) {
        let (state, sink, clock) = makeState(pattern: pattern)
        state.press(degree: .I)
        let notesPerBeat = pattern.pass(count: 3).count
        clock.advance(beats: Double(expected.count - 1) / Double(notesPerBeat))
        #expect(notes(sink) == expected.map { [$0] })
    }

    @Test func randomPlaysEveryNoteOnceEachPass() {
        let (state, sink, clock) = makeState(pattern: .random)
        state.press(degree: .I)
        clock.advance(beats: 3 - Self.moment)
        let played = notes(sink).map { $0[0] }
        #expect(played.count == 9)
        for pass in stride(from: 0, to: 9, by: 3) where played.count == 9 {
            #expect(played[pass..<pass + 3].sorted() == [60, 64, 67])
        }
    }

    @Test(arguments: ArpeggioPattern.allCases, 0...6)
    func aPassVisitsEveryNote(pattern: ArpeggioPattern, count: Int) {
        let pass = pattern.pass(count: count)
        #expect(Set(pass) == Set(0..<count))
    }

    // MARK: – Chords coming and going

    @Test func releasingEndsThePattern() {
        let (state, sink, clock) = makeState()
        state.press(degree: .I)
        state.release(degree: .I)
        #expect(sink.calls.last == .stop)
        #expect(clock.repeatCount == 0)
        sink.reset()
        clock.advance(beats: 2)
        #expect(sink.calls.isEmpty)
    }

    @Test func aNewChordStartsThePatternAgainAtOnce() {
        let (state, sink, clock) = makeState()
        state.press(degree: .I)
        clock.advance(beats: 1.0 / 3)               // 60, 64
        state.movePointer(from: .I, to: .IV)
        clock.advance(beats: 1.0 / 3)
        #expect(notes(sink) == [[60], [64], [65], [69]])
        #expect(clock.repeatCount == 1)
    }

    @Test func everyNoteCarriesItsChordsContext() {
        let (state, sink, clock) = makeState()
        state.press(degree: .IV)
        clock.advance(beats: 1 - Self.moment)
        #expect(sink.playEvents.count == 3)
        #expect(sink.playEvents.allSatisfy { $0.context.spec.degree == .IV && $0.articulation == .block })
    }

    @Test func switchingItOnOrOffReSoundsTheHeldChord() {
        let (state, sink, clock) = makeState(isOn: false)
        state.press(degree: .I)
        state.effects.arpeggiator.isOn = true
        clock.advance(beats: 1.0 / 3)
        state.effects.arpeggiator.isOn = false
        clock.advance(beats: 2)
        #expect(notes(sink) == [[60, 64, 67], [60], [64], [60, 64, 67]])
        #expect(clock.repeatCount == 0)
    }

    /// A new cycle changes the speed without starting the pattern again:
    /// the note that was due comes when it was due, and the rest follow at
    /// the new spacing.
    @Test func changingTheCycleChangesTheSpeedFromTheNextNote() {
        let (state, sink, clock) = makeState()
        state.press(degree: .I)
        state.effects.arpeggiator.cycle = .bar
        #expect(notes(sink) == [[60]])

        clock.advance(beats: 1.0 / 3)
        #expect(notes(sink) == [[60], [64]])
        clock.advance(beats: 4.0 / 3 - Self.moment)
        #expect(notes(sink) == [[60], [64]])
        clock.advance(beats: Self.moment)
        #expect(notes(sink) == [[60], [64], [67]])
    }

    // MARK: – Played by the slide

    /// The slide sets the speed a chord starts at, and changes it while the
    /// chord is held; lifting returns to the set cycle.
    @Test func theSlidePlaysTheCycle() {
        let (state, sink, clock) = makeState()
        state.effects.arpeggiator.followsSlide = true

        state.slide(on: .I, to: 0)                 // the bottom of the key: a bar per pass
        state.movePointer(from: nil, to: .I)
        clock.advance(beats: 4.0 / 3)
        #expect(notes(sink) == [[60], [64]])

        state.slide(on: .I, to: 1)                 // the top: half a beat per pass
        clock.advance(beats: 4.0 / 3)              // the note already due, at the old speed
        #expect(notes(sink) == [[60], [64], [67]])
        clock.advance(beats: 0.5)
        #expect(notes(sink) == [[60], [64], [67], [60], [64], [67]])

        state.movePointer(from: .I, to: nil)
        state.press(degree: .I)
        sink.reset()
        clock.advance(beats: 1)
        #expect(notes(sink) == [[64], [67], [60]])
    }

    /// A finger wavering across the line between two speeds must not hold
    /// the notes up: each note still comes when it was due.
    @Test func aWaveringSlideNeverStallsTheNotes() {
        let (state, sink, clock) = makeState()
        state.effects.arpeggiator.followsSlide = true
        state.slide(on: .I, to: 0.6)               // a beat per pass
        state.movePointer(from: nil, to: .I)

        for step in 0..<20 {
            state.slide(on: .I, to: step.isMultiple(of: 2) ? 0.4 : 0.6)
            clock.advance(beats: 0.01)
        }
        clock.advance(beats: 1.0 / 3 - 0.2)
        #expect(notes(sink) == [[60], [64]])
    }

    // MARK: – Played by key zones

    /// Where a key is struck chooses the speed: each zone holds its own cycle.
    @Test func eachZonePlaysItsOwnCycle() {
        let (state, sink, clock) = makeState(isOn: false)
        state.effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(),
            KeyZone(effect: .arpeggiator, value: ArpeggioCycle.bar.slide),
            KeyZone(effect: .arpeggiator, value: ArpeggioCycle.halfBeat.slide),
        ])

        state.slide(on: .I, to: 0.1)               // the plain zone: the chord whole
        state.movePointer(from: nil, to: .I)
        clock.advance(beats: 4)
        #expect(notes(sink) == [[60, 64, 67]])
        state.movePointer(from: .I, to: nil)

        sink.reset()
        state.slide(on: .I, to: 0.5)               // a bar per pass
        state.movePointer(from: nil, to: .I)
        clock.advance(beats: 4.0 / 3)
        #expect(notes(sink) == [[60], [64]])
        state.movePointer(from: .I, to: nil)

        sink.reset()
        state.slide(on: .I, to: 0.9)               // half a beat per pass
        state.movePointer(from: nil, to: .I)
        clock.advance(beats: 0.4)
        #expect(notes(sink) == [[60], [64], [67]])
    }

    /// Lifting from a zone that held the arpeggiator on ends the chord: it
    /// must not sound once more, whole, as the arpeggiator switches off.
    @Test func liftingFromAnArpeggiatorZoneJustStops() {
        let (state, sink, _) = makeState(isOn: false)
        state.effects.zones.isOn = true            // the top zone arpeggiates
        state.slide(on: .I, to: 0.9)
        state.movePointer(from: nil, to: .I)
        state.movePointer(from: .I, to: nil)

        #expect(notes(sink) == [[60]])
        #expect(sink.stopCount == 1)

        state.slide(on: .I, to: 0.9)
        state.movePointer(from: nil, to: .I)
        state.setMode(PlayMode())
        #expect(notes(sink) == [[60], [60]])
    }

    /// Sliding into the arpeggiator's zone under a held chord starts the
    /// pattern; sliding out sounds the chord whole again.
    @Test func slidingBetweenZonesReSoundsTheHeldChord() {
        let (state, sink, _) = makeState(isOn: false)
        state.effects.zones.isOn = true
        state.slide(on: .I, to: 0.1)
        state.movePointer(from: nil, to: .I)
        state.slide(on: .I, to: 0.9)
        state.slide(on: .I, to: 0.1)
        #expect(notes(sink) == [[60, 64, 67], [60], [60, 64, 67]])
    }

    // MARK: – With the sequencer

    /// A sequencer chord arpeggiates from the tick that starts it. When the
    /// next chord starts on the very tick the pattern would come round, the
    /// new chord wins: no note of the old one sounds first.
    @Test func sequencerStepsArpeggiateInTime() {
        let (state, sink, clock) = makeState()
        let seq = SequencerState(defaults: isolatedDefaults())
        for step in 0..<4 { seq.steps[step] = SequencerStep(degree: .I, gate: 1) }
        for step in 4..<8 { seq.steps[step] = SequencerStep(degree: .IV, gate: 1) }
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true

        for _ in 0..<5 { clock.tick() }              // one beat of I, then IV begins
        #expect(notes(sink) == [[60], [64], [67], [65]])
        #expect(clock.repeatCount == 1)
    }

    // MARK: – The chord listener

    /// Whoever listens for the chord itself (ChordLink) hears it once, whole,
    /// while the note sinks hear it one note at a time.
    @Test func theChordListenerHearsTheWholeChord() {
        let noteSink = RecordingSink()
        let listener = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: noteSink, chordListener: listener, clock: clock)
        state.effects.arpeggiator.isOn = true

        state.press(degree: .I)
        clock.advance(beats: 2)
        state.release(degree: .I)

        #expect(listener.calls.map(\.isPlay) == [true, false])
        #expect(listener.playCalls.map(\.notes) == [[60, 64, 67]])
        #expect(noteSink.playCalls.allSatisfy { $0.notes.count == 1 })
    }
}

private extension RecordingSink.Call {
    var isPlay: Bool { self != .stop }
}
