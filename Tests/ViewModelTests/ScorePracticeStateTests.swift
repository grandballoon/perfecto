import Foundation
import Testing
@testable import Perfecto

/// A score player that sounds nothing and says what it was asked.
@MainActor
private final class FakeScorePlayer: PracticePlaying {
    var played: [(notes: [ScoreNote], segments: [Segment], from: Double, repeats: Bool)] = []
    var isPlaying = false
    var currentTime = 0.0
    var onFinish: (() -> Void)?

    func play(_ notes: [ScoreNote], _ segments: [Segment], from: Double, repeats: Bool) {
        played.append((notes, segments, from, repeats))
        isPlaying = true
        currentTime = Playback.start(at: from, in: segments)?.time ?? 0
    }

    func stop() { isPlaying = false }
}

@Suite("ScorePracticeState")
@MainActor
struct ScorePracticeStateTests {

    private let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let player = FakeScorePlayer()
    private let piano = PianoState()
    private var library: ScoreLibrary { ScoreLibrary(folder: folder) }

    private func makeState() -> ScorePracticeState {
        ScorePracticeState(piano: piano, library: library, makePlayer: { [player] in player })
    }

    /// Eight right-hand quarters a second apart, C5 up, over a held C3:
    /// two bars of four at 60.
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

    /// A state with the scale imported.
    private func practising() throws -> ScorePracticeState {
        let state = makeState()
        state.importScore(from: try scoreFile())
        return state
    }

    // MARK: – Pieces

