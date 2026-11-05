import Foundation
import Testing
@testable import Perfecto

/// A recording player that plays nothing and says what it was asked.
@MainActor
private final class FakeRecordingPlayer: RecordingPlaying {
    var length = 20.0
    var played: [(segments: [Segment], from: Double, repeats: Bool)] = []
    var isPlaying = false
    var currentTime = 0.0
    var onFinish: (() -> Void)?

    func load(_ url: URL) throws -> Double { length }

    func play(_ segments: [Segment], from: Double, repeats: Bool) {
        played.append((segments, from, repeats))
        isPlaying = true
        currentTime = Playback.start(at: from, in: segments)?.time ?? 0
    }

    func stop() { isPlaying = false }
}

@Suite("ScorePracticeState")
@MainActor
struct ScorePracticeStateTests {

    private let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let player = FakeRecordingPlayer()
    private let piano = PianoState()
    private var library: ScoreLibrary { ScoreLibrary(folder: folder) }

    private func makeState(analyze: @escaping @Sendable (URL) -> RecordingFeatures? = { _ in nil },
                           logger: (any Logger)? = nil) -> ScorePracticeState {
        ScorePracticeState(piano: piano, library: library, makePlayer: { [player] in player }, analyze: analyze,
                           logger: logger)
    }

    /// Where the recording has each step of the right hand, in order.
    private func rightHandHeard(_ state: ScorePracticeState) -> [Double] {
        let onsets = Dictionary(state.timelineNotes.filter { $0.hand == .right }.map { ($0.step, $0.on) },
                                uniquingKeysWith: min)
        return onsets.keys.sorted().map { onsets[$0]! }
    }

    /// The scale played two seconds in, at two thirds of its pace: each
    /// second of the score heard over a second and a half.
    nonisolated static func heard(_ t: Double) -> Double { 2 + 1.5 * t }

    /// What a recording of the scale, played that way, sounds like.
    nonisolated static let performance: RecordingFeatures = {
        let rate = 22_050.0
        var samples = [Float](repeating: 0, count: Int(16 * rate))
        let notes = (0..<8).map { (pitch: [72, 74, 76, 77, 79, 81, 83, 84][$0], onset: Double($0), end: Double($0 + 1)) }
            + [(pitch: 48, onset: 0.0, end: 4.0)]
        for note in notes {
            let f = 440 * pow(2, Double(note.pitch - 69) / 12)
            let first = Int(heard(note.onset) * rate), last = min(samples.count, Int((heard(note.end) + 0.3) * rate))
            for s in first..<last {
                let t = Double(s - first) / rate
                let v = (1...4).reduce(0.0) { $0 + sin(2 * .pi * f * Double($1) * t) / Double($1) }
                samples[s] += Float(0.2 * min(1, t / 0.005) * exp(-t / 0.9) * v)
            }
        }
        return RecordingFeatures.analyze(samples, sampleRate: rate)
    }()

