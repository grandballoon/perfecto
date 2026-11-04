import Foundation
import Testing
@testable import Perfecto

/// A recording player that plays nothing and says what it was asked.
@MainActor
private final class FakeRecordingPlayer: RecordingPlaying {
    var length = 20.0
    var played: [(segments: [Segment], repeats: Bool)] = []
    var isPlaying = false
    var currentTime = 0.0
    var onFinish: (() -> Void)?

    func load(_ url: URL) throws -> Double { length }

    func play(_ segments: [Segment], repeats: Bool) {
        played.append((segments, repeats))
        isPlaying = true
        currentTime = segments[0].start
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

    private func makeState() -> ScorePracticeState {
        ScorePracticeState(piano: piano, library: library, makePlayer: { [player] in player })
    }

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
        state.seek(to: 3)
        state.markStart()

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
        state.preview(2)
        #expect(Set(state.lights(at: 0).keys) == [76])
        #expect(state.currentTime == 2)
    }

    @Test func matchingTheRunInFocusMovesItsRuns() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        state.seek(to: 2)
        state.markStart()
        state.seek(to: 18)
        state.markEnd()
        #expect(state.span(of: state.shownRuns[1].id) == 10...18)
    }

    @Test func anEdgeDraggedMovesTheRunsEitherSide() throws {
        let state = try practising()
        state.toggleCut(before: 4)
        #expect(state.shownEdges == [0, 4, 8])
        state.move(edgeAt: 4, to: 6, isDone: true)
        #expect(state.span(of: state.shownRuns[0].id) == 0...6)
        #expect(state.span(of: state.shownRuns[1].id)?.lowerBound == 6)
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
