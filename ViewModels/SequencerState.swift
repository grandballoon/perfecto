import Foundation

struct SequencerStep: Codable, Equatable {
    var degree: Degree = .I
    var color: ChordColor = .base
    var gate: Double = 0.75     // fraction of step to hold chord (0...1)
    var isRest: Bool = false

    /// The chord this step plays.
    var spec: ChordSpec { ChordSpec(degree: degree, color: color) }

    func label(in key: Key) -> String { isRest ? "—" : degreeNumeral(key: key, degree: degree) }

    /// Gates this close to 100% tie: the chord rings into the next step
    /// instead of being released, the clearly-audible top of the gate range.
    static let tieThreshold = 0.98
    var isTied: Bool { gate >= Self.tieThreshold }

    /// Whether this step holds the chord of `previous` rather than striking a
    /// new one: `previous` is tied into it and asks for the same chord. The one
    /// tie rule, shared by live playback and the MIDI export.
    func continues(_ previous: SequencerStep?) -> Bool {
        guard let previous, previous.isTied, !previous.isRest, !isRest else { return false }
        return previous.spec == spec
    }
}

/// How the sequencer lays out a pattern longer than one bar.
enum SequencerLayout: String, CaseIterable {
    /// One bar on screen at a time, behind numbered tabs.
    case paged
    /// Every bar in one continuous column that scrolls.
    case scroll

    var displayName: String {
        switch self {
        case .paged:  return "Pages"
        case .scroll: return "Scroll"
        }
    }
}

@Observable
@MainActor
final class SequencerState {
    /// One step per 1/16 note, always a whole number of bars. The pattern is
    /// as long as the bars added to it (`addBar`, `removeBar`).
    var steps: [SequencerStep] = Array(repeating: SequencerStep(), count: stepsPerBar)
    var currentStep: Int = -1   // -1 = stopped; else 0 ..< steps.count (global playhead)
    /// Steps being edited in the UI, as global indices (they may span bars).
    /// The step editor applies each change to every selected step.
    var selectedSteps: Set<Int> = [0]
    /// Most recently touched selected step — the one whose values the step
    /// editor displays. nil when the selection is empty.
    var primaryStep: Int? = 0
    var isPlaying: Bool = false
    var swing: Double = 0       // 0...0.5 (reserved for later timing offset)

