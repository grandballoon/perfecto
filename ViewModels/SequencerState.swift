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

    /// Steps in a bar, which follows the time signature.
    var stepsPerBar: Int { timeline.signature.stepsPerBar }
    /// How the grid arranges the steps: rows of a beat, bar after bar.
    var shape: StepGridShape { StepGridShape(timeline.signature) }

    var barCount: Int { timeline.barCount }

    /// The layer on screen.
    private var layer: Layer { timeline.layer(layerID) ?? Layer() }

    /// The layer on screen, one step at a time (see `SequencerStep`): how
    /// a pattern is written out for a test. Setting it changes only the
    /// steps that differ. The screen edits notes instead (see "Editing the
    /// selected notes").
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
        // A new sequence is one empty bar.
        let empty = Timeline()
        timeline = empty
        layerID = empty.layers[0].id
        load()
    }


    /// Gives the sequencer something to be heard through: it follows the
    /// timeline and the play button from here on, and moves the playhead.
    func attach(_ transport: TimelinePlayer) {
        self.transport = transport
        transport.timeline = timeline
        transport.onStep = { [weak self] step in
            guard let self, let step else { return }
            currentStep = step
            focusedBar = step / stepsPerBar
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
        showALayerThatExists()
        selectedSteps = previous.selectedSteps
        primaryStep = previous.primaryStep
        clampCursors()
        save()
    }

    /// Empties every step (keeping the pattern length and the loop) and the
    /// selection together as one undo step.
    func clearPattern() {
        snapshot()
        edit { $0.notes = [] }
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

    // MARK: – Editing the selected notes
    //
    // An edit applies to the notes on the selected steps: every note the
    // grid draws across one of them.

    /// The selected steps as the layer's edits take them. A note played just
    /// before the end is nearest a step line that is not there; the grid
    /// draws it on the last step, so selecting that step selects it too.
    private var editedSteps: Set<Int> { edited(selectedSteps) }

    private func edited(_ steps: Set<Int>) -> Set<Int> {
        let end = timeline.stepCount
        return steps.contains(end - 1) ? steps.union([end]) : steps
    }

    /// The layer on screen as the grid draws it.
    var chits: [NoteChit] { layer.chits(in: shape, stepCount: timeline.stepCount) }

    /// The notes on the selected steps.
    var selectedNotes: [TimelineNote] {
        let layer = layer
        return layer.indicesOfNotes(on: editedSteps).map { layer.notes[$0] }
    }

    /// The note the editor shows: the one on the step touched last.
    var primaryNote: TimelineNote? {
        guard let primaryStep else { return nil }
        let layer = layer
        return layer.note(on: primaryStep)
            ?? (primaryStep == timeline.stepCount - 1 ? layer.note(on: primaryStep + 1) : nil)
    }

    /// Changes the chord of every selected note, and puts a chord on each
    /// selected step that has none: what `change` makes of a plain I. The caller
    /// takes the undo snapshot, so a continuous gesture is one undo step.
    func editSelectedChords(_ change: (ChordSpec) -> ChordSpec) {
        let steps = editedSteps
        let stepCount = timeline.stepCount
        edit { layer in
            let empty = selectedSteps.filter {
                $0 < stepCount && layer.indicesOfNotes(on: edited([$0])).isEmpty
            }
            layer.edit(notesOn: steps) { $0.chord = change($0.chord) }
            layer.place(change(ChordSpec(degree: .I, color: .base)), onSteps: empty)
        }
    }

    /// Makes the selected steps rests. A note held across more steps than
    /// those keeps the rest of itself.
    func restSelected() {
        guard !selectedNotes.isEmpty else { return }
        snapshot()
        let steps = editedSteps
        edit { $0.rest(onSteps: steps) }
    }

    /// Whether Join would change anything: two selected steps side by side
    /// with a note to hold across them.
    var canJoin: Bool {
        var joined = layer
        joined.join(steps: selectedSteps)
        return joined != layer
    }

    /// Makes each run of selected steps one held note.
    func joinSelected() {
        guard canJoin else { return }
        snapshot()
        let steps = selectedSteps
        edit { $0.join(steps: steps) }
    }

    /// Whether a selected note is held across more than one selected step's edge.
    var canSplit: Bool {
        var split = layer
        split.split(steps: selectedSteps)
        return split != layer
    }

    /// Cuts the selected notes at the edges of the selected steps.
    func splitSelected() {
        guard canSplit else { return }
        snapshot()
        let steps = selectedSteps
        edit { $0.split(steps: steps) }
    }

    /// Whether a selected note was played off the grid's lines.
    var canSnap: Bool {
        selectedNotes.contains { !TimelineTime.isOnGrid($0.start) }
    }

    /// Moves the selected notes onto the grid's lines.
    func snapSelected() {
        guard canSnap else { return }
        snapshot()
        let (steps, limit) = (editedSteps, timeline.length)
        edit { $0.snap(notesOn: steps, limit: limit) }
    }

    /// Makes the selected notes `steps` steps longer (shorter if negative).
    func lengthenSelected(bySteps steps: Int) {
        guard !selectedNotes.isEmpty else { return }
        snapshot()
        let (selected, limit) = (editedSteps, timeline.length)
        edit { $0.lengthen(notesOn: selected, by: steps * TimelineTime.ticksPerStep, limit: limit) }
    }

    /// Sets how much of its last step each selected note sounds for. The
    /// caller takes the undo snapshot, so one drag of a slider is one step.
    func setGateOfSelected(_ gate: Double) {
        let (selected, limit) = (editedSteps, timeline.length)
        edit { $0.hold(notesOn: selected, forGate: gate, limit: limit) }
    }

    /// Changes what the selected notes are played with of their own (see
    /// `NotePlaying`): a key or octave set here stays when the live one is
    /// changed, and nil goes back to following it.
    func editSelectedPlaying(_ change: (inout NotePlaying) -> Void) {
        guard !selectedNotes.isEmpty else { return }
        snapshot()
        let steps = editedSteps
        edit { $0.edit(notesOn: steps) { change(&$0.playing) } }
    }

    /// Selects the step after the note the editor shows (or after the step
    /// touched last, if it is empty), coming round to the first at the end:
    /// where the next chord goes when a progression is entered a chord at a
    /// time. The undo snapshot is the caller's, taken before the chord went in.
    func advanceSelection() {
        guard let primaryStep else { return }
        let after = primaryNote.map { max($0.steps.upperBound, primaryStep + 1) } ?? primaryStep + 1
        let next = after < timeline.stepCount ? after : 0
        selectedSteps = [next]
        self.primaryStep = next
        focusedBar = next / stepsPerBar
    }

    // MARK: – Layers

    var layers: [Layer] { timeline.layers }

    var canAddLayer: Bool { timeline.layers.count < Timeline.maxLayers }

    /// Shows `id` in the grid, to be edited. The others play on.
    func showLayer(_ id: Layer.ID) {
        guard id != layerID, timeline.layer(id) != nil else { return }
        layerID = id
    }

    /// Adds an empty layer and shows it.
    func addLayer() {
        guard canAddLayer else { return }
        snapshot()
        layerID = timeline.addLayer()
        save()
    }

    /// Adds a copy of the layer on screen and shows it.
    func duplicateLayer() {
        guard canAddLayer else { return }
        snapshot()
        if let copy = timeline.duplicateLayer(layerID) { layerID = copy }
        save()
    }

    /// Where the playhead is, in ticks from the start; nil while stopped.
    var position: Int? { transport?.position }

    /// Makes `notes` the whole sequence: one layer, `bars` long. For a first
    /// loop recorded from the keys.
    func startLoop(_ notes: [TimelineNote], bars: Int) {
        snapshot()
        var started = Timeline(signature: timeline.signature, barCount: max(bars, 1))
        started.layers = [Layer(notes: notes)]
        timeline = started
        layerID = started.layers[0].id
        selectedSteps = []
        primaryStep = nil
        clampCursors()
        save()
    }

    /// Adds a layer for each of `layers`, a line of notes each. The first
    /// of them takes the place of a layer that is still empty.
    func addLayers(_ layers: [[TimelineNote]]) {
        guard !layers.isEmpty else { return }
        snapshot()
        var edited = timeline
        for notes in layers {
            if let empty = edited.layers.firstIndex(where: \.notes.isEmpty) {
                edited.layers[empty].notes = notes
            } else {
                edited.layers.append(Layer(notes: notes))
            }
        }
        timeline = edited
        save()
    }

    func setLayer(_ id: Layer.ID, muted: Bool) {
        timeline.edit(layer: id) { $0.isMuted = muted }
        save()
    }

    /// Removes a layer. The one on screen, if it goes, gives way to the first.
    func removeLayer(_ id: Layer.ID) {
        snapshot()
        timeline.removeLayer(id)
        showALayerThatExists()
        save()
    }

    /// Empties the sequence back to one bar with nothing in it.
    func removeAllLayers() {
        guard !timeline.isEmpty else { return }
        snapshot()
        timeline = Timeline(signature: timeline.signature)
        showALayerThatExists()
        selectedSteps = []
        primaryStep = nil
        clampCursors()
        save()
    }

    private func showALayerThatExists() {
        if timeline.layer(layerID) == nil { layerID = timeline.layers[0].id }
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

    /// Appends an empty bar and shows it.
    func addBar() {
        snapshot()
        timeline.addBar()
        save()
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
        let removed = shape.steps(ofBar: bar)
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

    var canHalveBars: Bool { timeline.canHalveBars }

    /// Reads the same notes as twice as many bars (see `Timeline.doubleBars`).
    func doubleBars() {
        changeBars { $0.doubleBars() }
        deselectAfterScaling()
    }

    /// Reads the same notes as half as many bars.
    func halveBars() {
        guard canHalveBars else { return }
        changeBars { $0.halveBars() }
        deselectAfterScaling()
    }

    /// Doubling and halving move every note to another step, so what was
    /// selected is no longer what the selection is on.
    private func deselectAfterScaling() {
        selectedSteps = []
        primaryStep = nil
    }

    /// Whether there are empty bars at the end to drop.
    var canTrimBars: Bool {
        var trimmed = timeline
        trimmed.trimEmptyBars()
        return trimmed != timeline
    }

    /// Drops the empty bars at the end.
    func trimEmptyBars() {
        guard canTrimBars else { return }
        changeBars { $0.trimEmptyBars() }
    }

    /// Changes the time signature. Every note stays where it is in time.
    func setSignature(_ signature: TimeSignature) {
        guard signature != timeline.signature else { return }
        changeBars { $0.setSignature(signature) }
        logger?.log(.sequencer_signature_changed(signature: signature.label))
    }

    /// A change to how the timeline is divided into bars.
    private func changeBars(_ change: (inout Timeline) -> Void) {
        snapshot()
        change(&timeline)
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
              pattern.steps.count.isMultiple(of: MusicalTime.stepsPerBar)
        else { return nil }
        var timeline = Timeline(barCount: pattern.steps.count / MusicalTime.stepsPerBar)
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
