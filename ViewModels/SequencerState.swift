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
    var steps: [SequencerStep] = Array(repeating: SequencerStep(), count: 16)
    var currentStep: Int = -1   // -1 = stopped; 0-15 = playing step index
    var selectedStep: Int = 0   // step being edited in the UI
    var isPlaying: Bool = false
    var swing: Double = 0       // 0...0.5 (reserved for v2 timing offset)

    init() { load() }

    func save() {
        let encoded: [[String: Any]] = steps.map { s in
            ["degree": s.degree.rawValue,
             "jmIdx": jmIndex(s.joystickMode),
             "jdIdx": jdIndex(s.joystickDirection),
             "gate": s.gate,
             "isRest": s.isRest]
        }
        UserDefaults.standard.set(encoded, forKey: "seqSteps.v1")
    }

    func load() {
        guard let data = UserDefaults.standard.array(forKey: "seqSteps.v1") as? [[String: Any]],
              data.count == 16 else { return }
        steps = data.map { d in
            var s = SequencerStep()
            if let v = d["degree"]  as? Int    { s.degree           = Degree(rawValue: v) ?? .I }
            if let v = d["jmIdx"]   as? Int    { s.joystickMode      = jmFromIndex(v) }
            if let v = d["jdIdx"]   as? Int    { s.joystickDirection = jdFromIndex(v) }
            if let v = d["gate"]    as? Double { s.gate              = v }
            if let v = d["isRest"]  as? Bool   { s.isRest            = v }
            return s
        }
    }

    // MARK: – Encoding helpers

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
