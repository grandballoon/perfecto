import Testing
@testable import ScorePractice

@Suite("Playback")
struct PlaybackTests {

    private let practice = Practice(score: scale)
    private var right: Run { practice.root(.right)! }

    private var quarters: Practice {
        practice.cutting(right.id, before: 2).cutting(right.id, before: 4).cutting(right.id, before: 6)
    }

    @Test func runsOneAfterAnotherPlayStraightThrough() {
        let runs = quarters.root(.right)!.children
        #expect(Playback.segments([runs[1].id, runs[0].id], quarters, scale) == [Segment(start: 0, end: 4)])
    }

    @Test func runsApartPlayApartInOrder() {
        let runs = quarters.root(.right)!.children
        #expect(Playback.segments([runs[3].id, runs[0].id], quarters, scale)
                == [Segment(start: 0, end: 2), Segment(start: 6, end: 8)])
    }

    @Test func aRunInsideAnotherIsNotPlayedTwice() {
        let runs = quarters.root(.right)!.children
        #expect(Playback.segments([right.id, runs[2].id], quarters, scale) == [Segment(start: 0, end: 8)])
    }

    @Test func aRunsNotesAreLitWhereTheScoreHasThem() {
        let run = quarters.root(.right)!.children[1]
        #expect(Playback.notes(of: [run.id], quarters, scale)
                == [TimedNote(pitch: 76, hand: .right, step: 2, on: 2, off: 3),
                    TimedNote(pitch: 77, hand: .right, step: 3, on: 3, off: 4)])
    }

    @Test func aNoteIsLitUntilItsRunEnds() {
        let left = practice.root(.left)!
        let cut = practice.cutting(left.id, before: 1)
        let first = cut.root(.left)!.children[0]
        #expect(Playback.notes(of: [first.id], cut, scale).map(\.off) == [4, 4])
    }

    @Test func aNoteInTwoRunsWatchedIsOneNote() {
        let runs = quarters.root(.right)!.children
        #expect(Playback.notes(of: [right.id, runs[0].id], quarters, scale).count == 8)
    }

    @Test func theKeysSoundingAndEachHandsNextAreLit() {
        let notes = Playback.notes(of: [right.id, practice.root(.left)!.id], practice, scale)
        let lights = Playback.lights(at: 1.25, notes)
        #expect(lights[74] == [KeyLight(hand: .right, kind: .sounding(since: 0.25))])
        #expect(lights[76] == [KeyLight(hand: .right, kind: .next)])
        #expect(lights[48] == [KeyLight(hand: .left, kind: .sounding(since: 1.25))])
        #expect(lights[53] == [KeyLight(hand: .left, kind: .next)])
        #expect(lights[72] == nil)
    }

    @Test func beforeARunItsFirstStepIsNext() {
        let run = quarters.root(.right)!.children[2]
        let lights = Playback.lights(at: 0, Playback.notes(of: [run.id], quarters, scale))
        #expect(lights == [79: [KeyLight(hand: .right, kind: .next)]])
    }

    @Test func thePianoIsBroughtToARunsNotes() {
        let runs = quarters.root(.right)!.children
        #expect(Playback.pitches(of: [runs[1].id], quarters, scale) == 76...77)
        #expect(Playback.pitches(of: [runs[0].id, practice.root(.left)!.id], quarters, scale) == 48...74)
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
