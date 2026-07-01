import Foundation

struct SequencerStep {
    var degree: Degree = .I
    var joystickMode: JoystickMode = .default
    var joystickDirection: JoystickDirection = .center
    var gate: Double = 0.75     // fraction of step to hold chord (0...1)
    var isRest: Bool = false

    var label: String { isRest ? "—" : degree.numeralLabel }
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
    var selectedStep: Int = 0   // step being edited in the UI (global index)
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

    private struct EditSnapshot { let steps: [SequencerStep]; let bars: Int }

    /// Edit history for the grid. Each mutating edit pushes the prior state so a
    /// single tap of Undo restores it — supports fine-tuning a loop in real time.
    private var undoStack: [EditSnapshot] = []
    private let undoLimit = 50
    var canUndo: Bool { !undoStack.isEmpty }

    /// Call immediately *before* mutating `steps`/`bars` to make the change undoable.
    func snapshot() {
        undoStack.append(EditSnapshot(steps: steps, bars: bars))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        steps = previous.steps
        bars  = previous.bars
        clampCursors()
        save()
    }

    init() { load() }

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
        let target = bars * 16
        if steps.count < target {
            steps.append(contentsOf: Array(repeating: SequencerStep(),
                                           count: target - steps.count))
        } else if steps.count > target {
            steps.removeLast(steps.count - target)
        }
        clampCursors()
    }

    private func clampCursors() {
        if currentPage >= bars { currentPage = max(0, bars - 1) }
        if selectedStep >= steps.count { selectedStep = max(0, steps.count - 1) }
    }

    // MARK: – Persistence

    func save() {
        let encoded = steps.map(encode)
        UserDefaults.standard.set(
            ["bars": bars, "chain": chain, "steps": encoded],
            forKey: "seqSteps.v2"
        )
    }

    func load() {
        // v2: bars + chain + steps
        if let dict = UserDefaults.standard.dictionary(forKey: "seqSteps.v2"),
           let stepData = dict["steps"] as? [[String: Any]] {
            bars  = (dict["bars"]  as? Int)  ?? 1
            chain = (dict["chain"] as? Bool) ?? true
            steps = stepData.map(decode)
            applyBars(bars)   // reconcile any length mismatch
            return
        }
        // v1 migration: a bare 16-step array → one bar
        if let data = UserDefaults.standard.array(forKey: "seqSteps.v1") as? [[String: Any]],
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
