/// How the keys' chords are voiced: the octave they are built in and how
/// far they are rolled from root position (`Inversion`). The two are one
/// setting on the play screen, set together by one finger (`VoicingField`).
struct KeyVoicing: Equatable, Sendable {
    var octave: Int
    var inversion: Inversion

    /// This voicing, `bend` from where it is.
    func bent(by bend: VoicingBend) -> KeyVoicing {
        KeyVoicing(octave: octave + bend.octaves, inversion: inversion.rolled(by: bend.steps))
    }

    /// How far `other` is from this voicing.
    func bend(to other: KeyVoicing) -> VoicingBend {
        VoicingBend(octaves: other.octave - octave, steps: other.inversion.steps - inversion.steps)
    }
}

/// How far the keys' chords are held from the voicing that is set, while a
/// finger is on a voicing field that does not keep what it is set to
/// (`PerformanceState.keepsVoicing`): octaves up, and steps rolled.
struct VoicingBend: Equatable, Sendable {
    var octaves = 0
    var steps = 0

    static let none = VoicingBend()
}
