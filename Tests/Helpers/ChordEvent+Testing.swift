@testable import Perfecto

extension ChordEvent {
    /// A block chord of `notes`, as if C major degree I at the base color
    /// produced it. For sink tests that care about notes, not meaning.
    static func block(_ notes: [Int], context: ChordContext = .cMajorI) -> ChordEvent {
        ChordEvent(voicing: Voicing(notes: notes), articulation: .block, context: context)
    }
}

extension ChordContext {
    static let cMajorI = performanceContext(key: Key(root: .C, scale: .major), octave: 4,
                                            spec: ChordSpec(degree: .I, color: .base))
}
