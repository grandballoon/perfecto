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

    /// The keys tapped and held, in the order they were pressed.
    var held: [Int] = []
    func press(_ pitch: Int) { held.append(pitch) }
    func release(_ pitch: Int) { held.removeAll { $0 == pitch } }
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

    /// A run of the hands shown made from step `first` to step `last`, as a
    /// learner makes one: begun at the note at the playhead, taken on a note
    /// at a time, and saved. Its id.
    @discardableResult
    private func addRun(_ state: ScorePracticeState, _ first: Int, _ last: Int) -> RunID? {
        guard let onset = state.score?.steps(state.hands)[first].onset else { return nil }
        state.seek(to: onset)
        state.startNewRun()
        while let draft = state.draft, draft.last < last { state.extendDraftEnd() }
        state.saveDraft()
        return state.selection.first
    }

    private func stepsOfRuns(_ state: ScorePracticeState) -> [ClosedRange<Int>] {
        state.shownRuns.map(\.passage.steps)
    }

    // MARK: – Pieces

    @Test func anImportedScoreIsOpenedOnItsRightHand() throws {
        let state = try practising()
        #expect(state.piece?.title == "Scale")
        #expect(state.handsShown == [.right, .left, .both])
        #expect(state.hands == .right)
        #expect(state.shownRuns.isEmpty)
        #expect(state.watched == [Passage(.right, from: 0, to: 7)])
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
        #expect(state.score!.steps(state.hands).map { $0.notes.map(\.pitch) } == [[72]])
        state.show(.left)
        #expect(state.score!.steps(state.hands).map { $0.notes.map(\.pitch) } == [[48]])
        state.show(.both)
        #expect(state.score!.steps(state.hands).map { $0.notes.map(\.pitch) } == [[48, 72]])
    }

    @Test func whatIsNotAScoreIsRefusedAndSaid() throws {
        let state = makeState()
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).xml")
        try Data("<html/>".utf8).write(to: url)
        state.importScore(from: url)
        #expect(state.piece == nil)
        #expect(state.failure != nil)
    }

    @Test func runsAreKeptAndReadAgain() async throws {
        let state = try practising()
        addRun(state, 4, 7)
        addRun(state, 0, 3)

        let again = makeState()
        await again.appear()
        #expect(again.piece == state.piece)
        #expect(stepsOfRuns(again) == [0...3, 4...7])
    }

    /// Pieces kept when they had recordings: the recording, its match and
    /// its nudge points are passed over, and the score plays from its start.
    @Test func aPieceSavedWithARecordingIsReadAsItsScore() async throws {
        let state = try practising()
        addRun(state, 0, 3)
        addRun(state, 4, 7)
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
        #expect(stepsOfRuns(again) == [0...3, 4...7])
        again.clearSelection()
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

        addRun(phone, 0, 3)
        await mac.libraryChanged()
        #expect(stepsOfRuns(mac) == [0...3])
    }

    @Test func anOlderSaveDoesNotUndoALaterOne() async throws {
        let phone = try practising()
        let mac = makeState()
        await mac.appear()
        addRun(mac, 0, 1)
        // The Mac saved last: the phone takes it up, and the Mac keeps it.
        await phone.libraryChanged()
        #expect(stepsOfRuns(phone) == [0...1])
        await mac.libraryChanged()
        #expect(stepsOfRuns(mac) == [0...1])
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

    @Test func aNewRunIsTheNoteAtThePlayheadMovedAndTakenFurtherThenSaved() throws {
        let state = try practising()
        state.seek(to: 2.5)
        state.startNewRun()
        #expect(state.isEditing)
        #expect(state.editing == nil)
        #expect(state.draft == Passage(.right, from: 2, to: 2))
        // Nothing is kept until it is saved.
        #expect(state.shownRuns.isEmpty)
        state.extendDraftEnd()
        state.extendDraftStart()
        #expect(state.draft == Passage(.right, from: 1, to: 3))
        // Dragged along the score, a step at a time, keeping its length.
        state.moveDraft(toStartAt: 4.3)
        #expect(state.draft == Passage(.right, from: 4, to: 6))
        #expect(state.currentTime == 4)
        state.saveDraft()
        #expect(!state.isEditing)
        #expect(stepsOfRuns(state) == [4...6])
        #expect(state.watched == [Passage(.right, from: 4, to: 6)])
        #expect(state.span(of: state.shownRuns[0]) == 4...7)
    }

    @Test func aRunBeingEditedGivesUpNotesAtEitherEnd() throws {
        let state = try practising()
        let id = try #require(addRun(state, 1, 6))
        state.edit(id)
        state.shrinkDraftStart()
        state.shrinkDraftEnd()
        state.shrinkDraftEnd()
        #expect(state.draft == Passage(.right, from: 2, to: 4))
        // The playhead and the keys follow its start.
        #expect(state.currentTime == 2)
        state.saveDraft()
        #expect(state.practice?.run(id)?.passage == Passage(.right, from: 2, to: 4))
    }

    @Test func aNewRunCalledOffIsNotMade() throws {
        let state = try practising()
        state.startNewRun()
        state.extendDraftEnd()
        state.cancelDraft()
        #expect(state.draft == nil)
        #expect(state.shownRuns.isEmpty)
        #expect(!state.canUndo)
    }

    @Test func aRunIsChangedOnlyInEditingAndSaved() throws {
        let state = try practising()
        let id = try #require(addRun(state, 0, 1))
        state.rename(id, to: "start")
        state.edit(id)
        #expect(state.editing == id)
        #expect(state.draft == Passage(.right, from: 0, to: 1))
        // While it is edited, it is what plays.
        #expect(state.watched == [Passage(.right, from: 0, to: 1)])
        state.moveDraft(toStartAt: 5)
        state.extendDraftEnd()
        #expect(state.practice?.run(id)?.passage == Passage(.right, from: 0, to: 1))
        state.saveDraft()
        #expect(state.practice?.run(id) == PracticeRun(id: id, passage: Passage(.right, from: 5, to: 7), name: "start"))
        #expect(state.shownRuns.count == 1)
        // The edit is one change, undone as one.
        state.undo()
        #expect(state.practice?.run(id)?.passage == Passage(.right, from: 0, to: 1))
    }

    @Test func anEditCalledOffLeavesTheRunAsItWas() throws {
        let state = try practising()
        let id = try #require(addRun(state, 2, 3))
        state.edit(id)
        state.moveDraft(toStartAt: 6)
        state.cancelDraft()
        #expect(state.practice?.run(id)?.passage == Passage(.right, from: 2, to: 3))
        #expect(state.editing == nil)
    }

    @Test func showingOtherHandsCallsOffAnEdit() throws {
        let state = try practising()
        state.startNewRun()
        state.show(.both)
        #expect(!state.isEditing)
        // Editing a run of other hands shows them.
        state.show(.left)
        let left = try #require(addRun(state, 0, 0))
        state.show(.right)
        state.edit(left)
        #expect(state.hands == .left)
        #expect(state.isEditing)
    }

    @Test func runsOverlapAndDeletingOneLeavesTheOthers() throws {
        let state = try practising()
        let whole = try #require(addRun(state, 0, 7))
        addRun(state, 2, 5)
        addRun(state, 4, 6)
        #expect(stepsOfRuns(state) == [0...7, 2...5, 4...6])
        state.delete(whole)
        #expect(stepsOfRuns(state) == [2...5, 4...6])
    }

    @Test func eachViewOfTheScoreHasItsOwnRuns() throws {
        let state = try practising()
        addRun(state, 0, 3)
        state.show(.left)
        #expect(state.hands == .left)
        #expect(state.shownRuns.isEmpty)
        #expect(state.watched == [Passage(.left, from: 0, to: 0)])
        state.show(.both)
        let both = try #require(addRun(state, 2, 6))
        #expect(state.practice?.run(both)?.passage == Passage(.both, from: 2, to: 6))
        #expect(stepsOfRuns(state) == [2...6])
        state.show(.right)
        #expect(stepsOfRuns(state) == [0...3])
        #expect(state.allRuns.map(\.hands) == [.right, .left, .both])
        #expect(state.allRuns.map(\.runs.count) == [1, 0, 1])
    }

    @Test func aRunOfBothHandsLightsBothHandsKeys() throws {
        let state = try practising()
        state.show(.both)
        addRun(state, 0, 1)
        state.play()
        let lights = state.lights(at: 0.5)
        #expect(lights[72] == [KeyLight(hand: .right, kind: .sounding(since: 0.5))])
        #expect(lights[48] == [KeyLight(hand: .left, kind: .sounding(since: 0.5))])
    }

    @Test func everyChangeToTheRunsIsUndoneAndRedone() async throws {
        let state = try practising()
        #expect(!state.canUndo)
        let id = try #require(addRun(state, 0, 3))
        state.rename(id, to: "the climb")
        state.delete(id)
        #expect(state.shownRuns.isEmpty)

        state.undo()
        #expect(state.shownRuns.map(\.name) == ["the climb"])
        state.undo()
        #expect(state.shownRuns.map(\.name) == [nil])
        state.undo()
        #expect(state.shownRuns.isEmpty)
        #expect(!state.canUndo)
        #expect(state.selection.isEmpty)

        state.redo()
        state.redo()
        #expect(state.shownRuns.map(\.name) == ["the climb"])
        #expect(state.canRedo)

        // What is undone or redone is kept, too.
        let again = makeState()
        await again.appear()
        #expect(again.shownRuns.map(\.name) == ["the climb"])
        #expect(!again.canUndo)
    }

    @Test func aRunIsNamedAndGoneToFromTheListOfAllRuns() async throws {
        let state = try practising()
        state.show(.both)
        let id = try #require(addRun(state, 4, 7))
        state.rename(id, to: "  the turn ")
        let run = try #require(state.practice?.run(id))
        #expect(state.title(of: run) == "the turn")
        #expect(state.bars(of: run) == "Bar 2")

        state.show(.right)
        state.goTo(id)
        #expect(state.hands == .both)
        #expect(state.selection == [id])

        // Without a name, a run goes by its bars.
        state.rename(id, to: " ")
        #expect(state.title(of: state.practice!.run(id)!) == "Bar 2")
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
        let late = try #require(addRun(state, 4, 7))
        addRun(state, 0, 1)
        state.toggle(late)
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

    @Test func theKeysShowTheFirstNoteOfTheRunBeingEdited() throws {
        let state = try practising()
        state.seek(to: 2)
        state.startNewRun()
        let sounding = state.lights(at: state.currentTime).filter { $0.value.contains { $0.kind != .next } }
        #expect(sounding.keys.contains(76))
        #expect(piano.span == PianoSpan.fitting(76...76))
    }

    @Test func thePianoIsBroughtToTheRunsWatched() throws {
        let state = try practising()
        addRun(state, 0, 3)
        #expect(piano.span == PianoSpan.fitting(72...77))
        state.show(.left)
        #expect(piano.span == PianoSpan.fitting(48...48))
    }

    // MARK: – Tapping

    /// The keys marked to tap next.
    private func nextKeys(_ state: ScorePracticeState) -> [Int] {
        state.lights(at: state.currentTime).filter { $0.value.contains { $0.kind == .next } }.keys.sorted()
    }

    @Test func aRunIsTappedNoteByNoteEachTapToldRightOrWrong() throws {
        let state = try practising()
        addRun(state, 0, 2)
        state.startTapping()
        #expect(state.isTapping)
        #expect(nextKeys(state) == [72])

        state.press(72)
        #expect(state.lastTap?.outcome == .stepDone)
        #expect(state.drill?.index == 1)
        #expect(state.currentTime == 1)          // the playhead follows the place
        state.press(77)
        #expect(state.lastTap == PracticeTap(pitch: 77, outcome: .wrong, number: 2))
        #expect(state.drill?.index == 1)
        state.press(74)
        state.press(76)
        #expect(state.lastTap?.outcome == .passed(mistakes: 1))
        #expect(state.drill?.index == 0)
    }

    @Test func aTappedKeySoundsUntilItIsLetGo() throws {
        let state = try practising()
        state.startTapping()
        state.press(72)
        state.press(60)                          // wrong notes sound too
        #expect(player.held == [72, 60])
        state.release(72)
        #expect(player.held == [60])
        state.stopTapping()
        #expect(player.held.isEmpty)
        #expect(state.drill == nil)
        // Not tapping, a key pressed sounds nothing and is told nothing.
        state.press(72)
        #expect(player.held.isEmpty)
        #expect(state.lastTap == nil)
    }

    @Test func theNextNoteIsShownOrHiddenAtAnyMomentWithoutLosingThePlace() throws {
        let logger = RecordingLogger()
        let state = ScorePracticeState(piano: piano, library: library, makePlayer: { [player] in player },
                                       logger: logger)
        state.importScore(from: try scoreFile())
        state.startTapping()
        state.press(72)
        state.showsNextNote = false
        #expect(nextKeys(state).isEmpty)
        #expect(state.drill?.index == 1)
        state.press(74)
        #expect(state.lastTap?.outcome == .stepDone)
        state.showsNextNote = true
        #expect(nextKeys(state) == [76])
        #expect(logger.events.contains { if case .practice_tap_hint_switched(isOn: false) = $0 { true } else { false } })
        #expect(logger.events.contains { if case .practice_tapped(pitch: 74, isRight: true) = $0 { true } else { false } })
    }

    @Test func tappingBeginsAtThePlayheadInsideTheRunsAndMovesWithIt() throws {
        let state = try practising()
        state.seek(to: 3.5)
        state.startTapping()
        #expect(state.drill?.current?.pitches == [77])
        state.seek(to: 6)
        #expect(state.drill?.current?.pitches == [83])
        state.restartTapping()
        #expect(state.drill?.current?.pitches == [72])
        #expect(state.currentTime == 0)
    }

    @Test func choosingOtherRunsWhileTappingTapsThoseFromTheirStart() throws {
        let state = try practising()
        let first = addRun(state, 0, 1)!
        let second = addRun(state, 4, 5)!
        state.goTo(first)
        state.startTapping()
        state.press(72)
        state.goTo(second)
        #expect(state.isTapping)
        #expect(state.drill?.steps.map(\.pitches) == [[79], [81]])
        #expect(state.drill?.index == 0)
        #expect(state.lastTap == nil)
        state.show(.left)
        #expect(state.drill?.steps.map(\.pitches) == [[48]])
    }

    @Test func playingTheScoreEndsTapping() throws {
        let state = try practising()
        state.startTapping()
        state.play()
        #expect(!state.isTapping)
        #expect(state.isPlaying)
        state.startTapping()
        #expect(state.isTapping)
        #expect(!state.isPlaying)
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

    @Test func aKeyPressedSoundsAtOnceUntilLetGoAndAgainWhenPressedAgain() {
        let player = player
        player.press(60)
        #expect(sink.started == [60])
        player.press(60)
        #expect(sink.started == [60, 60])
        #expect(sink.endTimes.count == 1)
        player.release(60)
        #expect(sink.sounding.isEmpty)
        player.release(60)
        #expect(sink.endTimes.count == 2)
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
