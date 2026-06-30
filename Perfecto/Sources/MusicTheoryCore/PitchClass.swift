public enum PitchClass: Int, CaseIterable, Hashable, Identifiable, Sendable {
    public var id: Int { rawValue }
    case C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B

    public var name: String {
        switch self {
        case .C:  return "C"
        case .Cs: return "C#"
        case .D:  return "D"
        case .Ds: return "D#"
        case .E:  return "E"
        case .F:  return "F"
        case .Fs: return "F#"
        case .G:  return "G"
        case .Gs: return "G#"
        case .A:  return "A"
        case .As: return "A#"
        case .B:  return "B"
        }
    }
}
