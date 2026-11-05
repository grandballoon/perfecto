import Testing
@testable import ScorePractice

/// A note moved along the recording, on the scale: eight right-hand steps
/// a second apart, and left-hand chords at 0 and 4 seconds.
@Suite("Nudging a note")
struct NudgeTests {

    private let practice = Practice(score: scale)

    /// The scale matched by ear two seconds in, at its own pace.
    private var matched: Practice {
        let onsets = [0.0, 1, 2, 3, 4, 5, 6, 7]
        return practice.matching(AutoMatch.Result(
            anchors: onsets.map { AlignmentAnchor(score: $0, recording: $0 + 2) }, unsure: []))
    }

    private func heard(_ moment: Double, _ practice: Practice) -> Double {
        Alignment.recordingTime(moment, practice.alignment)
    }

    @Test func aNudgedNoteIsPinnedAndTheNotesAroundItStay() {
        let nudged = matched.nudging(3, by: 0.12, in: scale)
        #expect(nudged.isPinned(3))
        #expect(abs(heard(3, nudged) - 5.12) < 1e-9)
        #expect(heard(2, nudged) == 4)
        #expect(heard(4, nudged) == 6)
        // Nudged again, from where it is now.
        #expect(abs(heard(3, nudged.nudging(3, by: -0.02, in: scale)) - 5.10) < 1e-9)
    }

    @Test func aNoteNeverPassesTheNotesEitherSide() {
        let late = matched.nudging(3, by: 5, in: scale)
        #expect(heard(3, late) == 6 - Practice.closest)
        let early = matched.moving(3, to: 0, in: scale)
        #expect(heard(3, early) == 4 + Practice.closest)
        #expect(early.alignment.count == 8)
    }

    @Test func withNothingHeldANudgeMovesTheWholeScore() {
        let shifted = practice.nudging(2, by: 0.5, in: scale)
        #expect(shifted.span(of: shifted.root(.right)!.id, in: scale) == 0.5...8.5)
        // A pin either side holds it, as a matched note does.
        let held = shifted.anchoring(6, to: 6.5).nudging(2, by: 10, in: scale)
        #expect(heard(2, held) == 6.5 - Practice.closest)
    }

    @Test func anUnpinnedNoteIsLeftToTheMatch() {
        let nudged = matched.nudging(3, by: 0.2, in: scale)
        let unpinned = nudged.unpinning(3)
        #expect(!unpinned.isPinned(3))
        #expect(heard(3, unpinned) == 5)
        #expect(unpinned == matched)
    }

    @Test func theNoteTappedIsTheStepHeardNearest() {
        let m = matched
        #expect(m.step(.right, nearest: 5.3, within: 0.4, in: scale) == 3)
        #expect(m.step(.right, nearest: 5.5, within: 0.4, in: scale) == nil)
        #expect(m.step(.left, nearest: 5.8, within: 0.4, in: scale) == 1)
    }

    @Test func theNextNoteFromAMomentIsTheFirstHeardAtOrAfterIt() {
        let m = matched
        #expect(m.step(.right, from: 4, forward: true, in: scale) == 2)
        #expect(m.step(.right, from: 4.5, forward: true, in: scale) == 3)
        #expect(m.step(.right, from: 4.5, forward: false, in: scale) == 2)
        #expect(m.step(.right, from: 4, forward: false, in: scale) == 1)
        #expect(m.step(.right, from: 20, forward: true, in: scale) == nil)
        #expect(m.step(.right, from: 1, forward: false, in: scale) == nil)
    }
}

@Suite("RecordingWindow")
struct RecordingWindowTests {

    private let window = RecordingWindow(start: 10, length: 4)

    @Test func aSpanIsShownWithRoomEitherSideWithinTheRecording() {
        let shown = RecordingWindow(showing: 10...20, in: 60)
        #expect(abs(shown.start - 9.2) < 1e-9 && abs(shown.end - 20.8) < 1e-9)
        #expect(RecordingWindow(showing: 0...2, in: 60) == RecordingWindow(start: 0, length: 2.5))
        #expect(RecordingWindow(showing: 55...60, in: 60) == RecordingWindow(start: 54.5, length: 5.5))
        #expect(RecordingWindow(around: 1, reach: 3, in: 60) == RecordingWindow(start: 0, length: 6))
    }

    @Test func itIsDraggedAlongAndStopsAtTheEnds() {
        #expect(window.panned(by: 2, in: 60) == RecordingWindow(start: 12, length: 4))
        #expect(window.panned(by: -20, in: 60) == RecordingWindow(start: 0, length: 4))
        #expect(window.panned(by: 100, in: 60) == RecordingWindow(start: 56, length: 4))
    }

    @Test func aPinchKeepsTheMomentUnderItInPlace() {
        let closer = window.zoomed(by: 2, around: 11, in: 60)
        #expect(closer == RecordingWindow(start: 10.5, length: 2))
        #expect(closer.share(of: 11) == window.share(of: 11))
        #expect(window.zoomed(by: 1000, around: 12, in: 60).length == RecordingWindow.shortest)
        #expect(window.zoomed(by: 0.001, around: 12, in: 60) == RecordingWindow(start: 0, length: 60))
    }

    @Test func aMomentOutOfViewIsBroughtToTheMiddle() {
        #expect(window.revealing(12, in: 60) == window)
        #expect(window.revealing(20, in: 60) == RecordingWindow(start: 18, length: 4))
        // At the very edge it is out of view enough.
        #expect(window.revealing(10.1, in: 60) == RecordingWindow(start: 8.1, length: 4))
    }

    @Test func thePlayheadTurnsItOverAPageAtATime() {
        #expect(window.paging(to: 13, in: 60) == window)
        #expect(window.paging(to: 14.5, in: 60) == RecordingWindow(start: 14, length: 4))
        #expect(window.paging(to: 23, in: 60) == RecordingWindow(start: 22, length: 4))
        #expect(window.paging(to: 3, in: 60) == RecordingWindow(start: 2, length: 4))
        #expect(window.paging(to: 59, in: 60) == RecordingWindow(start: 56, length: 4))
    }

    @Test func itIsAtMostTheRecordingAndAtLeastTheShortest() {
        #expect(RecordingWindow(start: -5, length: 100).clamped(to: 30) == RecordingWindow(start: 0, length: 30))
        #expect(RecordingWindow(start: 5, length: 0).clamped(to: 30).length == RecordingWindow.shortest)
        #expect(window.time(at: 0.25) == 11)
        #expect(window.contains(14) && !window.contains(14.01))
    }
}