    @Test func anImportedScoreIsOpenedOnItsRightHand() throws {
        let state = try practising()
        #expect(state.piece?.title == "Scale")
        #expect(state.hands == [.right, .left])
        #expect(state.hand == .right)
        #expect(state.focusPath.map(\.steps) == [0...7])
        #expect(state.length == 8)
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

    @Test func cutsAreKeptAndReadAgain() async throws {
        let state = try practising()
        state.toggleCut(before: 4)

        let again = makeState()
        await again.appear()
        #expect(again.piece == state.piece)
        #expect(again.shownRuns.map(\.steps) == [0...3, 4...7])
    }

    /// Pieces kept when they had recordings: the recording, its match and
    /// its nudge points are passed over, and the score plays from its start.
    @Test func aPieceSavedWithARecordingIsReadAsItsScore() async throws {
        let state = try practising()
        state.toggleCut(before: 4)
        let piece = try #require(state.piece)
        let file = folder.appendingPathComponent(piece.id.uuidString).appendingPathComponent("piece.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["recordingFile"] = "recording.m4a"
        var practice = try #require(json["practice"] as? [String: Any])
        practice["anchors"] = [["score": 0, "recording": 47]]
        practice["nudges"] = [47.2]
        practice["unsure"] = [3.5]
        json["practice"] = practice
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let again = makeState()
        await again.appear()
        #expect(again.piece?.id == piece.id)
        #expect(again.shownRuns.map(\.steps) == [0...3, 4...7])
        again.play()
        #expect(player.played.last?.segments == [Segment(start: 0, end: 8)])
        #expect(again.currentTime == 0)
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
        #expect(!state.isPlaying)
        #expect(state.lights(at: 1).isEmpty)
        #expect(state.pieces.map(\.id) == [closed.id])

        // The screen shown again leaves the piano as it was left.
        await state.appear()
        #expect(state.piece == nil)

        await state.open(closed)
        #expect(state.piece?.id == closed.id)
    }

    // MARK: – Runs

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

    @Test func aRunIsWhereTheScoreHasIt() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        #expect(state.shownRuns.map { state.span(of: $0.id) } == [0...4, 4...8])
    }

    // MARK: – Playing

    @Test func withNoRunChosenTheWholeHandPlaysFromTheScoresStart() throws {
        let state = try practising()
        state.play()
        #expect(player.played.last?.segments == [Segment(start: 0, end: 8)])
        #expect(player.played.last?.from == 0)
        #expect(state.isPlaying)
        #expect(state.currentTime == 0)
        // Both hands sound, though only the hand shown is lit.
        #expect(Set(player.played.last?.notes.map(\.hand) ?? []) == [.right, .left])
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

        state.stop()
        state.repeats = false
        state.play()
        #expect(player.played.last?.repeats == false)
    }

    @Test func spacePlaysTheRunsWatchedOrStops() throws {
        let state = try practising()
        state.playOrStop()
        #expect(state.isPlaying)
        state.playOrStop()
        #expect(!state.isPlaying)
    }

    @Test func playGoesOnFromWhereItStopped() throws {
        let state = try practising()
        state.seek(to: 5)
        state.play()
        #expect(player.played.last?.from == 5)
        #expect(state.currentTime == 5)
        player.currentTime = 6.5
        state.stop()
        state.play()
        #expect(state.currentTime == 6.5)
    }

    @Test func aSeekWhilePlayingPlaysOnFromThere() throws {
        let state = try practising()
        state.play()
        state.seek(to: 4)
        #expect(state.isPlaying)
        #expect(state.currentTime == 4)
    }

    @Test func aSeekWhileStoppedStaysStoppedWithinTheScore() throws {
        let state = try practising()
        state.seek(to: 30)
        #expect(!state.isPlaying)
        #expect(state.currentTime == 8)
        #expect(player.played.isEmpty)
        // Stopped, the keys of the hand shown are lit as they are where it stands.
        state.seek(to: 3.5)
        let sounding = state.lights(at: state.currentTime).filter { $0.value.contains { $0.kind != .next } }
        #expect(Set(sounding.keys) == [77])
    }

    @Test func skippingGoesFiveSecondsAndKeepsPlaying() throws {
        let state = try practising()
        state.play()
        state.skip(by: 5)
        #expect(state.isPlaying)
        #expect(state.currentTime == 5)
        state.skip(by: -ScorePracticeState.skipSeconds * 3)
        #expect(state.currentTime == 0)
        state.stop()
        state.skip(by: 5)
        #expect(!state.isPlaying)
        #expect(state.currentTime == 5)
    }

    @Test func playingOnceStopsAtTheEnd() throws {
        let state = try practising()
        state.repeats = false
        state.play()
        player.currentTime = 8
        player.isPlaying = false
        player.onFinish?()
        #expect(!state.isPlaying)
        #expect(state.currentTime == 8)
    }

    @Test func theKeysOfTheRunsWatchedLightAsTheScorePlays() throws {
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

@Suite("ScorePlayer")
@MainActor
struct ScorePlayerTests {

    private let clock = ManualClock()
    private let sink = RecordingNoteSink()
    private var player: ScorePlayer { ScorePlayer(sinks: [sink], clock: clock) }

    /// C, D and E a second each.
    private let notes = [60, 62, 64].enumerated().map {
        ScoreNote(pitch: $1, onset: Double($0), duration: 1, hand: .right)
    }
    private let whole = [Segment(start: 0, end: 3)]

    private func near(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    @Test func eachNoteSoundsOnItsMomentAndPlayEndsAfterTheLast() {
        let player = player
        var finished = false
        player.onFinish = { finished = true }
        player.play(notes, whole, from: 0, repeats: false)
        // Each note is sent ahead of its moment, stamped with it.
        #expect(sink.started == [60])
        clock.advance(seconds: 1)
        #expect(sink.started == [60, 62])
        #expect(abs(player.currentTime - 0.95) < 1e-9)
        clock.advance(seconds: 2.5)
        #expect(sink.started == [60, 62, 64])
        #expect(near(sink.startTimes, [0.05, 1.05, 2.05]))
        #expect(near(sink.endTimes, [1.05, 2.05, 3.05]))
        #expect(sink.sounding.isEmpty)
        #expect(finished)
        #expect(!player.isPlaying)
        #expect(player.currentTime == 3)
    }

    @Test func playBegunInsideANoteSoundsItFromThere() {
        let player = player
        player.play(notes, whole, from: 1.5, repeats: false)
        #expect(sink.started == [62])
        clock.advance(seconds: 1)
        #expect(near(Array(sink.endTimes.prefix(1)), [0.55]))
    }

    @Test func repeatsGoBackToTheFirstSegment() {
        let player = player
        player.play(notes, whole, from: 2, repeats: true)
        clock.advance(seconds: 1.5)
        #expect(sink.started == [64, 60])
        #expect(near(sink.startTimes, [0.05, 1.05]))
        #expect(player.isPlaying)
        #expect(abs(player.currentTime - 0.45) < 1e-9)
    }

    @Test func stoppingLetsGoOfEveryNoteSentEvenOneNotYetHeard() {
        let player = player
        player.play(notes, whole, from: 0, repeats: true)
        player.stop()
        #expect(sink.sounding.isEmpty)
        #expect(near(sink.endTimes, [0.05]))
        clock.advance(seconds: 5)
        #expect(sink.started == [60])
        #expect(!player.isPlaying)
    }
}
