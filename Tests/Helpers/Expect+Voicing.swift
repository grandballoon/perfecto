import Testing
@testable import Perfecto

/// Convenience assertions for Voicing values in Swift Testing.
/// Use these instead of raw #expect to get readable failure messages.

func expectNotes(_ voicing: Voicing, _ expected: [Int],
                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(voicing.notes == expected, sourceLocation: sourceLocation)
}

func expectContainsNote(_ voicing: Voicing, _ note: Int,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(voicing.notes.contains(note),
            "Expected \(voicing.notes) to contain \(note)",
            sourceLocation: sourceLocation)
}
