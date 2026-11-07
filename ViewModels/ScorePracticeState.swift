import Foundation
import Observation

/// Score practice, as the whole-screen piano shows it: a piece's score,
/// runs kept of it (each a stretch of one hand or both, independent of
/// the others), and the runs watched on the piano while the score plays on
/// the app's own sound, once or over again.
///
/// The decisions are the score practice core's (`Practice`, `Playback`);
/// this is the shell around them: it keeps the piece being practised and
/// what is chosen of it, saves the piece on each change, plays the score,
/// and brings the piano to the runs being watched.
@Observable
@MainActor
final class ScorePracticeState {

    private(set) var pieces: [Piece] = []
    private(set) var piece: Piece?
    private(set) var score: Score?

    /// The hands whose runs are shown and whose keys are lit: one alone,
    /// or both together, each a view of the one score.
    private(set) var hands = Hands.right
    /// The runs chosen to watch; with none, the whole piece of the hands
    /// shown is watched.
    private(set) var selection: Set<RunID> = []
    /// Whether the runs watched play over and over.
    var repeats = true
    /// The run being made or edited, as it stands (`RunDraft`); nil when
    /// no run is being edited.
    private(set) var runDraft: RunDraft?
    /// Where the score stands, while it is not playing.
    private(set) var playhead = 0.0
    private(set) var isPlaying = false
    /// What could not be done last, said once.
    var failure: String?

    /// Whether the learner is tapping the runs watched on the keys, note
    /// by note, rather than watching them play.
    private(set) var isTapping = false
    /// Whether, while tapping, the notes to tap next are marked on the
    /// keys. It can be switched at any moment without losing the place, and
    /// is kept while the app runs, not saved.
    var showsNextNote = true {
        didSet {
            guard showsNextNote != oldValue else { return }
            logger?.log(.practice_tap_hint_switched(isOn: showsNextNote))
        }
    }
    /// The steps being tapped and how far the learner has got; nil while
    /// not tapping.
    private(set) var drill: TapDrill?
    /// The last key tapped and what it was, for the screen to say; nil
    /// until a key is tapped.
    private(set) var lastTap: PracticeTap?

    /// The notes lit as the score plays.
    private var litNotes: [TimedNote] = []
    /// The keys pressed while tapping and not yet let go.
    private var held: Set<Int> = []

    private let piano: PianoState
    /// Where the pieces are kept: given, or found when the screen first
    /// appears (`ScoreLibrary.resolve`, iCloud if the device is signed in).
    private var library: ScoreLibrary?
    private var watcher: ScoreLibraryWatcher?
    private let makePlayer: () -> any PracticePlaying
    private var player: (any PracticePlaying)?
    private let logger: (any Logger)?
    /// The changes to the runs of the piece open, to undo and redo; kept
    /// only while it is open.
    private var history = History(Practice())
    /// Whether a piece has been opened or closed by the learner: until
    /// then, the screen appearing opens the latest piece, and after, it
    /// leaves the piano as it was left, with no piece if one was closed.
    private var hasChosen = false
    /// The run whose editing a sub-run was begun from, which is edited
    /// again once the sub-run is saved or called off, so several are made
    /// in a row.
    private var resumesEditing: RunID?

    /// `library` nil: the library is found when the screen first appears.
    /// `makePlayer` makes what plays the score, once one is opened.
    init(piano: PianoState,
         library: ScoreLibrary? = nil,
         makePlayer: @escaping () -> any PracticePlaying,
         logger: (any Logger)? = nil) {
        self.piano = piano
        self.library = library
        self.makePlayer = makePlayer
        self.logger = logger
    }

    // MARK: – Pieces

    /// Whether the pieces are kept in iCloud, shared with the other device.
    var isInCloud: Bool { library?.isInCloud ?? false }

    /// The library found, the pieces read from it, and the latest opened
    /// if none has been opened or closed yet.
    func appear() async {
        if library == nil {
            let found = await Task.detached(priority: .userInitiated) { ScoreLibrary.resolve() }.value
            library = found
            if found.isInCloud {
                watcher = ScoreLibraryWatcher { [weak self] in
                    Task { await self?.libraryChanged() }
                }
            }
        }
        await readPieces()
        if piece == nil, !hasChosen, let latest = pieces.first { await open(latest) }
    }

