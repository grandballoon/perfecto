public enum ScaleType: CaseIterable, Hashable, Identifiable, Sendable {
    public var id: Self { self }
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case majorPentatonic
    case minorPentatonic
    case blues
    case dorian
    case mixolydian
    case lydian

    public var displayName: String {
        switch self {
        case .major:           return "Major"
        case .naturalMinor:    return "Natural Minor"
        case .harmonicMinor:   return "Harmonic Minor"
        case .melodicMinor:    return "Melodic Minor"
        case .majorPentatonic: return "Maj. Pentatonic"
        case .minorPentatonic: return "Min. Pentatonic"
        case .blues:           return "Blues"
        case .dorian:          return "Dorian"
        case .mixolydian:      return "Mixolydian"
        case .lydian:          return "Lydian"
        }
    }

    public var intervals: [Int] {
        switch self {
        case .major:           return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor:    return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor:   return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor:    return [0, 2, 3, 5, 7, 9, 11]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .blues:           return [0, 3, 5, 6, 7, 10]
        case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian:      return [0, 2, 4, 5, 7, 9, 10]
        case .lydian:          return [0, 2, 4, 6, 7, 9, 11]
        }
    }
}
