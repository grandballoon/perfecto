import Foundation
import Observation

/// Score practice, as the whole-screen piano shows it: a piece's score
/// diced into runs of each hand, matched to its recording, and the runs
/// watched on the piano while the recording plays, once or over again.
///
/// The decisions are the score practice core's (`Practice`, `Playback`);
/// this is the shell around them: it keeps the piece being practised and
/// what is chosen of it, saves the piece on each change, plays the
/// recording, and brings the piano to the runs being watched.
@Observable
@MainActor
final class ScorePracticeState {

    /// What the recording is playing: the runs being watched, or all of the
    /// hand from a moment of it on, to listen for where a run begins.
    enum Listening: Equatable {
        case runs
        case free
    }

    private(set) var pieces: [Piece] = []
    private(set) var piece: Piece?
    private(set) var score: Score?
    /// The recording's length in seconds, and its loudness, `peaksPerSecond`
    /// peaks to a second (empty until it has been read).
    private(set) var recordingLength: Double?
    private(set) var peaks: [Float] = []
    static let peaksPerSecond = 50

    /// The hand whose runs are shown.
    private(set) var hand = Hand.right
    /// The run whose runs are shown, to choose and to cut.
    private(set) var focus: RunID?
    /// The runs chosen to watch; with none, the run in focus is watched.
    private(set) var selection: Set<RunID> = []
    /// Whether the runs watched play over and over.
    var repeats = true
    /// Whether the steps of the run in focus are shown, to cut it by.
    var isCutting = false {
        didSet { if !isCutting { previewStep = nil } }
    }
    /// The step of the run in focus being looked at, lit on the piano.
    private(set) var previewStep: Int?
    /// Where the recording is, while it is not playing.
    private(set) var playhead = 0.0
    private(set) var listening: Listening?
    /// Whether the recording is being dragged (`scrub`).
    private(set) var isScrubbing = false
    /// The stretch of the recording the strip shows when it is brought to
    /// a nudge point, in place of the run in focus; nil for the run.
    var zoom: ClosedRange<Double>?
    /// What was playing when the drag began, played on when it ends.
    private var resumesAfterScrub: Listening?
    /// What could not be done last, said once.
    var failure: String?

    /// The notes lit as the recording plays.
    private var litNotes: [TimedNote] = []

    private let piano: PianoState
    /// Where the pieces are kept: given, or found when the screen first
    /// appears (`ScoreLibrary.resolve`, iCloud if the device is signed in).
    private var library: ScoreLibrary?
    private var watcher: ScoreLibraryWatcher?
    private let makePlayer: () -> any RecordingPlaying
    private var player: (any RecordingPlaying)?
    private let analyze: @Sendable (URL) -> RecordingFeatures?
    /// What the open recording sounds like, once it has been listened to;
    /// kept to match it again whenever the pins change.
    private var features: RecordingFeatures?
    private var matching: Task<Void, Never>?
    /// Whether the recording is being listened to or matched.
    private(set) var isMatching = false
    private let logger: (any Logger)?

    /// `library` nil: the library is found when the screen first appears.
    /// `analyze` hears a recording, for matching it to its score.
    init(piano: PianoState,
         library: ScoreLibrary? = nil,
         makePlayer: @escaping () -> any RecordingPlaying = { RecordingPlayer() },
         analyze: @escaping @Sendable (URL) -> RecordingFeatures? = RecordingPlayer.features(of:),
         logger: (any Logger)? = nil) {
        self.piano = piano
        self.library = library
        self.makePlayer = makePlayer
        self.analyze = analyze
        self.logger = logger
    }

    // MARK: – Pieces

    /// Whether the pieces are kept in iCloud, shared with the other device.
    var isInCloud: Bool { library?.isInCloud ?? false }

