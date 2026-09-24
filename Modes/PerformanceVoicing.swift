/// How Perfecto voices every chord it plays: root position, voice leading off.
///
/// The one place those performance settings live, shared by live playback
/// (`PerformanceState`) and offline rendering (`SequencerMidiRenderer`), so an
/// exported pattern always contains exactly the notes that were heard.
func performanceVoicing(key: Key,
                        octave: Int,
                        degree: Degree,
                        joystickMode: JoystickMode,
                        joystickDirection: JoystickDirection,
                        previousVoicing: Voicing?) -> Voicing {
    computeVoicing(
        key: key,
        degree: degree,
        joystickMode: joystickMode,
        joystickDirection: joystickDirection,
        inversion: .root,
        octave: octave,
        voiceLeading: false,
        previousVoicing: previousVoicing
    )
}
