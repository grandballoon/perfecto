import Foundation
import Observation

/// Score practice, as the whole-screen piano shows it: a piece's score
/// diced into runs of each hand, and the runs watched on the piano while
/// the score plays on the app's own sound, once or over again.
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

    /// The hand whose runs are shown.
    private(set) var hand = Hand.right
    /// The run whose runs are shown, to choose and to cut.
    private(set) var focus: RunID?
    /// The runs chosen to watch; with none, the run in focus is watched.
    private(set) var selection: Set<RunID> = []
    /// Whether the runs watched play over and over.
    var repeats = true
    /// Whether the steps of the run in focus are shown, to cut it by.
    var isCutting = false
    /// The step of the hand shown that is chosen among the steps while
    /// cutting. It is lit on the piano while the playhead stands at it.
    private(set) var selectedStep: Int?
    /// Where the score stands, while it is not playing.
    private(set) var playhead = 0.0
    private(set) var isPlaying = false
    /// What could not be done last, said once.
    var failure: String?

    /// The notes lit as the score plays.
    private var litNotes: [TimedNote] = []

    private let piano: PianoState
    /// Where the pieces are kept: given, or found when the screen first
    /// appears (`ScoreLibrary.resolve`, iCloud if the device is signed in).
    private var library: ScoreLibrary?
    private var watcher: ScoreLibraryWatcher?
    private let makePlayer: () -> any PracticePlaying
    private var player: (any PracticePlaying)?
    private let logger: (any Logger)?
    /// Whether a piece has been opened or closed by the learner: until
    /// then, the screen appearing opens the latest piece, and after, it
    /// leaves the piano as it was left, with no piece if one was closed.
    private var hasChosen = false

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
        selection = selection.filter { kept.practice.find($0) != nil }
        if let focus, kept.practice.find(focus) == nil { self.focus = kept.practice.root(hand)?.id }
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
        piece = nil
        score = nil
        focus = nil
        selection = []
        selectedStep = nil
        playhead = 0
        litNotes = []
    }

    private func show(_ piece: Piece, _ score: Score) {
        stop()
        hasChosen = true
        self.piece = piece
        self.score = score
        hand = piece.practice.root(.right) == nil ? .left : .right
        focus = piece.practice.root(hand)?.id
        selection = []
        selectedStep = nil
        playhead = 0
        refresh()
        fitPiano()
        logger?.log(.practice_piece_opened(title: piece.title, notes: score.notes.count))
    }

    // MARK: – Choosing runs

    var practice: Practice? { piece?.practice }

    /// The hands the score has.
    var hands: [Hand] {
        Hand.allCases.filter { practice?.root($0) != nil }
    }

    func show(_ hand: Hand) {
        guard hand != self.hand, let root = practice?.root(hand) else { return }
        stop()
        self.hand = hand
        focus = root.id
        selection = []
        selectedStep = nil
        refresh()
        fitPiano()
    }

    /// The run with `id` brought into focus, its runs shown.
    func focus(on id: RunID) {
        guard practice?.find(id) != nil else { return }
        stop()
        focus = id
        selection = selection.filter { id != $0 && isInFocus($0) }
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

    func clearSelection() {
        selection = []
        stop()
        refresh()
        fitPiano()
    }

    /// The runs watched: those chosen, or the run in focus.
    var watched: [RunID] {
        selection.isEmpty ? (focus.map { [$0] } ?? []) : selection.sorted()
    }

    /// The run in focus and the runs above it, from the hand's whole part.
    var focusPath: [Run] {
        focus.map { practice?.path(to: $0) ?? [] } ?? []
    }

    /// The runs of the run in focus, or the run itself if it has none.
    var shownRuns: [Run] {
        guard let run = focusPath.last else { return [] }
        return run.isLeaf ? [run] : run.children
    }

    /// What a run is called: the name the learner gave it, or else its
    /// place (`label`).
    func title(of id: RunID) -> String {
        practice?.find(id)?.run.name ?? label(of: id)
    }

    /// The run with `id` given the name `name`; nothing but spaces takes
    /// its name away.
    func rename(_ id: RunID, to name: String) {
        guard let practice else { return }
        commit(practice.naming(id, name))
        logger?.log(.practice_run_named(isNamed: !name.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    /// Every run of every hand, the outline the list of all runs shows.
    var allRuns: [(hand: Hand, runs: [(run: Run, depth: Int)])] {
        guard let practice else { return [] }
        return hands.map { ($0, practice.outline($0)) }
    }

    /// The run with `id` gone to from the list of all runs: its hand shown,
    /// the run it is one of in focus, and it chosen to watch; a hand's whole
    /// part is brought into focus itself.
    func goTo(_ id: RunID) {
        guard let practice, let found = practice.find(id) else { return }
        if found.hand != hand { show(found.hand) }
        let path = practice.path(to: id)
        if path.count > 1 {
            focus(on: path[path.count - 2].id)
            selection = [id]
            refresh()
            fitPiano()
        } else {
            focus(on: id)
        }
    }

    /// A run's place: its place among its run's runs at each depth, "2.3",
    /// or the hand's for its whole part.
    func label(of id: RunID) -> String {
        guard let practice else { return "" }
        let path = practice.path(to: id)
        guard path.count > 1 else { return practice.find(id)?.hand.name ?? "" }
        return zip(path, path.dropFirst())
            .map { parent, child in String((parent.children.firstIndex { $0.id == child.id } ?? 0) + 1) }
            .joined(separator: ".")
    }

    /// Where the run with `id` is in the score, in seconds.
    func span(of id: RunID) -> ClosedRange<Double>? {
        guard let practice, let score else { return nil }
        return practice.span(of: id, in: score)
    }

    private func isInFocus(_ id: RunID) -> Bool {
        guard let focus else { return false }
        return practice?.path(to: id).contains { $0.id == focus } ?? false
    }

    // MARK: – Cutting

    /// The steps of the run in focus.
    var focusSteps: [(index: Int, step: Step)] {
        guard let score, let run = focusPath.last else { return [] }
        let steps = score.steps(hand)
        return run.steps.filter { $0 < steps.count }.map { ($0, steps[$0]) }
    }

    /// Where the run in focus is cut into its runs.
    var focusCuts: Set<Int> {
        guard let focus, let practice else { return [] }
        return Set(practice.cuts(of: focus))
    }

    /// The run in focus cut before step `step`, or the cut there taken
    /// away.
    func toggleCut(before step: Int) {
        guard let focus, let practice else { return }
        let isCut = practice.cuts(of: focus).contains(step)
        commit(isCut ? practice.joining(focus, before: step) : practice.cutting(focus, before: step))
        logger?.log(.practice_run_cut(step: step, isCut: !isCut))
    }

    /// Step `step` of the hand shown chosen: play stopped, and the playhead
    /// standing at it, its keys lit.
    func select(_ step: Int) {
        guard let onset = score?.steps(hand)[safe: step]?.onset else { return }
        stop()
        selectedStep = step
        playhead = onset
    }

    /// `next` made the practice, and saved.
    private func commit(_ next: Practice) {
        guard var piece, next != piece.practice else { return }
        piece.practice = next
        self.piece = piece
        if let saved = try? currentLibrary.save(piece) {
            self.piece = saved
            keep(saved)
        }
        selection = selection.filter { next.find($0) != nil }
        if let focus, next.find(focus) == nil { self.focus = next.root(hand)?.id }
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
        guard let practice, let score else { return }
        let segments = Playback.segments(watched, practice, score)
        guard !segments.isEmpty else { return }
        let from = currentTime
        stopPlayer()
        litNotes = Playback.notes(of: watched, practice, score)
        let player = player ?? makePlayer()
        self.player = player
        player.onFinish = { [weak self] in self?.finished() }
        player.play(score.notes, segments, from: from, repeats: repeats)
        isPlaying = true
        selectedStep = nil
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
        selectedStep = nil
        playhead = time.clamped(to: 0...(length ?? 0))
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

    /// The keys lit at `time` seconds of the score: the step chosen while
    /// the playhead stands at it, or else the notes of the runs watched.
    func lights(at time: Double) -> [Int: [KeyLight]] {
        if !isPlaying, let selectedStep, let step = score?.steps(hand)[safe: selectedStep],
           abs(time - step.onset) < Score.sameTime {
            return Playback.lights(of: step, hand)
        }
        return Playback.lights(at: time, litNotes)
    }

    /// The notes to light while nothing plays: all of the hand shown, so
    /// the keys are right at any moment the playhead stands at.
    private func refresh() {
        guard !isPlaying, let practice, let score, let root = practice.root(hand) else { return }
        litNotes = Playback.notes(of: [root.id], practice, score)
    }

    /// The piano brought to the notes of the runs watched.
    func fitPiano() {
        guard let practice, let score,
              let pitches = Playback.pitches(of: watched, practice, score) else { return }
        piano.span = PianoSpan.fitting(pitches)
    }
}

extension Hand {
    var name: String {
        switch self {
        case .right: return "Right hand"
        case .left:  return "Left hand"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
