import Testing
@testable import ScorePractice

@Suite("Alignment")
struct AlignmentTests {

    @Test func withNoAnchorsTheScoreIsTheRecording() {
        #expect(Alignment.recordingTime(3, []) == 3)
    }

    @Test func oneAnchorSaysOnlyWhereTheScoreIs() {
        let anchors = [AlignmentAnchor(score: 2, recording: 7)]
        #expect(Alignment.recordingTime(4, anchors) == 9)
        #expect(Alignment.scoreTime(9, anchors) == 4)
    }

    @Test func betweenAnchorsTimeIsSharedEvenlyAndBeyondThemTheNearestPaceKeeps() {
        let anchors = [AlignmentAnchor(score: 0, recording: 1), AlignmentAnchor(score: 4, recording: 9), AlignmentAnchor(score: 8, recording: 11)]
        #expect(Alignment.recordingTime(2, anchors) == 5)
        #expect(Alignment.recordingTime(6, anchors) == 10)
        #expect(Alignment.recordingTime(-1, anchors) == -1)
        #expect(Alignment.recordingTime(10, anchors) == 12)
        #expect(Alignment.scoreTime(10, anchors) == 6)
    }

    @Test func anAnchorReplacesTheOnesItContradicts() {
        let anchors = [AlignmentAnchor(score: 0, recording: 1), AlignmentAnchor(score: 4, recording: 9), AlignmentAnchor(score: 8, recording: 11)]
        // Heard before the anchor of the score's start: that one goes.
        #expect(Alignment.set(AlignmentAnchor(score: 2, recording: 0.5), in: anchors)
                == [AlignmentAnchor(score: 2, recording: 0.5), AlignmentAnchor(score: 4, recording: 9), AlignmentAnchor(score: 8, recording: 11)])
        // At a moment anchored already: the new one wins.
        #expect(Alignment.set(AlignmentAnchor(score: 4, recording: 8), in: anchors)
                == [AlignmentAnchor(score: 0, recording: 1), AlignmentAnchor(score: 4, recording: 8), AlignmentAnchor(score: 8, recording: 11)])
    }
}

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

    @Test func aRunsNotesAreLitAsTheRecordingHasThem() {
        let run = quarters.root(.right)!.children[1]
        let matched = quarters.settingStart(of: right.id, to: 0, in: scale).settingEnd(of: right.id, to: 16, in: scale)
        let notes = Playback.notes(of: [run.id], matched, scale)
        #expect(notes == [TimedNote(pitch: 76, hand: .right, step: 2, on: 4, off: 6),
                          TimedNote(pitch: 77, hand: .right, step: 3, on: 6, off: 8)])
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

    @Test func aWaveformIsEachStretchsLoudest() {
        #expect(Waveform.peaks([0.1, -0.5, 0.2, 0.3, -0.1], frames: 2) == [0.5, 0.3, 0.1])
    }
}