    /// The pieces read again, off the main thread: reading one that came
    /// from the other device waits for it to download.
    private func readPieces() async {
        guard let library else { return }
        pieces = await Task.detached(priority: .userInitiated) { library.pieces() }.value
    }

    /// Something changed in the library from the other device: the pieces
    /// are read again, and the piece open takes up a later save of it.
    func libraryChanged() async {
        await readPieces()
        guard let open = piece else { return }
        guard let kept = pieces.first(where: { $0.id == open.id }) else {
            close()
            return
        }
        guard (kept.modified ?? .distantPast) > (open.modified ?? .distantPast) else { return }
        piece = kept
        history = History(kept.practice)
        selection = selection.filter { kept.practice.run($0) != nil }
        refresh()
        if isPlaying { play() }
    }

    func importScore(from url: URL) {
        do {
            let (piece, score) = try currentLibrary.importScore(from: url)
            keep(piece)
            show(piece, score)
        } catch {
            failure = "That file is not a MIDI file (.mid) or a MusicXML score (.mxl or .musicxml)."
            logger?.log(.practice_import_failed(reason: String(describing: error)))
        }
    }

    /// The piece opened, its score read.
    func open(_ piece: Piece) async {
        let library = currentLibrary
        do {
            let score = try await Task.detached(priority: .userInitiated) { try library.score(of: piece) }.value
            show(piece, score)
        } catch {
            failure = "“\(piece.title)” could not be read."
            logger?.log(.practice_import_failed(reason: String(describing: error)))
        }
    }

    /// The piece open taken off the piano, leaving the keys alone; it is
    /// kept among the pieces, to be opened again.
    func closePiece() {
        guard piece != nil else { return }
        hasChosen = true
        close()
        logger?.log(.practice_piece_closed)
    }

    func delete(_ piece: Piece) {
        if piece.id == self.piece?.id { close() }
        currentLibrary.delete(piece)
        pieces.removeAll { $0.id == piece.id }
    }

    /// The library, or until one is found, the device's own.
    private var currentLibrary: ScoreLibrary { library ?? .local }

    /// `piece` in the list of pieces as it is now.
    private func keep(_ piece: Piece) {
        pieces = ([piece] + pieces.filter { $0.id != piece.id }).sorted { $0.added > $1.added }
    }

    private func close() {
        stop()
        endTapping()
        piece = nil
        score = nil
        selection = []
        runDraft = nil
        resumesEditing = nil
        history = History(Practice())
        playhead = 0
        litNotes = []
    }

    private func show(_ piece: Piece, _ score: Score) {
        stop()
        hasChosen = true
        self.piece = piece
        self.score = score
        hands = score.hands.first ?? .right
        selection = []
        runDraft = nil
        resumesEditing = nil
        history = History(piece.practice)
        playhead = 0
        refresh()
        fitPiano()
        logger?.log(.practice_piece_opened(title: piece.title, notes: score.notes.count))
    }

    // MARK: – Choosing runs

    var practice: Practice? { piece?.practice }

    /// The views of the score there are: each hand it has, and both
    /// together when it has both.
    var handsShown: [Hands] { score?.hands ?? [] }

    /// The runs of `hands` shown, and the whole piece of them watched.
    func show(_ hands: Hands) {
        guard hands != self.hands, handsShown.contains(hands) else { return }
        stop()
        self.hands = hands
        selection = []
        resumesEditing = nil
        cancelDraft()
        refresh()
        fitPiano()
    }

    /// The run with `id` chosen to watch, or no longer.
    func toggle(_ id: RunID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        stop()
        refresh()
        fitPiano()
    }

    /// No run chosen: the whole piece of the hands shown is watched.
    func clearSelection() {
        selection = []
        stop()
        refresh()
        fitPiano()
    }

    /// The runs of the hands shown, in the order of the score.
    var shownRuns: [PracticeRun] {
        guard let practice, let score else { return [] }
        return practice.runs(of: hands, in: score)
    }

    /// The runs of the hands shown as they are nested: each run of the
    /// score followed by its sub-runs.
    var shownOutline: [OutlinedRun] {
        guard let practice, let score else { return [] }
        return practice.outline(of: hands, in: score)
    }

    /// What is watched: the run being edited, or the runs chosen, or else
    /// the whole piece of the hands shown.
    var watched: [Passage] {
        guard let practice, let score else { return [] }
        if let draft { return [draft] }
        let chosen = practice.runs.filter { selection.contains($0.id) }.map(\.passage)
        return chosen.isEmpty ? (Passage.whole(hands, in: score).map { [$0] } ?? []) : chosen
    }

