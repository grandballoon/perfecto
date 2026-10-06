/// How Perfecto voices every chord it plays: root position, voice leading off.
///
/// The one place those performance settings live, shared by live playback
/// (`PerformanceState`) and offline rendering (`SequencerMidiRenderer`), so an
/// exported pattern always contains exactly the notes that were heard, and a
/// ChordLink frame always describes the settings that produced its notes.
func performanceContext(key: Key, octave: Int, spec: ChordSpec) -> ChordContext {
    ChordContext(key: key, spec: spec, octave: octave, inversion: .root, voiceLeading: false)
}

/// The single note Lead mode plays for `degree`: the scale degree itself, in
/// the octave the chords are built from.
func leadPitch(key: Key, octave: Int, degree: Degree) -> Int {
    key.root.rawValue + (octave + 1) * 12 + key.scale.offset(of: degree)
}

func performanceVoicing(key: Key,
                        octave: Int,
                        spec: ChordSpec,
                        previousVoicing: Voicing?) -> Voicing {
    performanceContext(key: key, octave: octave, spec: spec).voicing(after: previousVoicing)
}
