public enum Degree: Int, CaseIterable, Hashable, Codable, Sendable {
    // Raw values are stored in saved patterns, so they are spelled out rather
    // than implied by declaration order.
    case I = 1, ii = 2, iii = 3, IV = 4, V = 5, vi = 6, viiDim = 7

    // Zero-based index into the scale's intervals array
    public var index: Int { rawValue - 1 }
}