    /// The library found, the pieces read from it, and the latest opened
    /// if none is.
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
        if piece == nil, let latest = pieces.first { await open(latest) }
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
        let recordingChanged = kept.recordingFile != open.recordingFile
        piece = kept
        selection = selection.filter { kept.practice.find($0) != nil }
        if let focus, kept.practice.find(focus) == nil { self.focus = kept.practice.root(hand)?.id }
        if recordingChanged {
            await loadDownloadedRecording()
        } else {
            refresh()
            if listening == .runs { play() }
        }
    }

    func importScore(from url: URL) {
        do {
            let (piece, score) = try currentLibrary.importScore(from: url)
            keep(piece)
            show(piece, score)
        } catch {
            fail("That file is not a MusicXML score (.mxl or .musicxml) or a MIDI file (.mid).", error)
        }
    }

    func importRecording(from url: URL) {
        guard let piece else { return }
        do {
            var next = try currentLibrary.importRecording(from: url, into: piece)
            // What was matched and tagged was of the recording it replaces.
            next.practice = next.practice.clearingRecording()
            next = (try? currentLibrary.save(next)) ?? next
            self.piece = next
            keep(next)
            loadRecording(at: currentLibrary.recordingURL(of: next))
            if let recordingLength { logger?.log(.practice_recording_added(duration: recordingLength)) }
        } catch {
            fail("That file could not be read as a recording.", error)
        }
    }

    /// The piece opened: its score read, and its recording downloaded if
    /// it is not on this device yet.
    func open(_ piece: Piece) async {
        let library = currentLibrary
        do {
            let score = try await Task.detached(priority: .userInitiated) { try library.score(of: piece) }.value
            show(piece, score)
            await loadDownloadedRecording()
        } catch {
            fail("“\(piece.title)” could not be read.", error)
        }
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
        recordingLength = nil
        peaks = []
        features = nil
        zoom = nil
        focus = nil
        selection = []
        litNotes = []
    }

    private func show(_ piece: Piece, _ score: Score) {
        stop()
        self.piece = piece
        self.score = score
        hand = piece.practice.root(.right) == nil ? .left : .right
        focus = piece.practice.root(hand)?.id
        selection = []
        previewStep = nil
        zoom = nil
        playhead = 0
        loadRecording(at: nil)
        refresh()
        fitPiano()
        logger?.log(.practice_piece_opened(title: piece.title, notes: score.notes.count))
    }

    /// The open piece's recording loaded, once it is on this device.
    private func loadDownloadedRecording() async {
        guard let piece else { return }
        let library = currentLibrary
        let url = await Task.detached(priority: .userInitiated) { library.downloadedRecording(of: piece) }.value
        guard self.piece?.id == piece.id else { return }
        loadRecording(at: url)
    }

    /// The recording at `url` made the one played; with none, there is none.
    private func loadRecording(at url: URL?) {
        stop()
        recordingLength = nil
        peaks = []
        features = nil
        matching?.cancel()
        isMatching = false
        guard let piece, let url else { return }
        do {
            let player = player ?? makePlayer()
            self.player = player
            player.onFinish = { [weak self] in self?.finished() }
            recordingLength = try player.load(url)
        } catch {
            fail("The recording could not be played.", error)
            return
        }
        let id = piece.id
        let perSecond = Self.peaksPerSecond
        Task.detached(priority: .userInitiated) {
            let peaks = RecordingPlayer.peaks(of: url, perSecond: perSecond)
            await MainActor.run { [weak self] in
                if self?.piece?.id == id { self?.peaks = peaks }
            }
        }
        listen(to: url, of: id)
    }

    // MARK: – Matching by ear

    /// The recording at `url` heard, and matched to the score if it has
    /// not been yet.
    private func listen(to url: URL, of id: UUID) {
        let analyze = analyze
        isMatching = true
        matching = Task { [weak self] in
            let heard = await Task.detached(priority: .userInitiated) { analyze(url) }.value
            guard let self, !Task.isCancelled, self.piece?.id == id else { return }
            self.features = heard
            if heard != nil, self.practice?.matched.isEmpty == true {
                await self.runMatch()
            } else {
                self.isMatching = false
            }
        }
    }

    /// The recording matched again around the pins as they are now, after
    /// a pin is set or taken away. Nothing if it has not been heard yet:
    /// it is matched as soon as it has.
    func matchAgain() {
        guard features != nil else { return }
        matching?.cancel()
        isMatching = true
        matching = Task { [weak self] in await self?.runMatch() }
    }

    /// The pins cleared and the recording matched again by ear alone.
    func clearPinsAndMatch() {
        guard let practice else { return }
        commit(practice.clearingAnchors())
        matchAgain()
    }

    /// Waits for the match being made, if one is (for tests).
    func matchMade() async {
        await matching?.value
    }

    private func runMatch() async {
        guard let piece, let score, let features else { isMatching = false; return }
        let pins = piece.practice.anchors
        let started = Date.now
        let result = await Task.detached(priority: .userInitiated) {
            AutoMatch.match(score, features, pins: pins)
        }.value
        guard !Task.isCancelled else { return }
        isMatching = false
        // A pin set meanwhile is matched around next.
        guard let practice = self.piece?.practice, self.piece?.id == piece.id, practice.anchors == pins else { return }
        commit(practice.matching(result), rematching: false)
        logger?.log(.practice_matched(anchors: result.anchors.count, unsure: result.unsure.count,
                                      seconds: Date.now.timeIntervalSince(started)))
    }

    private func fail(_ message: String, _ error: any Error) {
        failure = message
        logger?.log(.practice_import_failed(reason: String(describing: error)))
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
        previewStep = nil
        zoom = nil
        refresh()
        fitPiano()
    }

    /// The run with `id` brought into focus, its runs shown.
    func focus(on id: RunID) {
        guard practice?.find(id) != nil else { return }
        stop()
        focus = id
        selection = selection.filter { id != $0 && isInFocus($0) }
        previewStep = nil
        zoom = nil
        refresh()
        fitPiano()
    }

    /// The run with `id` chosen to watch, or no longer.
    func toggle(_ id: RunID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        if listening == .runs { stop() }
        previewStep = nil
        refresh()
        fitPiano()
    }

    func clearSelection() {
        selection = []
        if listening == .runs { stop() }
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
        commit(practice.naming(id, name), rematching: false)
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
        guard path.count > 1 else { return hand(of: id)?.name ?? "" }
        return zip(path, path.dropFirst())
            .map { parent, child in String((parent.children.firstIndex { $0.id == child.id } ?? 0) + 1) }
            .joined(separator: ".")
    }

    func span(of id: RunID) -> ClosedRange<Double>? {
        guard let practice, let score else { return nil }
        return practice.span(of: id, in: score)
    }

    private func hand(of id: RunID) -> Hand? {
        practice?.find(id)?.hand
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

    /// The step `step` of the run in focus lit on the piano, and the
    /// recording at its moment.
    func preview(_ step: Int) {
        guard let score, let practice else { return }
        stop()
        previewStep = step
        let onset = score.boundary(hand, step)
        playhead = max(0, Alignment.recordingTime(onset, practice.alignment))
    }

    // MARK: – Matching the recording

    /// The run whose ends "start" and "end" set: the one run chosen, or the
    /// run in focus.
    var matchedRun: RunID? {
        selection.count == 1 ? selection.first : focus
    }

    /// The matched run heard from the moment the recording is at.
    func markStart() {
        guard let id = matchedRun, let practice, let score else { return }
        let at = currentTime
        commit(kept(practice, around: id).settingStart(of: id, to: at, in: score))
        logger?.log(.practice_run_matched(edge: "start", at: at))
    }

    /// The matched run heard until the moment the recording is at.
    func markEnd() {
        guard let id = matchedRun, let practice, let score else { return }
        let at = currentTime
        commit(kept(practice, around: id).settingEnd(of: id, to: at, in: score))
        logger?.log(.practice_run_matched(edge: "end", at: at))
    }

    // MARK: – Nudging

    /// A step's mark on the recording strip: the moment of the score it is
    /// struck at, where the recording has it, and whether it is pinned
    /// there by hand.
    struct StepMark: Equatable {
        let score: Double
        let recording: Double
        let isPinned: Bool
    }

    /// Every step of the hand shown, where it is heard, to drag a step
    /// that is heard in the wrong place to where it is.
    var stepMarks: [StepMark] {
        guard let practice, let score else { return [] }
        let alignment = practice.alignment
        return score.steps(hand).map { step in
            StepMark(score: step.onset, recording: Alignment.recordingTime(step.onset, alignment),
                     isPinned: practice.anchors.contains { abs($0.score - step.onset) < Score.sameTime })
        }
    }

    /// How far either side of a nudge point the strip shows, in seconds.
    static let zoomReach = 3.0

    /// The nudge points: those tagged, and where the match doubts itself.
    var nudgePoints: [Double] { practice?.nudgePoints ?? [] }

    /// Whether the recording stands at a nudge point that was tagged.
    var isAtTag: Bool {
        practice?.nudge(near: currentTime) != nil
    }

    /// A nudge point tagged where the recording is, or the one there taken
    /// away: what the tag button and its key do.
    func toggleTag() {
        guard let practice, hasRecording else { return }
        let at = currentTime
        let isTagged = practice.nudge(near: at) == nil
        commit(isTagged ? practice.tagging(at) : practice.untagging(at), rematching: false)
        logger?.log(.practice_nudge_tagged(at: at, isTagged: isTagged))
    }

    /// The recording brought to the next nudge point, or the one before,
    /// and the strip to the seconds around it; listened to on from there if
    /// it was being listened to.
    func goToNudge(forward: Bool) {
        let points = nudgePoints
        let now = currentTime
        let reach = Practice.nudgeReach
        guard let target = forward ? points.first(where: { $0 > now + reach })
                                   : points.last(where: { $0 < now - reach }) else { return }
        seek(to: target)
        let length = recordingLength ?? target
        zoom = max(0, target - Self.zoomReach)...min(length, target + Self.zoomReach)
    }

    /// The moment `scoreTime` of the score heard at `recording` seconds: an
    /// edge between runs dragged along the recording. Saved only when
    /// `isDone`, so a drag is one change on disk.
    func move(edgeAt scoreTime: Double, to recording: Double, isDone: Bool) {
        guard let practice, let score, let focus else { return }
        let edges = shownEdges
        let isInside = edges.dropFirst().dropLast().contains { abs($0 - scoreTime) < Score.sameTime }
        let base = isInside ? practice.keeping(focus, in: score) : practice
        commit(base.anchoring(scoreTime, to: recording), saving: isDone)
        if isDone { logger?.log(.practice_run_matched(edge: "edge", at: recording)) }
    }

    /// `practice` with the run in focus kept where it is heard, if the run
    /// with `id` is inside it, so matching a run of it leaves the runs
    /// around it where they were.
    private func kept(_ practice: Practice, around id: RunID) -> Practice {
        guard let focus, id != focus, let score else { return practice }
        return practice.keeping(focus, in: score)
    }

    /// The edges of the runs shown, at the moments of the score they are:
    /// where the run in focus begins, where each of its runs after the
    /// first begins, and where it ends.
    var shownEdges: [Double] {
        guard let score, let run = focusPath.last else { return [] }
        let starts = [run.first] + (run.isLeaf ? [] : run.children.dropFirst().map(\.first))
        return starts.map { score.boundary(hand, $0) } + [score.boundary(hand, run.last + 1)]
    }

    func recordingTime(ofScore t: Double) -> Double {
        Alignment.recordingTime(t, practice?.alignment ?? [])
    }

    /// `next` made the practice, and saved unless `saving` is false (an
    /// edge still being dragged). Pins set or taken away are matched
    /// around (`matchAgain`) once saved.
    private func commit(_ next: Practice, saving: Bool = true, rematching: Bool = true) {
        guard var piece, next != piece.practice else { return }
        let pinsChanged = next.anchors != piece.practice.anchors
        piece.practice = next
        self.piece = piece
        if saving, let saved = try? currentLibrary.save(piece) {
            self.piece = saved
            keep(saved)
        }
        selection = selection.filter { next.find($0) != nil }
        if let focus, next.find(focus) == nil { self.focus = next.root(hand)?.id }
        refresh()
        if listening == .runs { play() }
        if saving, rematching, pinsChanged { matchAgain() }
    }

    // MARK: – Playing

    var hasRecording: Bool { recordingLength != nil }

    /// The moment of the recording heard, or where it stands.
    var currentTime: Double {
        if listening != nil, let player, player.isPlaying { return player.currentTime }
        return playhead
    }

    /// The runs watched, played on from where the recording stands if that
    /// is inside them, and otherwise from the next of them
    /// (`Playback.start`).
    func play() {
        guard let practice, let score, let player, hasRecording else { return }
        let segments = Playback.segments(watched, practice, score)
        guard !segments.isEmpty else { return }
        let from = currentTime
        previewStep = nil
        litNotes = Playback.notes(of: watched, practice, score)
        player.play(segments, from: from, repeats: repeats)
        listening = .runs
        logger?.log(.practice_playback_started(segments: segments.count, repeats: repeats))
    }

    /// The recording played from where it stands to its end, with all of
    /// the hand lit.
    func listen() {
        guard let practice, let score, let player, let recordingLength,
              let root = practice.root(hand) else { return }
        let now = currentTime
        let from = now < recordingLength - Playback.nearEnd ? now : 0
        previewStep = nil
        litNotes = Playback.notes(of: [root.id], practice, score)
        player.play([Segment(start: from, end: recordingLength)], from: from, repeats: false)
        listening = .free
        logger?.log(.practice_playback_started(segments: 1, repeats: false))
    }

    /// What the space bar does: the runs watched played, or whatever is
    /// playing stopped.
    func playOrStop() {
        if listening != nil { stop() } else { play() }
    }

    func stop() {
        guard listening != nil else { return }
        playhead = currentTime
        player?.stop()
        listening = nil
        refresh()
        logger?.log(.practice_playback_stopped)
    }

    /// The recording brought to `time` seconds, and played on from there
    /// as it was being played (the runs, or listened to), if it was.
    func seek(to time: Double) {
        let was = listening
        stand(at: time)
        resume(was)
    }

    /// The recording brought `seconds` later, or earlier: the skip buttons.
    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// How far the skip buttons go.
    static let skipSeconds = 5.0

    /// The recording dragged to `time` seconds: it stops while it is
    /// dragged, its keys lit as they are at each moment passed, and when
    /// the drag ends (`isDone`) it plays on from there as it was being
    /// played, if it was.
    func scrub(to time: Double, isDone: Bool) {
        if !isScrubbing {
            isScrubbing = true
            resumesAfterScrub = listening
        }
        stand(at: time)
        guard isDone else { return }
        isScrubbing = false
        resume(resumesAfterScrub)
        resumesAfterScrub = nil
    }

    /// The recording stopped and standing at `time` seconds.
    private func stand(at time: Double) {
        stop()
        previewStep = nil
        playhead = time.clamped(to: 0...(recordingLength ?? 0))
    }

    private func resume(_ was: Listening?) {
        switch was {
        case .runs: play()
        case .free: listen()
        case nil: break
        }
    }

    private func finished() {
        guard listening != nil else { return }
        playhead = player?.currentTime ?? playhead
        listening = nil
        refresh()
        logger?.log(.practice_playback_stopped)
    }

    /// The keys lit at `time` seconds of the recording: the step looked at
    /// while cutting, or else the notes of the runs watched.
    func lights(at time: Double) -> [Int: [KeyLight]] {
        if listening == nil, let previewStep, let step = score?.steps(hand)[safe: previewStep] {
            return Playback.lights(of: step, hand)
        }
        return Playback.lights(at: time, litNotes)
    }

    /// The notes to light while nothing plays: all of the hand shown, so
    /// the keys are right at any moment the recording is stood at.
    private func refresh() {
        guard listening == nil, let practice, let score, let root = practice.root(hand) else { return }
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
