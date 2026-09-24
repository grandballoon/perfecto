import Foundation

struct SequencerStep {
    var degree: Degree = .I
    var joystickMode: JoystickMode = .default
    var joystickDirection: JoystickDirection = .center
    var gate: Double = 0.75     // fraction of step to hold chord (0...1)
    var isRest: Bool = false

    var label: String { isRest ? "—" : degree.numeralLabel }

    /// Gates this close to 100% tie: the chord rings into the next step
    /// instead of being released, the clearly-audible top of the gate range.
    static let tieThreshold = 0.98
    var isTied: Bool { gate >= Self.tieThreshold }
}

extension Degree {
    var numeralLabel: String {
        switch self {
        case .I:      return "I"
        case .ii:     return "ii"
        case .iii:    return "iii"
        case .IV:     return "IV"
        case .V:      return "V"
        case .vi:     return "vi"
        case .viiDim: return "vii°"
        }
    }
}

@Observable
@MainActor
final class SequencerState {
    /// One step per 1/16 note. `bars` × 16 steps; grows with `setBars`.
    var steps: [SequencerStep] = Array(repeating: SequencerStep(), count: 16)
    var currentStep: Int = -1   // -1 = stopped; else 0 ..< steps.count (global playhead)
    /// Steps being edited in the UI, as global indices (they may span bars).
    /// The step editor applies each change to every selected step.
    var selectedSteps: Set<Int> = [0]
    /// Most recently touched selected step — the one whose values the step
    /// editor displays. nil when the selection is empty.
    var primaryStep: Int? = 0
    var isPlaying: Bool = false
    var swing: Double = 0       // 0...0.5 (reserved for later timing offset)

    /// Pattern length in bars. Each bar is one 16-step page. Allowed: 1, 2, 4.
    private(set) var bars: Int = 1
    /// Which bar (page) the grid is showing.
    var currentPage: Int = 0
    /// When true, playback runs through every bar in sequence; when false it
    /// loops the current bar only.
    var chain: Bool = true

    /// The bar counts the UI offers, in order — also drives the "add bar" step.
    static let barOptions = [1, 2, 4]
    static let stepsPerBar = 16

    /// The steps playback runs through, in order: every bar in chain mode,
    /// otherwise just the visible bar, which is the one that loops.
    var playedSteps: [SequencerStep] {
        guard !chain else { return steps }
        let base = currentPage * Self.stepsPerBar
        return Array(steps[base ..< min(base + Self.stepsPerBar, steps.count)])
    }

    /// One undoable state: the pattern, its length, and the step selection, so
    /// Undo rewinds selection changes the same way it rewinds chord edits.
    private struct EditState {
        var steps: [SequencerStep]
        var bars: Int
        var selectedSteps: Set<Int>
        var primaryStep: Int?
    }

    /// Edit history for the grid. Each mutating edit pushes the prior state so a
    /// single tap of Undo restores it — supports fine-tuning a loop in real time.
    private var undoStack: [EditState] = []
    private let undoLimit = 50
    var canUndo: Bool { !undoStack.isEmpty }

    private let defaults: UserDefaults
    private static let storageKey = "seqSteps.v2"

    /// `defaults` is injectable so tests can use an isolated store instead of
    /// reading and writing the user's saved pattern.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Call immediately *before* mutating `steps`, `bars` or the selection to
    /// make the change undoable.
    func snapshot() {
        undoStack.append(EditState(steps: steps, bars: bars,
                                   selectedSteps: selectedSteps,
                                   primaryStep: primaryStep))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        steps = previous.steps
        bars  = previous.bars
        selectedSteps = previous.selectedSteps
        primaryStep = previous.primaryStep
        clampCursors()
        save()
    }