    /// What a run is called: the name the learner gave it, or else its
    /// bars.
    func title(of run: PracticeRun) -> String {
        run.name ?? bars(of: run)
    }

    /// Where a run is, by its bars: "Bars 5–8".
    func bars(of run: PracticeRun) -> String {
        guard let score else { return "" }
        return score.bars(of: run.passage.span(in: score))
    }

    /// Where a run is in the score, in seconds.
    func span(of run: PracticeRun) -> ClosedRange<Double>? {
        score.map { run.passage.span(in: $0) }
    }

    /// The run with `id` given the name `name`; nothing but spaces takes
    /// its name away.
    func rename(_ id: RunID, to name: String) {
        guard let practice else { return }
        commit(practice.naming(id, name))
        logger?.log(.practice_run_named(isNamed: !name.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    /// The run with `id` taken away; every other run is as it was.
    func delete(_ id: RunID) {
        guard let practice, practice.run(id) != nil else { return }
        commit(practice.removing(id))
        logger?.log(.practice_run_removed)
    }

    /// Every run, nested, by the hands it is of, for each view of the
    /// score: the list of all runs.
    var allRuns: [(hands: Hands, runs: [OutlinedRun])] {
        guard let practice, let score else { return [] }
        return handsShown.map { ($0, practice.outline(of: $0, in: score)) }
    }

    /// The run with `id` gone to from the list of all runs: its hands shown
    /// and it alone chosen to watch.
    func goTo(_ id: RunID) {
        guard let run = practice?.run(id) else { return }
        show(run.passage.hands)
        selection = [id]
        stop()
        refresh()
        fitPiano()
    }

    // MARK: – Undo

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// The last change to the runs or the flags undone: a run added,
    /// deleted or named, or a flag put on, noted or taken away.
    func undo() {
        guard history.canUndo else { return }
        history = history.undoing()
        save(history.present)
        logger?.log(.practice_runs_undone(isRedo: false))
    }

    func redo() {
        guard history.canRedo else { return }
        history = history.redoing()
        save(history.present)
        logger?.log(.practice_runs_undone(isRedo: true))
    }

    // MARK: – Making and editing a run

    var isEditing: Bool { runDraft != nil }
    /// The steps of the run being made or edited, as they stand.
    var draft: Passage? { runDraft?.passage }
    /// The run being edited; nil while a new one is being made.
    var editing: RunID? { runDraft?.run }

    /// A new run of the hands shown begun: the note at the playhead, to
    /// move and take further a note at a time before it is saved.
    func startNewRun() {
        guard let score, let next = (practice ?? Practice()).newRun(hands, at: currentTime, in: score) else { return }
        resumesEditing = nil
        show(draft: next)
    }

    /// Whether a sub-run can be begun from the run being edited: it is a
    /// run kept, and as it was, so nothing unsaved is left behind.
    var canStartSubRun: Bool {
        guard let runDraft, let id = runDraft.run else { return false }
        return runDraft.moved == 0 && runDraft.passage == practice?.run(id)?.passage
    }

    /// A sub-run of the run with `id` begun, its hands shown: the note of
    /// it nearest the playhead, to move within it and take further before
    /// it is saved. Begun from that run's editing, it goes back to editing
    /// that run once it is saved or called off.
    func startSubRun(of id: RunID) {
        guard let run = practice?.run(id) else { return }
        let fromEditing = editing == id
        if !fromEditing { show(run.passage.hands) }
        guard let score, let next = practice?.newRun(hands, at: currentTime, in: score, under: id) else { return }
        resumesEditing = fromEditing ? id : nil
        selection = [id]
        show(draft: next)
    }

    /// The run with `id` put into editing, its hands shown.
    func edit(_ id: RunID) {
        guard let run = practice?.run(id) else { return }
        show(run.passage.hands)
        guard let score, let next = practice?.editing(id, in: score) else { return }
        resumesEditing = nil
        selection = [id]
        show(draft: next)
    }

    /// The run being edited moved along the score, keeping its length, to
    /// begin with the step struck at `time`.
    func moveDraft(toStartAt time: Double) {
        guard let score, let runDraft else { return }
        let moved = runDraft.moved(toStartAt: time, in: score)
        if moved != runDraft { show(draft: moved) }
    }

    /// One more note before the run being edited.
    func extendDraftStart() { change { $0.extendingStart() } }

    /// One more note after the run being edited.
    func extendDraftEnd() { change { $0.extendingEnd() } }

    /// One note fewer at the start of the run being edited, down to one.
    func shrinkDraftStart() { change { $0.shrinkingStart() } }

    /// One note fewer at the end of the run being edited, down to one.
    func shrinkDraftEnd() { change { $0.shrinkingEnd() } }

    private func change(_ edit: (RunDraft) -> RunDraft) {
        guard let runDraft else { return }
        let next = edit(runDraft)
        if next != runDraft { show(draft: next) }
    }

    /// The run being edited kept: a new run added, or the run edited
    /// changed, as one change that can be undone; it is chosen to watch,
    /// or the run a sub-run was begun from is edited again.
    func saveDraft() {
        guard let practice, let runDraft else { return }
        let (next, id) = practice.keeping(runDraft)
        commit(next)
        let steps = runDraft.passage.steps.count
        if runDraft.run == nil {
            logger?.log(.practice_run_added(hands: runDraft.passage.hands.rawValue, steps: steps,
                                            isSubRun: runDraft.parent != nil))
        } else {
            logger?.log(.practice_run_edited(steps: steps))
        }
        self.runDraft = nil
        if let parent = resumesEditing {
            edit(parent)
            return
        }
        selection = [id]
        refresh()
        fitPiano()
    }

    /// The run being edited left as it was, or the new one not made; the
    /// run a sub-run was begun from is edited again.
    func cancelDraft() {
        guard runDraft != nil else { return }
        stop()
        runDraft = nil
        if let parent = resumesEditing {
            edit(parent)
            return
        }
        refresh()
        fitPiano()
    }

    /// `next` the run being edited, the playhead at its start so the keys
    /// show its first step, and the piano brought to it.
    private func show(draft next: RunDraft) {
        guard let score else { return }
        stop()
        runDraft = next
        playhead = next.passage.span(in: score).lowerBound
        refresh()
        fitPiano()
    }

    /// `next` made the practice, as a change that can be undone, and saved.
    private func commit(_ next: Practice) {
        guard next != practice else { return }
        history = history.doing(next)
        save(next)
    }

    /// `practice` made the practice of the piece open, and saved.
    private func save(_ practice: Practice) {
        guard var piece, practice != piece.practice else { return }
        piece.practice = practice
        self.piece = piece
        if let saved = try? currentLibrary.save(piece) {
            self.piece = saved
            keep(saved)
        }
        selection = selection.filter { practice.run($0) != nil }
        refresh()
        if isPlaying { play() }
    }

    // MARK: – Playing

    /// How long the score is, in seconds.
    var length: Double? { score?.barlines.last }

    /// The moment of the score heard, or where it stands.
    var currentTime: Double {
        if isPlaying, let player, player.isPlaying { return player.currentTime }
        return playhead
    }

    /// The runs watched, played on from where the playhead stands if that
    /// is inside them, and otherwise from the next of them
    /// (`Playback.start`), with both hands sounding and the runs' keys lit.
    func play() {
        guard let score else { return }
        // Listening is not tapping: the place is let go.
        if isTapping { stopTapping() }
        let segments = Playback.segments(watched, score)
        guard !segments.isEmpty else { return }
        let from = currentTime
        stopPlayer()
        litNotes = Playback.notes(of: watched, score)
        let player = player ?? makePlayer()
        self.player = player
        player.onFinish = { [weak self] in self?.finished() }
        player.play(score.notes, segments, from: from, repeats: repeats)
        isPlaying = true
        logger?.log(.practice_playback_started(segments: segments.count, repeats: repeats))
    }

    /// What the space bar does: the runs watched played, or stopped.
    func playOrStop() {
        if isPlaying { stop() } else { play() }
    }

    func stop() {
        guard isPlaying else { return }
        stopPlayer()
        refresh()
        logger?.log(.practice_playback_stopped)
    }

    private func stopPlayer() {
        guard isPlaying else { return }
        playhead = currentTime
        player?.stop()
        isPlaying = false
    }

    /// The playhead brought to `time` seconds, and played on from there if
    /// it was playing: a tap on the score's bar, or a skip.
    func seek(to time: Double) {
        let was = isPlaying
        stopPlayer()
        playhead = time.clamped(to: 0...(length ?? 0))
        if let drill, isTapping {
            self.drill = drill.moved(to: playhead)
            lastTap = nil
            followDrill()
        }
        if was { play() } else { refresh() }
    }

    /// The playhead brought `seconds` later, or earlier: the skip buttons.
    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// How far the skip buttons go.
    static let skipSeconds = 5.0

    private func finished() {
        guard isPlaying else { return }
        playhead = player?.currentTime ?? playhead
        isPlaying = false
        refresh()
        logger?.log(.practice_playback_stopped)
    }

    /// The keys lit at `time` seconds of the score, by the notes of what is
    /// watched as it plays, or of the hands shown while nothing does.
    /// While tapping, the keys lit are the drill's instead
    /// (`TapDrill.lights`).
    func lights(at time: Double) -> [Int: [KeyLight]] {
        if isTapping { return drill?.lights(showingNext: showsNextNote) ?? [:] }
        return Playback.lights(at: time, litNotes)
    }

    /// The notes to light while nothing plays: all of the hands shown, so
    /// the keys are right at any moment the playhead stands at. While
    /// tapping, the drill is made again if what is watched has changed.
    private func refresh() {
        syncDrill()
        guard !isPlaying, let score, let whole = Passage.whole(hands, in: score) else { return }
        litNotes = Playback.notes(of: [whole], score)
    }

    // MARK: – Stepping

    /// Whether there is a step of the hands shown after the playhead, or
    /// before it, to step to. Not while tapping, which goes note by note
    /// itself.
    var canStepOn: Bool { !isTapping && score?.step(hands, after: currentTime) != nil }
    var canStepBack: Bool { !isTapping && score?.step(hands, before: currentTime) != nil }

    /// The playhead brought to the next step of the hands shown, and the
    /// step heard: the score walked through a note at a time.
    func stepOn() {
        guard !isTapping, let score, let next = score.step(hands, after: currentTime) else { return }
        step(to: score.steps(hands)[next], isForward: true)
    }

    /// The playhead brought to the step of the hands shown before it, and
    /// the step heard.
    func stepBack() {
        guard !isTapping, let score, let previous = score.step(hands, before: currentTime) else { return }
        step(to: score.steps(hands)[previous], isForward: false)
    }

    private func step(to step: Step, isForward: Bool) {
        stop()
        playhead = step.onset
        refresh()
        let player = player ?? makePlayer()
        self.player = player
        player.sound(step.sounded)
        logger?.log(.practice_stepped(isForward: isForward))
    }

    // MARK: – Flags

    /// Every flag on the score, in its order, whichever view it was put on in.
    var flags: [ScoreFlag] { practice?.flags.all ?? [] }

    func flag(_ id: FlagID) -> ScoreFlag? { practice?.flags.flag(id) }

    /// The flags at the step of the hands shown where the playhead stands
    /// at `time`.
    func flags(at time: Double) -> [ScoreFlag] {
        guard let practice, let score else { return [] }
        return practice.flags.at(time, hands, in: score)
    }

    /// The flag of the hands shown that the playhead stands on at `time`,
    /// if there is one: a flag put on there now is that flag.
    func ownFlag(at time: Double) -> ScoreFlag? {
        flags(at: time).first { $0.hands == hands }
    }

    /// A flag put on the score at `time`, in the view of the hands shown,
    /// with `note` (nothing but spaces is no note), as a change that can be
    /// undone; its id. Playing goes on.
    @discardableResult
    func addFlag(at time: Double, note: String = "") -> FlagID? {
        guard let practice, score != nil else { return nil }
        let (flags, id) = practice.flags.adding(at: time, hands, note: note)
        guard flags != practice.flags else { return id }
        commit(practice.with(flags))
        logger?.log(.practice_flag_added(hands: hands.rawValue,
                                         hasNote: flags.flag(id)?.note != nil))
        return id
    }

    /// The flag with `id` given the note `note`; nothing but spaces takes
    /// its note away.
    func note(_ id: FlagID, _ note: String) {
        guard let practice, practice.flags.flag(id) != nil else { return }
        let flags = practice.flags.noting(id, note)
        guard flags != practice.flags else { return }
        commit(practice.with(flags))
        logger?.log(.practice_flag_noted(hasNote: flags.flag(id)?.note != nil))
    }

    func deleteFlag(_ id: FlagID) {
        guard let practice, practice.flags.flag(id) != nil else { return }
        commit(practice.with(practice.flags.removing(id)))
        logger?.log(.practice_flag_removed)
    }

    /// The playhead brought to the flag with `id`.
    func goTo(flag id: FlagID) {
        guard let flag = flag(id) else { return }
        seek(to: flag.time)
    }

    /// The flags the run being made or edited begins and ends on, as it
    /// stands; nil when no run is being edited.
    var draftEdgeFlags: RunEdgeFlags? {
        guard let practice, let score, let draft else { return nil }
        return practice.flags.edges(of: draft, in: score)
    }

    /// Where a flag is, by its bar: "Bar 5".
    func bar(of flag: ScoreFlag) -> String {
        score.map { "Bar \($0.bar(at: flag.time))" } ?? ""
    }

    // MARK: – Tapping

    /// Tapping the runs watched begun, or ended: what the tap button does.
    func toggleTapping() {
        if isTapping { stopTapping() } else { startTapping() }
    }

    /// The runs watched to be tapped on the keys, from the step at the
    /// playhead if it is inside them, and otherwise from their first. The
    /// score stops playing.
    func startTapping() {
        guard !isTapping, let score else { return }
        stop()
        let drill = TapDrill(watched, in: score)
        guard !drill.isEmpty else { return }
        isTapping = true
        let isInside = Playback.segments(watched, score).contains {
            playhead >= $0.start && playhead < $0.end - Playback.nearEnd
        }
        self.drill = isInside ? drill.moved(to: playhead) : drill
        lastTap = nil
        followDrill()
        logger?.log(.practice_tapping_switched(isOn: true))
    }

    func stopTapping() {
        guard isTapping else { return }
        endTapping()
        logger?.log(.practice_tapping_switched(isOn: false))
    }

    /// The drill begun again from its first step.
    func restartTapping() {
        guard let drill, isTapping else { return }
        self.drill = drill.restarted()
        lastTap = nil
        followDrill()
    }

    /// A key of the piano pressed while tapping: it sounds, and is told
    /// right or wrong against the step to tap.
    func press(_ pitch: Int) {
        guard isTapping, let drill else { return }
        let player = player ?? makePlayer()
        self.player = player
        player.press(pitch)
        held.insert(pitch)
        let (next, outcome) = drill.tapping(pitch)
        self.drill = next
        lastTap = PracticeTap(pitch: pitch, outcome: outcome, number: (lastTap?.number ?? 0) + 1)
        followDrill()
        logger?.log(.practice_tapped(pitch: pitch, isRight: outcome.isRight))
        if case let .passed(mistakes) = outcome {
            logger?.log(.practice_tap_pass_finished(steps: drill.steps.count, mistakes: mistakes))
        }
    }

    /// A key pressed while tapping let go: it stops sounding.
    func release(_ pitch: Int) {
        guard held.remove(pitch) != nil else { return }
        player?.release(pitch)
    }

    /// Tapping ended with nothing logged: the piece closed.
    private func endTapping() {
        held.forEach { player?.release($0) }
        held = []
        isTapping = false
        drill = nil
        lastTap = nil
    }

    /// The drill made again from what is watched, if that has changed:
    /// another run chosen, the hands shown changed, or the run edited.
    private func syncDrill() {
        guard isTapping, let score else { return }
        let next = TapDrill(watched, in: score)
        guard next.steps != drill?.steps else { return }
        guard !next.isEmpty else {
            stopTapping()
            return
        }
        drill = next
        lastTap = nil
        followDrill()
    }

    /// The playhead brought to the step to tap, so the score's bar shows
    /// how far the learner has got.
    private func followDrill() {
        if let onset = drill?.current?.onset { playhead = onset }
    }

    /// The piano brought to the notes of what is watched.
    func fitPiano() {
        guard let score, let pitches = Playback.pitches(of: watched, score) else { return }
        piano.span = PianoSpan.fitting(pitches)
    }
}

/// A key tapped while practising by touch, and what it was: the
/// `number`th tap, so a key tapped twice the same way is told twice.
struct PracticeTap: Equatable {
    let pitch: Int
    let outcome: TapOutcome
    let number: Int
}

extension Hands {
    var name: String {
        switch self {
        case .right: return "Right hand"
        case .left:  return "Left hand"
        case .both:  return "Both hands"
        }
    }

    /// As a chit says it.
    var short: String {
        switch self {
        case .right: return "RH"
        case .left:  return "LH"
        case .both:  return "Both"
        }
    }
}
