import Testing
@testable import Perfecto

@Suite("TrautoniumState")
@MainActor
struct TrautoniumStateTests {

    // MARK: – Helpers

    /// A performance in C major, octave 4, whose bars sound through
    /// players of their own on one note sink.
    @MainActor
    private struct Rig {
        let clock: ManualClock
        let notes: RecordingNoteSink
        let state: PerformanceState

        init() {
            let (clock, notes) = (ManualClock(), RecordingNoteSink())
            self.clock = clock
            self.notes = notes
            state = PerformanceState(sink: RecordingSink(),
                                     trautoniumSink: { NotePlayer([notes], clock: clock) },
                                     clock: clock)
        }

        var bars: TrautoniumState { state.trautonium }
    }

    /// The place on `bar` where `pitch` is, as loud as `across` makes it.
    private func place(_ rig: Rig, _ pitch: Double, on bar: TrautoniumBar = .low,
                       across: Double = 1) -> BarPlace {
        BarPlace(along: rig.bars.range(of: bar).place(of: pitch), across: across)
    }

    private func near(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-4 }

    // MARK: – The bars

    @Test func theBarsAreTwoOctavesFromTheTonicTheHighOneAnOctaveUp() {
        let rig = Rig()
        #expect(rig.bars.range(of: .low) == BarRange(lowest: 60))
        #expect(rig.bars.range(of: .high) == BarRange(lowest: 72))
        #expect(rig.bars.notes(of: .low) == [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84])
    }

    @Test func theBarsFollowTheKeyAndTheOctave() {
        let rig = Rig()
        rig.state.key = Key(root: .D, scale: .naturalMinor)
        rig.state.octave = 3
        #expect(rig.bars.range(of: .low).lowest == 50)
        #expect(Array(rig.bars.notes(of: .low).prefix(8)) == [50, 52, 53, 55, 57, 58, 60, 62])
    }

    @Test func aBarThatWouldRunPastTheHighestNoteIsAnOctaveDown() {
        let rig = Rig()
        rig.state.octave = 8
        #expect(rig.bars.range(of: .high).highest <= 127)
        #expect(rig.bars.range(of: .high).lowest % 12 == 0)
    }

    // MARK: – Landing

    @Test func aFingerComesDownOnTheNearestNoteOfTheKey() {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 61.3))
        #expect(rig.notes.started == [62])
        #expect(rig.notes.sounds.last?.bend == 0)
        rig.bars.release(.low)

        rig.bars.press(.low, at: place(rig, 60.8))            // C# is no note of the key
        #expect(rig.notes.started == [62, 60])
    }

    @Test func theHighBarIsAVoiceOfItsOwn() {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 60))
        rig.bars.press(.high, at: place(rig, 79, on: .high))
        #expect(rig.notes.sounding == [60, 79])

        rig.bars.release(.low)
        #expect(rig.notes.sounding == [79])
        rig.bars.release(.high)
        #expect(rig.notes.sounding.isEmpty)
    }

    // MARK: – Sliding

    @Test func aSlideBendsTheNoteAsFarAsTheFingerMoves() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 61.3))            // lands on D
        rig.bars.move(.low, to: place(rig, 62.8))
        #expect(near(try #require(rig.notes.changes.last).bend, 1.5))
        #expect(rig.bars.playing[.low]?.pitch == 63.5)

        rig.bars.move(.low, to: place(rig, 60.3))
        #expect(near(try #require(rig.notes.changes.last).bend, -1))
        // The one note, bent: never struck again.
        #expect(rig.notes.started == [62])
    }

    @Test func aSlideStopsAtTheEndsOfTheBar() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 83.8))            // lands on C, the top
        rig.bars.move(.low, to: BarPlace(along: 1, across: 1))
        #expect(rig.bars.playing[.low]?.pitch == 84)
    }

    @Test func aFingerAtRestIsBroughtOntoANoteOfTheKey() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 62))
        rig.bars.move(.low, to: place(rig, 63.4))
        #expect(near(try #require(rig.notes.changes.last).bend, 1.4))

        rig.clock.advance(seconds: TrautoniumState.rest + 0.01)
        #expect(near(try #require(rig.notes.changes.last).bend, 2))      // E
        #expect(rig.bars.playing[.low]?.pitch == 64)

        // From there the pitch follows the finger again.
        rig.bars.move(.low, to: place(rig, 63.9))
        #expect(near(try #require(rig.notes.changes.last).bend, 2.5))
    }

    @Test func aFingerThatKeepsMovingIsLeftWhereItIs() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 62))
        for step in 1...6 {
            rig.clock.advance(seconds: TrautoniumState.rest * 0.6)
            rig.bars.move(.low, to: place(rig, 62 + (step.isMultiple(of: 2) ? 0.3 : -0.3)))
        }
        #expect(near(try #require(rig.notes.changes.last).bend, 0.3))
    }

    @Test func aSecondFingerTakesTheNoteThereWithoutStrikingIt() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 60))
        rig.bars.press(.low, at: place(rig, 66.8))
        #expect(rig.notes.started == [60])
        #expect(near(try #require(rig.notes.changes.last).bend, 7))      // G
    }

    // MARK: – How loud

    @Test func acrossTheBarIsHowLoud() throws {
        let rig = Rig()
        rig.bars.press(.low, at: place(rig, 60, across: 0))
        #expect(rig.notes.sounds.last?.level == TrautoniumState.quietest)

        rig.bars.move(.low, to: place(rig, 60, across: 1))
        #expect(rig.notes.changes.last?.level == 1)
        rig.bars.move(.low, to: place(rig, 60, across: 0.5))
        let half = try #require(rig.notes.changes.last).level
        #expect(half > TrautoniumState.quietest && half < 0.5)
        // Only the level moved.
        #expect(rig.notes.changes.allSatisfy { $0.bend == 0 })
    }

    // MARK: – Sound

    @Test func aBarIsPlayedInTheKeysSoundWithTheEffectsAsSet() {
        let rig = Rig()
        rig.state.setSynthPreset(.bell)
        rig.state.effects.reverb.isOn = true
        rig.bars.press(.low, at: place(rig, 60))
        #expect(rig.notes.sounds.last?.preset == .bell)
        #expect(rig.notes.sounds.last?.reverb.isOn == true)
    }

    // MARK: – The screen

    @Test func theBarsTakeTheScreenAndLeavingItEndsWhatSounds() {
        let rig = Rig()
        rig.state.show(.trautonium)
        #expect(rig.state.phoneScreen == .trautonium)
        #expect(rig.bars.isShown)

        rig.bars.press(.low, at: place(rig, 60))
        rig.state.show(.play)
        #expect(!rig.bars.isShown)
        #expect(rig.notes.sounding.isEmpty)
        #expect(rig.bars.playing.isEmpty)
    }
}