    /// Resets every step (keeping the pattern length) and the selection
    /// together as one undo step.
    func clearPattern() {
        snapshot()
        steps = Array(repeating: SequencerStep(), count: bars * Self.stepsPerBar)
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
    /// cells of one page's grid. A straight drag yields a row or column run;
    /// a diagonal drag selects the full block between its corners. Indices are
    /// page-local (0 ..< 16); callers add the page's base offset.
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

    // MARK: – Bars / pagination

    func setBars(_ newBars: Int) {
        guard newBars != bars, newBars >= 1 else { return }
        snapshot()
        applyBars(newBars)
        save()
    }

    /// Advances to the next larger allowed bar count (1 → 2 → 4). No-op at max.
    func addBar() {
        guard let idx = Self.barOptions.firstIndex(of: bars),
              idx + 1 < Self.barOptions.count else { return }
        setBars(Self.barOptions[idx + 1])
        currentPage = bars - 1
    }

    var canAddBar: Bool { bars != Self.barOptions.last }

    private func applyBars(_ newBars: Int) {
        bars = newBars
        let target = bars * Self.stepsPerBar
        if steps.count < target {
            steps.append(contentsOf: Array(repeating: SequencerStep(),
                                           count: target - steps.count))
        } else if steps.count > target {
            steps.removeLast(steps.count - target)
        }
        clampCursors()
    }

    /// Keeps the page, playhead and selection inside the pattern after it
    /// shrinks, so no view or clock tick indexes past the end of `steps`.
    private func clampCursors() {
        if currentPage >= bars { currentPage = max(0, bars - 1) }
        if currentStep >= steps.count { currentStep = -1 }
        selectedSteps = selectedSteps.filter { $0 < steps.count }
        if let primary = primaryStep, primary >= steps.count {
            primaryStep = selectedSteps.min()
        }
    }

    // MARK: – Persistence

    func save() {
        let encoded = steps.map(encode)
        defaults.set(["bars": bars, "chain": chain, "steps": encoded],
                     forKey: Self.storageKey)
    }

    func load() {
        // v2: bars + chain + steps
        if let dict = defaults.dictionary(forKey: Self.storageKey),
           let stepData = dict["steps"] as? [[String: Any]] {
            bars  = (dict["bars"]  as? Int)  ?? 1
            chain = (dict["chain"] as? Bool) ?? true
            steps = stepData.map(decode)
            applyBars(bars)   // reconcile any length mismatch
            return
        }
        // v1 migration: a bare 16-step array → one bar
        if let data = defaults.array(forKey: "seqSteps.v1") as? [[String: Any]],
           data.count == 16 {
            bars = 1
            steps = data.map(decode)
        }
    }

    // MARK: – Encoding helpers

    private func encode(_ s: SequencerStep) -> [String: Any] {
        ["degree": s.degree.rawValue,
         "jmIdx": jmIndex(s.joystickMode),
         "jdIdx": jdIndex(s.joystickDirection),
         "gate": s.gate,
         "isRest": s.isRest]
    }

    private func decode(_ d: [String: Any]) -> SequencerStep {
        var s = SequencerStep()
        if let v = d["degree"]  as? Int    { s.degree           = Degree(rawValue: v) ?? .I }
        if let v = d["jmIdx"]   as? Int    { s.joystickMode      = jmFromIndex(v) }
        if let v = d["jdIdx"]   as? Int    { s.joystickDirection = jdFromIndex(v) }
        if let v = d["gate"]    as? Double { s.gate              = v }
        if let v = d["isRest"]  as? Bool   { s.isRest            = v }
        return s
    }

    private func jmIndex(_ m: JoystickMode) -> Int {
        switch m { case .default: return 0; case .extended: return 1; case .chromatic: return 2 }
    }
    private func jmFromIndex(_ i: Int) -> JoystickMode {
        switch i { case 1: return .extended; case 2: return .chromatic; default: return .default }
    }
    private let allDirections: [JoystickDirection] = [
        .center, .up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft
    ]
    private func jdIndex(_ d: JoystickDirection) -> Int {
        allDirections.firstIndex(of: d) ?? 0
    }
    private func jdFromIndex(_ i: Int) -> JoystickDirection {
        guard i >= 0, i < allDirections.count else { return .center }
        return allDirections[i]
    }
}
