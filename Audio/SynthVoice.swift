import AudioKit
import Darwin
import SoundpipeAudioKit

/// One polyphonic voice: a waveform oscillator shaped by an ADSR amplitude envelope.
/// Connect `node` (the envelope output) to a Mixer.
final class SynthVoice {

    /// Output node to wire into the Mixer.
    let node: AmplitudeEnvelope
    private let oscillator: Oscillator

    init(waveform: Table = Table(.sine)) {
        oscillator = Oscillator(waveform: waveform)
        node = AmplitudeEnvelope(oscillator)
        // Sine pad defaults — fast enough to feel responsive, slow enough to avoid clicks
        node.attackDuration  = 0.02
        node.decayDuration   = 0.08
        node.sustainLevel    = 0.75
        node.releaseDuration = 0.35
    }

    /// Call once after the AudioEngine is started to activate the oscillator.
    func prepare() {
        oscillator.start()
    }

    private var presetAmplitude: AUValue = 0.25

    func applyEnvelope(from preset: SynthPreset) {
        presetAmplitude      = preset.amplitude
        node.attackDuration  = preset.attack
        node.decayDuration   = preset.decay
        node.sustainLevel    = preset.sustain
        node.releaseDuration = preset.release
    }

    func noteOn(midiNote: Int) {
        oscillator.frequency = midiToHz(midiNote)
        oscillator.amplitude = presetAmplitude
        node.openGate()
    }

    func noteOff() {
        node.closeGate()
    }

    private func midiToHz(_ note: Int) -> AUValue {
        440.0 * pow(2.0, AUValue(note - 69) / 12.0)
    }
}
