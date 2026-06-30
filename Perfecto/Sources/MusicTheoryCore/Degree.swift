public enum Degree: Int, CaseIterable, Hashable, Sendable {
    case I = 1, ii, iii, IV, V, vi, viiDim

    // Zero-based index into the scale's intervals array
    public var index: Int { rawValue - 1 }
}
