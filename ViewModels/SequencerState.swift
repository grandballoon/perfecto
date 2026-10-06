import Foundation

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
    /// The music being edited and played: notes in layers (see `Timeline`).
    /// Every edit goes through here, so the player hears it at once and it
    /// is saved.
    private(set) var timeline = Timeline() {
        didSet {
            guard timeline != oldValue else { return }
            transport?.timeline = timeline
        }
    }
    /// The layer on screen: the one the grid shows and the editor changes.
    private(set) var layerID: Layer.ID

    var currentStep: Int = -1   // -1 = stopped; else 0 ..< steps.count (global playhead)
    /// Steps being edited in the UI, as global indices (they may span bars).
    /// The step editor applies each change to every selected step.
    var selectedSteps: Set<Int> = [0]
    /// Most recently touched selected step — the one whose values the step
    /// editor displays. nil when the selection is empty.
    var primaryStep: Int? = 0
    var isPlaying: Bool = false {
        didSet {
            guard isPlaying != oldValue else { return }
            if isPlaying {
                transport?.start()
            } else {
                transport?.stop()
                currentStep = -1
            }
        }
    }

    /// The bar the grid shows: the visible page in the paged layout, the bar
    /// scrolled to in the scroll layout. Playback moves it with the playhead.
    var focusedBar: Int = 0
    /// Which of the two grid layouts is on screen. Remembered across launches.
    var layout: SequencerLayout = .paged {
        didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    /// What plays the timeline. Attached by whoever owns the clock and the
    /// sinks; without one the sequencer can be edited but not heard.
    private var transport: TimelinePlayer?

    static let stepsPerBar = MusicalTime.stepsPerBar

    var barCount: Int { timeline.barCount }

    /// The layer on screen.
    private var layer: Layer { timeline.layer(layerID) ?? Layer() }

    /// The layer on screen, one step at a time, as the step editor sees it
    /// (see `SequencerStep`). Setting it changes only the steps that differ.
    var steps: [SequencerStep] {
        get {
            let layer = layer
            return (0..<timeline.stepCount).map(layer.step)
        }
        set {
            let old = steps
            edit { layer in
                for (index, step) in newValue.enumerated() where index < old.count && step != old[index] {
                    layer.setStep(index, to: step)
                }
            }
        }
    }

    /// One step of the layer on screen.
    func step(_ index: Int) -> SequencerStep {
        layer.step(index)
    }

    /// The steps playback repeats; empty means the whole pattern. It is
    /// captured from the selection (`loopSelection`) and then independent of
    /// it, so steps can go on being selected and edited while the loop plays.
    var loopSteps: Set<Int> {
        guard let loop = timeline.loop else { return [] }
        return Set(TimelineTime.step(at: loop.lowerBound) ..< TimelineTime.step(at: loop.upperBound - 1) + 1)
    }

    /// One undoable state: the timeline (and so its length and loop) and
    /// the step selection, so Undo rewinds selection changes the same way it
    /// rewinds chord edits.
    private struct EditState {
        var timeline: Timeline
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
    /// The timeline, as JSON. "sequencer.pattern.v4" and "v3" held one step
    /// for every sixteenth; they are still read, once, into the first layer
    /// (see `load`). Formats before v3 are not.
    private static let storageKey = "sequencer.timeline.v1"
    private static let stepStorageKeys = ["sequencer.pattern.v4", "sequencer.pattern.v3"]
    private static let layoutKey = "sequencer.layout"

    /// `defaults` is injectable so tests can use an isolated store instead of
    /// reading and writing the user's saved pattern.
    init(defaults: UserDefaults = .standard, logger: (any Logger)? = nil) {
        self.defaults = defaults
        self.logger = logger
        let blank = Self.blank()
        timeline = blank
        layerID = blank.layers[0].id
        load()
    }

    /// The sequence a new pattern starts as: one bar, the I chord on every step.
    private static func blank(bars: Int = 1) -> Timeline {
        var timeline = Timeline(barCount: bars)
        timeline.layers = [Layer(steps: Array(repeating: SequencerStep(), count: timeline.stepCount))]
        return timeline
    }

    /// Gives the sequencer something to be heard through: it follows the
    /// timeline and the play button from here on, and moves the playhead.
    func attach(_ transport: TimelinePlayer) {
        self.transport = transport
        transport.timeline = timeline
        transport.onStep = { [weak self] step in
            guard let self, let step else { return }
            currentStep = step
            focusedBar = step / Self.stepsPerBar
        }
        if isPlaying { transport.start() }
    }

    /// Stops this sequencer being heard through `transport`, if it is.
    func detach(_ transport: TimelinePlayer) {
        guard self.transport === transport else { return }
        isPlaying = false
        transport.onStep = nil
        self.transport = nil
    }

    /// Changes the layer on screen and saves.
    private func edit(_ change: (inout Layer) -> Void) {
        timeline.edit(layer: layerID, change)
        save()
    }

    /// Call immediately *before* mutating the pattern, the loop or the
    /// selection to make the change undoable.
    func snapshot() {
        undoStack.append(EditState(timeline: timeline,
                                   selectedSteps: selectedSteps,
                                   primaryStep: primaryStep))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        timeline = previous.timeline
        selectedSteps = previous.selectedSteps
        primaryStep = previous.primaryStep
        clampCursors()
        save()
    }

    /// Resets every step (keeping the pattern length and the loop) and the
    /// selection together as one undo step.
    func clearPattern() {
        snapshot()
        let cleared = Self.blank(bars: barCount).layers[0].notes
        edit { $0.notes = cleared }
        selectedSteps = []
        primaryStep = nil
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
    func editSelectedSteps(_ change: (inout SequencerStep) -> Void) {
        let stepCount = timeline.stepCount
        edit { layer in
            for index in selectedSteps.sorted() where index < stepCount {
                var step = layer.step(index)
                change(&step)
                layer.setStep(index, to: step)
            }
        }
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

    /// Makes playback repeat the stretch from the first selected step to
    /// the last.
    func loopSelection() {
        guard !selectedSteps.isEmpty else { return }
        var looped = timeline
        looped.setLoop(steps: selectedSteps)
        guard looped.loop != timeline.loop else { return }
        snapshot()
        timeline = looped
        save()
        logger?.log(.sequencer_loop_changed(stepCount: loopSteps.count))
    }

    /// Makes playback repeat the whole pattern again.
    func loopAll() {
        guard timeline.loop != nil else { return }
        snapshot()
        timeline.loop = nil
        save()
        logger?.log(.sequencer_loop_changed(stepCount: 0))
    }

    // MARK: – Bars

    /// Appends a bar and shows it.
    func addBar() {
        snapshot()
        let added = barCount * Self.stepsPerBar ..< (barCount + 1) * Self.stepsPerBar
        timeline.addBar()
        edit { layer in
            for step in added { layer.setStep(step, to: SequencerStep()) }
        }
        focusedBar = barCount - 1
        logger?.log(.sequencer_bars_changed(barCount: barCount))
    }

    var canRemoveBar: Bool { timeline.canRemoveBar }

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
        timeline.removeBar(bar)
        selectedSteps = Set(selectedSteps.compactMap(moved))
        primaryStep = primaryStep.flatMap(moved) ?? selectedSteps.min()
        // A playhead inside the removed bar steps back to just before it.
        currentStep = moved(currentStep) ?? removed.lowerBound - 1
        if focusedBar > bar { focusedBar -= 1 }
        clampCursors()
        save()
        logger?.log(.sequencer_bars_changed(barCount: barCount))
    }

    /// Keeps the focused bar, playhead and selection inside the pattern
    /// after it shrinks, so no view indexes past the end of it.
    private func clampCursors() {
        let stepCount = timeline.stepCount
        focusedBar = min(max(focusedBar, 0), barCount - 1)
        if currentStep >= stepCount { currentStep = -1 }
        selectedSteps = selectedSteps.filter { $0 < stepCount }
        if let primary = primaryStep, primary >= stepCount {
            primaryStep = selectedSteps.min()
        }
    }

    // MARK: – Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(timeline) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Restores the saved timeline and layout. Data that doesn't decode (for
    /// example a color case this build doesn't know) or isn't a whole number
    /// of bars leaves the default pattern rather than being partly
    /// interpreted.
    func load() {
        if let saved = defaults.string(forKey: Self.layoutKey).flatMap(SequencerLayout.init(rawValue:)) {
            layout = saved
        }
        guard let loaded = savedTimeline() ?? timelineFromSavedSteps(),
              loaded.barCount >= 1, let first = loaded.layers.first else { return }
        timeline = loaded
        layerID = first.id
        clampCursors()
    }

    private func savedTimeline() -> Timeline? {
        defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Timeline.self, from: $0) }
    }

    /// A pattern saved as steps, read into one layer.
    private func timelineFromSavedSteps() -> Timeline? {
        guard let data = Self.stepStorageKeys.lazy.compactMap({ self.defaults.data(forKey: $0) }).first,
              let pattern = try? JSONDecoder().decode(SavedSteps.self, from: data),
              !pattern.steps.isEmpty,
              pattern.steps.count.isMultiple(of: Self.stepsPerBar)
        else { return nil }
        var timeline = Timeline(barCount: pattern.steps.count / Self.stepsPerBar)
        timeline.layers = [Layer(steps: pattern.steps)]
        timeline.setLoop(steps: Set(pattern.loopSteps ?? []).filter { $0 < pattern.steps.count })
        return timeline
    }

    /// The stored form of a pattern of steps. Enum cases are encoded by name
    /// (and `Degree` by its explicit raw value), so reordering a Swift enum
    /// never changed what a saved pattern meant. `loopSteps` is absent from
    /// v3 data.
    private struct SavedSteps: Codable {
        var steps: [SequencerStep]
        var loopSteps: [Int]?
    }
}