    /// Eight right-hand quarters a second apart, C5 up, over a held C3.
    private func scoreFile() throws -> URL {
        let names: [(String, Int)] = [("C", 5), ("D", 5), ("E", 5), ("F", 5), ("G", 5), ("A", 5), ("B", 5), ("C", 6)]
        let right = names.map { "<note><pitch><step>\($0.0)</step><octave>\($0.1)</octave></pitch><duration>1</duration><staff>1</staff></note>" }
        let xml = """
        <score-partwise version="4.0"><work><work-title>Scale</work-title></work><part id="P1">
        <measure number="1"><attributes><divisions>1</divisions><staves>2</staves></attributes>
        <direction><sound tempo="60"/></direction>\(right[0..<4].joined())
        <backup><duration>4</duration></backup>
        <note><pitch><step>C</step><octave>3</octave></pitch><duration>4</duration><staff>2</staff></note></measure>
        <measure number="2">\(right[4..<8].joined())</measure></part></score-partwise>
        """
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).musicxml")
        try Data(xml.utf8).write(to: url)
        return url
    }

    private func recordingFile() throws -> URL {
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0]).write(to: url)
        return url
    }

    /// A state with the scale imported and a recording added.
    private func practising() throws -> ScorePracticeState {
        let state = makeState()
        state.importScore(from: try scoreFile())
        state.importRecording(from: try recordingFile())
        return state
    }

    @Test func anImportedScoreIsOpenedOnItsRightHand() throws {
        let state = try practising()
        #expect(state.piece?.title == "Scale")
        #expect(state.hands == [.right, .left])
        #expect(state.hand == .right)
        #expect(state.focusPath.map(\.steps) == [0...7])
        #expect(state.hasRecording)
        #expect(state.failure == nil)
    }

    @Test func aMidiFileIsAScoreWithItsHandsByTrack() throws {
        // Two tracks, "lh" and "rh", a quarter note each at 120.
        func track(_ name: String, _ pitch: UInt8) -> [UInt8] {
            let body: [UInt8] = [0x00, 0xFF, 0x03, UInt8(name.utf8.count)] + Array(name.utf8)
                + [0x00, 0x90, pitch, 100, 0x83, 0x60, 0x80, pitch, 0, 0x00, 0xFF, 0x2F, 0x00]
            return Array("MTrk".utf8) + [0, 0, 0, UInt8(body.count)] + body
        }
        let bytes = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 2, 0x01, 0xE0] + track("lh", 48) + track("rh", 72)
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mid")
        try Data(bytes).write(to: url)
        let state = makeState()
        state.importScore(from: url)
        #expect(state.failure == nil)
        #expect(state.piece?.scoreFile == "score.mid")
        #expect(state.focusSteps.map { $0.step.notes.map(\.pitch) } == [[72]])
        state.show(.left)
        #expect(state.focusSteps.map { $0.step.notes.map(\.pitch) } == [[48]])
    }

    @Test func whatIsNotAScoreIsRefusedAndSaid() throws {
        let state = makeState()
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).xml")
        try Data("<html/>".utf8).write(to: url)
        state.importScore(from: url)
        #expect(state.piece == nil)
        #expect(state.failure != nil)
    }

    @Test func cutsAndMatchesAreKeptAndReadAgain() async throws {
        let state = try practising()
        state.toggleCut(before: 4)
        state.select(0)
        state.moveSelected(to: 3, isDone: true)

        let again = makeState()
        await again.appear()
        #expect(again.piece == state.piece)
        #expect(again.hasRecording)
        #expect(again.shownRuns.map(\.steps) == [0...3, 4...7])
        #expect(again.span(of: again.focus!)?.lowerBound == 3)
    }

    /// The phone and the Mac keep their pieces in one folder in iCloud.
    @Test func whatTheOtherDeviceSavesIsTakenUp() async throws {
        let phone = try practising()
        let mac = makeState()
        await mac.appear()
        #expect(mac.piece?.id == phone.piece?.id)

        phone.toggleCut(before: 4)
        await mac.libraryChanged()
        #expect(mac.shownRuns.map(\.steps) == [0...3, 4...7])
    }

    @Test func anOlderSaveDoesNotUndoALaterOne() async throws {
        let phone = try practising()
        let mac = makeState()
        await mac.appear()
        mac.toggleCut(before: 2)
        // The Mac saved last: the phone takes it up, and the Mac keeps it.
        await phone.libraryChanged()
        #expect(phone.shownRuns.map(\.steps) == [0...1, 2...7])
        await mac.libraryChanged()
        #expect(mac.shownRuns.map(\.steps) == [0...1, 2...7])
    }

    @Test func aPieceDeletedOnTheOtherDeviceIsClosed() async throws {
        let phone = try practising()
        let mac = makeState()
        await mac.appear()
        phone.delete(phone.piece!)
        await mac.libraryChanged()
        #expect(mac.piece == nil)
        #expect(mac.pieces.isEmpty)
    }

    @Test func aClosedPieceLeavesThePianoAndStaysAmongThePieces() async throws {
        let state = try practising()
        state.play()
        let closed = try #require(state.piece)
        state.closePiece()
        #expect(state.piece == nil)
        #expect(state.score == nil)
        #expect(!state.hasRecording)
        #expect(state.listening == nil)
        #expect(state.lights(at: 1).isEmpty)
        #expect(state.pieces.map(\.id) == [closed.id])

        // The screen shown again leaves the piano as it was left.
        await state.appear()
        #expect(state.piece == nil)

        await state.open(closed)
        #expect(state.piece?.id == closed.id)
        #expect(state.hasRecording)
    }

    // MARK: – Matching by ear

    /// A state with the scale imported and its performance added, matched.
    private func matched() async throws -> ScorePracticeState {
        player.length = 16
        let state = makeState(analyze: { _ in Self.performance })
        state.importScore(from: try scoreFile())
        state.importRecording(from: try recordingFile())
        await state.matchMade()
        return state
    }

    @Test func anAddedRecordingIsMatchedByEar() async throws {
        let state = try await matched()
        #expect(state.isMatching == false)
        #expect(state.practice?.matched.isEmpty == false)
        let span = try #require(state.span(of: state.focus!))
        #expect(abs(span.lowerBound - Self.heard(0)) < 0.05)
        // Every step of the right hand where it is heard, none pinned.
        let heard = rightHandHeard(state)
        #expect(heard.count == 8)
        for (step, at) in heard.enumerated() {
            #expect(abs(at - Self.heard(Double(step))) < 0.05)
        }
        #expect(state.pinTimes.isEmpty)
    }

    @Test func aNoteDraggedIsPinnedAndTheRestMatchedAround() async throws {
        let state = try await matched()
        state.select(4)
        state.moveSelected(to: Self.heard(4) + 0.2, isDone: true)
        await state.matchMade()
        #expect(state.isSelectedPinned)
        #expect(state.selectedTime == Self.heard(4) + 0.2)
        let heard = rightHandHeard(state)
        #expect(abs(heard[6] - Self.heard(6)) < 0.05)
        #expect(zip(heard, heard.dropFirst()).allSatisfy { $0 < $1 })

        state.clearPinsAndMatch()
        await state.matchMade()
        #expect(!state.isSelectedPinned)
        #expect(abs((state.selectedTime ?? 0) - Self.heard(4)) < 0.05)
    }

    @Test func nudgesInARowAreMatchedAroundOnceTheyStop() async throws {
        let logger = RecordingLogger()
        player.length = 16
        let state = makeState(analyze: { _ in Self.performance }, logger: logger)
        state.importScore(from: try scoreFile())
        state.importRecording(from: try recordingFile())
        await state.matchMade()
        logger.reset()

        state.select(4)
        for _ in 0..<3 { state.nudge(by: ScorePracticeState.fineNudge) }
        #expect(state.isMatching)
        await state.matchMade()
        let matches = logger.events.filter { if case .practice_matched = $0 { true } else { false } }
        #expect(matches.count == 1)
        #expect(abs((state.selectedTime ?? 0) - (Self.heard(4) + 0.03)) < 0.06)
        #expect(state.isSelectedPinned)
    }

    // MARK: – Nudge points

    @Test func aNudgePointIsTaggedWhereTheRecordingStandsAndGoneTo() throws {
        let state = try practising()
        state.seek(to: 3)
        state.toggleTag()
        state.seek(to: 9)
        state.toggleTag()
        #expect(state.practice?.nudges == [3, 9])
        #expect(state.isAtTag)

        state.seek(to: 0)
        state.goToNudge(forward: true)
        #expect(state.currentTime == 3)
        #expect(state.window == RecordingWindow(start: 0, length: 6))
        state.goToNudge(forward: true)
        #expect(state.currentTime == 9)
        state.goToNudge(forward: false)
        #expect(state.currentTime == 3)

        state.toggleTag()
        #expect(state.practice?.nudges == [9])
        state.focus(on: state.focus!)
        #expect(state.window == RecordingWindow(showing: try #require(state.span(of: state.focus!)), in: 20))
    }

    @Test func goingToANudgePointWhileListeningListensOnFromIt() throws {
        let state = try practising()
        state.seek(to: 5)
        state.toggleTag()
        state.seek(to: 0)
        state.listen()
        state.goToNudge(forward: true)
        #expect(state.listening == .free)
        #expect(player.played.last?.segments == [Segment(start: 5, end: 20)])
    }

    @Test func aNewRecordingForgetsWhatWasMadeOfTheOldOne() throws {
        let state = try practising()
        state.seek(to: 3)
        state.toggleTag()
        state.select(0)
        state.nudge(by: 0.5)
        #expect(state.practice?.anchors.isEmpty == false)
        state.importRecording(from: try recordingFile())
        #expect(state.practice?.nudges.isEmpty == true)
        #expect(state.practice?.anchors.isEmpty == true)
    }

    @Test func aRunIsNamedAndFoundInTheListOfAllRuns() async throws {
        let state = try practising()
        state.toggleCut(before: 4)
        let second = state.shownRuns[1].id
        state.focus(on: second)
        state.toggleCut(before: 6)
        let inner = state.shownRuns[1].id
        state.rename(inner, to: "the turn")
        #expect(state.title(of: inner) == "the turn")
        #expect(state.label(of: inner) == "2.2")

        let right = try #require(state.allRuns.first { $0.hand == .right })
        #expect(right.runs.map(\.depth) == [0, 1, 1, 2, 2])
        #expect(right.runs.last?.run.name == "the turn")

        // Gone to from the list: the run it is one of in focus, and it watched.
        state.focus(on: state.focusPath[0].id)
        state.goTo(inner)
        #expect(state.focus == second)
        #expect(state.watched == [inner])

        // Kept with the piece.
        let again = makeState()
        await again.appear()
        #expect(again.practice?.find(inner)?.run.name == "the turn")
    }

        @Test func aRunIsOpenedAndCutIntoRunsOfItsOwn() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        let second = state.shownRuns[1]
        state.focus(on: second.id)
        state.toggleCut(before: 6)
        #expect(state.shownRuns.map(\.steps) == [4...5, 6...7])
        #expect(state.label(of: state.shownRuns[1].id) == "2.2")
        state.toggleCut(before: 6)
        #expect(state.shownRuns.map(\.steps) == [4...7])
    }

    @Test func theRunsChosenArePlayedOverAgainOrOnce() throws {
        let state = try practising()
        state.toggleCut(before: 2)
        state.toggleCut(before: 4)
        state.toggle(state.shownRuns[2].id)
        state.toggle(state.shownRuns[0].id)
        state.play()
        #expect(player.played.last?.segments == [Segment(start: 0, end: 2), Segment(start: 4, end: 8)])
        #expect(player.played.last?.repeats == true)
        #expect(state.listening == .runs)

        state.repeats = false
        state.play()
        #expect(player.played.last?.repeats == false)
    }

    @Test func withNoRunChosenTheRunInFocusIsPlayed() throws {
        let state = try practising()
        state.play()
        #expect(player.played.last?.segments == [Segment(start: 0, end: 8)])
    }

    @Test func listeningPlaysOnFromWhereTheRecordingStands() throws {
        let state = try practising()
        state.seek(to: 5)
        state.listen()
        #expect(player.played.last?.segments == [Segment(start: 5, end: 20)])
        #expect(state.listening == .free)
        state.stop()
        #expect(state.listening == nil)
    }

    @Test func spacePlaysTheRunsWatchedOrStopsWhatPlays() throws {
        let state = try practising()
        state.playOrStop()
        #expect(state.listening == .runs)
        state.playOrStop()
        #expect(state.listening == nil)
        state.listen()
        state.playOrStop()
        #expect(state.listening == nil)
    }

    @Test func aTapOnTheRecordingWhileListeningListensOnFromThere() throws {
        let state = try practising()
        state.listen()
        state.seek(to: 6.5)
        #expect(state.listening == .free)
        #expect(player.played.last?.segments == [Segment(start: 6.5, end: 20)])
        // Stopped, the keys of the hand shown are lit as they are where it stands.
        state.stop()
        state.seek(to: 3.5)
        let sounding = state.lights(at: state.currentTime).filter { $0.value.contains { $0.kind != .next } }
        #expect(Set(sounding.keys) == [77])
    }

    @Test func playGoesOnFromWhereTheRecordingStands() throws {
        let state = try practising()
        state.seek(to: 5)
        state.play()
        #expect(player.played.last?.segments == [Segment(start: 0, end: 8)])
        #expect(state.currentTime == 5)
        // Stopped and played again, it goes on from where it stopped.
        player.currentTime = 6.5
        state.stop()
        state.play()
        #expect(state.currentTime == 6.5)
    }

    @Test func aTapWhileTheRunsPlayPlaysThemOnFromThere() throws {
        let state = try practising()
        state.play()
        state.seek(to: 4)
        #expect(state.listening == .runs)
        #expect(state.currentTime == 4)
    }

    @Test func skippingGoesFiveSecondsAndKeepsPlaying() throws {
        let state = try practising()
        state.listen()
        state.skip(by: 5)
        #expect(state.listening == .free)
        #expect(state.currentTime == 5)
        state.skip(by: -ScorePracticeState.skipSeconds * 3)
        #expect(state.currentTime == 0)
        state.stop()
        state.skip(by: 5)
        #expect(state.listening == nil)
        #expect(state.currentTime == 5)
    }

    @Test func aTapWhileStoppedStaysStoppedWithinTheRecording() throws {
        let state = try practising()
        state.seek(to: 30)
        #expect(state.listening == nil)
        #expect(state.currentTime == 20)
        #expect(player.played.isEmpty)
    }

    @Test func theKeysOfTheRunsWatchedLightAsTheRecordingPlays() throws {
        let state = try practising()
        state.play()
        let lights = state.lights(at: 1.5)
        #expect(lights[74]?.first?.hand == .right)
        #expect(lights[76] == [KeyLight(hand: .right, kind: .next)])
    }

    @Test func aStepLookedAtWhileCuttingIsLit() throws {
        let state = try practising()
        state.isCutting = true
        state.select(2)
        #expect(Set(state.lights(at: state.currentTime).keys) == [76])
        #expect(state.currentTime == 2)
    }

    @Test func aRunsFirstNoteMovedMovesWhereItBegins() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        state.select(4)
        state.moveSelected(to: 6, isDone: true)
        #expect(state.span(of: state.shownRuns[0].id)?.upperBound == 6)
        #expect(state.span(of: state.shownRuns[1].id)?.lowerBound == 6)
    }

    @Test func aNoteNudgedIsPinnedAndUnpinnedGoesBack() throws {
        let state = try practising()
        state.select(4)
        state.nudge(by: ScorePracticeState.coarseNudge)
        state.nudge(by: ScorePracticeState.coarseNudge)
        #expect(abs((state.selectedTime ?? 0) - 4.2) < 1e-9)
        #expect(state.currentTime == state.selectedTime)
        #expect(state.isSelectedPinned)
        state.unpinSelected()
        #expect(!state.isSelectedPinned)
        #expect(state.selectedTime == 4)
    }

    @Test func theNextAndPreviousNoteAreChosenFromWhereTheRecordingStands() throws {
        let state = try practising()
        state.seek(to: 2.5)
        state.selectNext(forward: true)
        #expect(state.selectedStep == 3)
        state.selectNext(forward: false)
        #expect(state.selectedStep == 2)
        #expect(state.currentTime == 2)
        // A tap near a note chooses it; a tap on no note stands the recording there.
        state.tapNotes(at: 5.05, within: 0.1)
        #expect(state.selectedStep == 5)
        state.tapNotes(at: 12, within: 0.1)
        #expect(state.currentTime == 12)
    }

    @Test func hearingANotePlaysAroundItAndStandsAtItAgain() throws {
        let state = try practising()
        state.select(3)
        state.hearSelected()
        #expect(state.listening == .step)
        #expect(player.played.last?.segments == [Segment(start: 1.5, end: 4)])
        player.currentTime = 4
        player.onFinish?()
        #expect(state.listening == nil)
        #expect(state.currentTime == 3)
    }

    @Test func theTimelinesTurnAPageWhilePlayingUntilTheyAreMoved() throws {
        let state = try practising()
        state.zoom(by: 4)
        let window = try #require(state.window)
        let later = window.end + 0.1
        state.listen()
        let shown = try #require(state.shownWindow(at: later))
        #expect(shown.contains(later))
        #expect(shown.length == window.length)
        #expect(shown.start == window.end)

        // Moved by hand, they stay where they were put.
        state.showWindow(window)
        #expect(state.shownWindow(at: later) == window)
        // Played again, they follow once more.
        state.stop()
        state.listen()
        #expect(state.shownWindow(at: later)?.contains(later) == true)
    }

    @Test func thePianoIsBroughtToTheRunsWatched() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        state.toggle(state.shownRuns[0].id)
        #expect(piano.span == PianoSpan.fitting(72...77))
        state.show(.left)
        #expect(piano.span == PianoSpan.fitting(48...48))
    }

    @Test func theLeftHandHasItsOwnRuns() throws {
        let state = try practising()
        state.show(.left)
        #expect(state.hand == .left)
        #expect(state.label(of: state.focus!) == "Left hand")
        #expect(state.focusSteps.map { $0.step.notes.map(\.pitch) } == [[48]])
    }
}

@Suite("PianoSpan fitting")
struct PianoSpanFittingTests {

    @Test func aRunsKeysAreAllInViewWithHalfAKeyToSpare() {
        // C4 to G5: twelve white keys.
        let span = PianoSpan.fitting(60...79)
        #expect(span.count == 13)
        #expect(span.start == Double(PianoKeys.whitesBelow(60)) - 0.5)
    }

    @Test func aFewKeysAreShownWithAnOctaveAroundThem() {
        let span = PianoSpan.fitting(64...65)
        #expect(span.count == PianoSpan.fewest)
        #expect(abs((span.start + span.count / 2) - Double(PianoKeys.whitesBelow(64) + 1)) < 0.001)
    }
}
