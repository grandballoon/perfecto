import Testing
@testable import ScorePractice

@Suite("Playback")
struct PlaybackTests {

    private func quarter(_ i: Int) -> Passage { Passage(.right, from: 2 * i, to: 2 * i + 1) }
    private let right = Passage.whole(.right, in: scale)!
    private let left = Passage.whole(.left, in: scale)!

    @Test func runsOneAfterAnotherPlayStraightThrough() {
        #expect(Playback.segments([quarter(1), quarter(0)], scale) == [Segment(start: 0, end: 4)])
    }

    @Test func runsApartPlayApartInOrder() {
        #expect(Playback.segments([quarter(3), quarter(0)], scale)
                == [Segment(start: 0, end: 2), Segment(start: 6, end: 8)])
    }

    @Test func aRunInsideAnotherOrOverlappingItIsNotPlayedTwice() {
        #expect(Playback.segments([right, quarter(2)], scale) == [Segment(start: 0, end: 8)])
        #expect(Playback.segments([Passage(.right, from: 0, to: 4), Passage(.left, from: 1, to: 1)], scale)
                == [Segment(start: 0, end: 8)])
    }

    @Test func aRunsNotesAreLitWhereTheScoreHasThem() {
        #expect(Playback.notes(of: [quarter(1)], scale)
                == [TimedNote(pitch: 76, hand: .right, on: 2, off: 3),
                    TimedNote(pitch: 77, hand: .right, on: 3, off: 4)])
    }

    @Test func aRunOfBothHandsLightsEachNoteInItsHand() {
        #expect(Playback.notes(of: [Passage(.both, from: 3, to: 4)], scale)
                == [TimedNote(pitch: 77, hand: .right, on: 3, off: 4),
                    TimedNote(pitch: 53, hand: .left, on: 4, off: 5),
                    TimedNote(pitch: 79, hand: .right, on: 4, off: 5)])
    }

    @Test func aNoteIsLitUntilItsRunEnds() {
        #expect(Playback.notes(of: [Passage(.left, from: 0, to: 0)], scale).map(\.off) == [4, 4])
        // In both hands' steps, the next step is the right hand's at 1.
        #expect(Playback.notes(of: [Passage(.both, from: 0, to: 0)], scale).map(\.off) == [1, 1, 1])
    }

    @Test func aNoteInTwoRunsWatchedIsOneNote() {
        #expect(Playback.notes(of: [right, quarter(0)], scale).count == 8)
        #expect(Playback.notes(of: [right, Passage(.both, from: 0, to: 7)], scale).count == 11)
    }

    @Test func theKeysSoundingAndEachHandsNextAreLit() {
        let notes = Playback.notes(of: [right, left], scale)
        let lights = Playback.lights(at: 1.25, notes)
        #expect(lights[74] == [KeyLight(hand: .right, kind: .sounding(since: 0.25))])
        #expect(lights[76] == [KeyLight(hand: .right, kind: .next)])
        #expect(lights[48] == [KeyLight(hand: .left, kind: .sounding(since: 1.25))])
        #expect(lights[53] == [KeyLight(hand: .left, kind: .next)])
        #expect(lights[72] == nil)
    }

    @Test func beforeARunItsFirstStepIsNext() {
        let lights = Playback.lights(at: 0, Playback.notes(of: [quarter(2)], scale))
        #expect(lights == [79: [KeyLight(hand: .right, kind: .next)]])
    }

    @Test func thePianoIsBroughtToARunsNotes() {
        #expect(Playback.pitches(of: [quarter(1)], scale) == 76...77)
        #expect(Playback.pitches(of: [quarter(0), left], scale) == 48...74)
    }

}

@Suite("A pass of playing")
struct PlayPassTests {

    @Test func aPassSoundsBothHandsInItsStretchesOneAfterAnother() {
        let segments = [Segment(start: 0, end: 2), Segment(start: 6, end: 8)]
        let pass = Playback.pass(scale.notes, segments, from: PlayStart(segment: 0, time: 0))
        #expect(pass.length == 4)
        #expect(pass.notes == [
            PassNote(pitch: 48, start: 0, end: 2), PassNote(pitch: 55, start: 0, end: 2),
            PassNote(pitch: 72, start: 0, end: 1), PassNote(pitch: 74, start: 1, end: 2),
            PassNote(pitch: 83, start: 2, end: 3), PassNote(pitch: 84, start: 3, end: 4),
        ])
    }

    @Test func aPassBegunInsideAStretchSoundsWhatIsHeldThere() {
        let pass = Playback.pass(scale.notes, [Segment(start: 0, end: 8)], from: PlayStart(segment: 0, time: 2.5))
        #expect(pass.length == 5.5)
        // The left hand's chord, struck at 0, is held over 2.5; E5 is struck at 2.
        #expect(pass.notes.prefix(3) == [PassNote(pitch: 48, start: 0, end: 1.5),
                                         PassNote(pitch: 55, start: 0, end: 1.5),
                                         PassNote(pitch: 76, start: 0, end: 0.5)])
        #expect(pass.notes.last == PassNote(pitch: 84, start: 4.5, end: 5.5))
    }

    @Test func aPassBegunInALaterSegmentPlaysOnlyFromThere() {
        let segments = [Segment(start: 0, end: 2), Segment(start: 6, end: 8)]
        let pass = Playback.pass(scale.notes, segments, from: PlayStart(segment: 1, time: 6))
        #expect(pass.stretches == [PlayPass.Stretch(from: 6, to: 8, at: 0)])
        #expect(pass.notes.map(\.pitch) == [53, 83, 84])
    }

    @Test func theMomentHeardFollowsTheStretches() {
        let segments = [Segment(start: 0, end: 2), Segment(start: 6, end: 8)]
        let pass = Playback.pass(scale.notes, segments, from: PlayStart(segment: 0, time: 1))
        #expect(pass.scoreTime(at: -1) == 1)
        #expect(pass.scoreTime(at: 0.5) == 1.5)
        #expect(pass.scoreTime(at: 1.5) == 6.5)
        #expect(pass.scoreTime(at: 10) == 8)
    }
}

@Suite("Where play begins")
struct PlayStartTests {
    let segments = [Segment(start: 2, end: 4), Segment(start: 6, end: 9)]

    @Test func insideASegmentPlayGoesOnFromThePlayhead() {
        #expect(Playback.start(at: 7.5, in: segments) == PlayStart(segment: 1, time: 7.5))
        #expect(Playback.start(at: 2, in: segments) == PlayStart(segment: 0, time: 2))
    }

    @Test func betweenSegmentsPlayBeginsAtTheNext() {
        #expect(Playback.start(at: 0, in: segments) == PlayStart(segment: 0, time: 2))
        #expect(Playback.start(at: 5, in: segments) == PlayStart(segment: 1, time: 6))
    }

    @Test func pastTheLastOrAtItsEndPlayBeginsAgainAtTheFirst() {
        #expect(Playback.start(at: 12, in: segments) == PlayStart(segment: 0, time: 2))
        #expect(Playback.start(at: 9, in: segments) == PlayStart(segment: 0, time: 2))
        #expect(Playback.start(at: 3.98, in: segments) == PlayStart(segment: 1, time: 6))
    }

    @Test func nothingToPlayHasNoStart() {
        #expect(Playback.start(at: 1, in: []) == nil)
    }
}