    /// The steps playback repeats, as global indices; empty means the whole
    /// pattern. It is captured from the selection (`loopSelection`) and then
    /// independent of it, so steps can go on being selected and edited while
    /// the loop plays.
    private(set) var loopSteps: Set<Int> = []
    /// The bar the grid shows: the visible page in the paged layout, the bar
    /// scrolled to in the scroll layout. Playback moves it with the playhead.
    var focusedBar: Int = 0
    /// Which of the two grid layouts is on screen. Remembered across launches.
    var layout: SequencerLayout = .paged {
        didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    static let stepsPerBar = MusicalTime.stepsPerBar

    var barCount: Int { steps.count / Self.stepsPerBar }

    /// The step indices playback runs through, in order.
    var playOrder: [Int] {
        loopSteps.isEmpty ? Array(steps.indices) : loopSteps.sorted()
    }

    /// The steps playback runs through, in order — also what the MIDI export
    /// renders.
    var playedSteps: [SequencerStep] { playOrder.map { steps[$0] } }

    /// Where the playhead goes from `index`: the next step of the loop (or of
    /// the whole pattern), wrapping to the first at the end. A playhead outside
    /// the loop joins it at the next loop step.
    func step(after index: Int) -> Int {
        guard !loopSteps.isEmpty else { return (index + 1) % steps.count }
        return loopSteps.filter { $0 > index }.min() ?? loopSteps.min() ?? 0
    }

    /// One undoable state: the pattern (and so its length), the loop and the
    /// step selection, so Undo rewinds selection changes the same way it
    /// rewinds chord edits.
    private struct EditState {
        var steps: [SequencerStep]
        var loopSteps: Set<Int>
        var selectedSteps: Set<Int>
        var primaryStep: Int?
    }

    /// Edit history for the grid. Each mutating edit pushes the prior state so a
    /// single tap of Undo restores it — supports fine-tuning a loop in real time.
    private var undoStack: [EditState] = []
    private let undoLimit = 50
    var canUndo: Bool { !undoStack.isEmpty }

    private let defaults: UserDefaults
    private let logger: (any Logger)?
    /// "sequencer.pattern.v3" also stored a fixed bar count and a chain flag;
    /// its steps are still read (see `load`). Formats before v3 are not.
    private static let storageKey = "sequencer.pattern.v4"
    private static let legacyStorageKey = "sequencer.pattern.v3"
    private static let layoutKey = "sequencer.layout"

    /// `defaults` is injectable so tests can use an isolated store instead of
    /// reading and writing the user's saved pattern.
    init(defaults: UserDefaults = .standard, logger: (any Logger)? = nil) {
        self.defaults = defaults
        self.logger = logger
        load()
    }

    /// Call immediately *before* mutating `steps`, the loop or the selection
    /// to make the change undoable.
    func snapshot() {
        undoStack.append(EditState(steps: steps, loopSteps: loopSteps,
                                   selectedSteps: selectedSteps,
                                   primaryStep: primaryStep))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        steps = previous.steps
        loopSteps = previous.loopSteps
        selectedSteps = previous.selectedSteps
        primaryStep = previous.primaryStep
        clampCursors()
        save()
    }

    /// Resets every step (keeping the pattern length and the loop) and the
    /// selection together as one undo step.
    func clearPattern() {
        snapshot()
        steps = Array(repeating: SequencerStep(), count: steps.count)
        selectedSteps = []
        primaryStep = nil
        save()
    }

    // MARK: – Selection

    /// Tap: select an unselected step, deselect a selected one.
    func toggleStepSelection(_ idx: Int) {
        snapshot()
        if selectedSteps.contains(idx) {
            selectedSteps.remove(idx)
            if primaryStep == idx { primaryStep = selectedSteps.min() }
        } else {
            selectedSteps.insert(idx)
            primaryStep = idx
        }
    }

    /// Deselects every step.
    func deselectAll() {
        guard !selectedSteps.isEmpty || primaryStep != nil else { return }
        snapshot()
        selectedSteps = []
        primaryStep = nil
    }

    /// Commits a finished drag sweep: adds `indices` to the selection.
    /// Sweeps only ever highlight — a step that is already selected stays
    /// selected when the finger passes over it again.
    func addToSelection(_ indices: Set<Int>, primary: Int) {
        guard !indices.isSubset(of: selectedSteps) || primaryStep != primary else { return }
        snapshot()
        selectedSteps.formUnion(indices)
        primaryStep = primary
    }

    /// Applies `edit` to every selected step and saves. The caller takes the
    /// undo snapshot, so a continuous gesture can group many calls into one.
    func editSelectedSteps(_ edit: (inout SequencerStep) -> Void) {
        for idx in selectedSteps where idx < steps.count {
            edit(&steps[idx])
        }
        save()
    }

    /// All step indices inside the axis-aligned rectangle spanned by two
    /// cells of the step grid. A straight drag yields a row or column run;
    /// a diagonal drag selects the full block between its corners. Rows run on
    /// through the bars, so global indices sweep across bar boundaries.
    static func rectangle(from a: Int, to b: Int, columns: Int = 4) -> Set<Int> {
        let (rowA, colA) = (a / columns, a % columns)
        let (rowB, colB) = (b / columns, b % columns)
        var indices = Set<Int>()
        for row in min(rowA, rowB)...max(rowA, rowB) {
            for col in min(colA, colB)...max(colA, colB) {
                indices.insert(row * columns + col)
            }
        }
        return indices
    }

    // MARK: – Loop

    /// Makes playback repeat exactly the selected steps, in order.
    func loopSelection() {
        guard !selectedSteps.isEmpty, selectedSteps != loopSteps else { return }
        snapshot()
        loopSteps = selectedSteps
        save()
        logger?.log(.sequencer_loop_changed(stepCount: loopSteps.count))
    }

    /// Makes playback repeat the whole pattern again.
    func loopAll() {
        guard !loopSteps.isEmpty else { return }
        snapshot()
        loopSteps = []
        save()
        logger?.log(.sequencer_loop_changed(stepCount: 0))
    }

    // MARK: – Bars

    /// Appends a blank bar and shows it.
    func addBar() {
        snapshot()
        steps.append(contentsOf: Array(repeating: SequencerStep(), count: Self.stepsPerBar))
        focusedBar = barCount - 1
        save()
        logger?.log(.sequencer_bars_changed(barCount: barCount))
    }

    var canRemoveBar: Bool { barCount > 1 }

    /// Removes one bar; the bars after it move up, and the selection, loop and
    /// playhead move with their steps. A loop that lay wholly inside the bar
    /// goes with it, leaving the whole pattern looping. The last bar stays.
    func removeBar(_ bar: Int) {
        guard canRemoveBar, (0..<barCount).contains(bar) else { return }
        snapshot()
        let removed = bar * Self.stepsPerBar ..< (bar + 1) * Self.stepsPerBar
        /// Where a step index points after the removal; nil if it was removed.
        func moved(_ index: Int) -> Int? {
            if removed.contains(index) { return nil }
            return index < removed.lowerBound ? index : index - removed.count
        }
        steps.removeSubrange(removed)
        selectedSteps = Set(selectedSteps.compactMap(moved))
        loopSteps = Set(loopSteps.compactMap(moved))
        primaryStep = primaryStep.flatMap(moved) ?? selectedSteps.min()
        // A playhead inside the removed bar steps back to just before it, so
        // the next tick plays what moved into its place.
        currentStep = moved(currentStep) ?? removed.lowerBound - 1
        if focusedBar > bar { focusedBar -= 1 }
        clampCursors()
        save()
        logger?.log(.sequencer_bars_changed(barCount: barCount))
    }

    /// Keeps the focused bar, playhead, loop and selection inside the pattern
    /// after it shrinks, so no view or clock tick indexes past the end of `steps`.
    private func clampCursors() {
        focusedBar = min(max(focusedBar, 0), barCount - 1)
        if currentStep >= steps.count { currentStep = -1 }
        selectedSteps = selectedSteps.filter { $0 < steps.count }
        loopSteps = loopSteps.filter { $0 < steps.count }
        if let primary = primaryStep, primary >= steps.count {
            primaryStep = selectedSteps.min()
        }
    }

    // MARK: – Persistence

    func save() {
        let pattern = SavedPattern(steps: steps, loopSteps: loopSteps.sorted())
        guard let data = try? JSONEncoder().encode(pattern) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Restores the saved pattern and layout. Data that doesn't decode (for
    /// example a color case this build doesn't know) or isn't a whole number
    /// of bars leaves the default empty pattern rather than being partly
    /// interpreted.
    func load() {
        if let saved = defaults.string(forKey: Self.layoutKey).flatMap(SequencerLayout.init(rawValue:)) {
            layout = saved
        }
        guard let data = defaults.data(forKey: Self.storageKey)
                      ?? defaults.data(forKey: Self.legacyStorageKey),
              let pattern = try? JSONDecoder().decode(SavedPattern.self, from: data),
              !pattern.steps.isEmpty,
              pattern.steps.count.isMultiple(of: Self.stepsPerBar)
        else { return }
        steps = pattern.steps
        loopSteps = Set(pattern.loopSteps ?? [])
        clampCursors()
    }

    /// The stored form of a pattern. Enum cases are encoded by name (and
    /// `Degree` by its explicit raw value), so reordering a Swift enum never
    /// changes what a saved pattern means. `loopSteps` is absent from v3 data.
    private struct SavedPattern: Codable {
        var steps: [SequencerStep]
        var loopSteps: [Int]?
    }
}
