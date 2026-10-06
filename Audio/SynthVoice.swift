import AudioKit
import Darwin
import SoundpipeAudioKit

/// One polyphonic voice. Its signal path is fixed (see `SynthPatch`), so
/// changing sound only changes parameters and the audio graph never has to be
/// rewired while the engine runs. Connect `node` to a Mixer.
final class SynthVoice {

    /// Output node to wire into the Mixer.
    let node: AmplitudeEnvelope

    private let oscillators: [DynamicOscillator]
    private let fm = FMOscillator()
    private let filter: MoogLadder
    private var patch: SynthPatch

    /// The filter's working range; cutoffs follow the note but stay inside it.
    private static let cutoffRange: ClosedRange<AUValue> = 60...18_000

    init(patch: SynthPatch) {
        self.patch = patch
        oscillators = (0..<SynthPatch.oscillatorCount).map { _ in DynamicOscillator() }
        let sources: [Node] = oscillators + [fm]
        filter = MoogLadder(Mixer(sources))
        node = AmplitudeEnvelope(filter)
        apply(patch)
    }

    /// Switches this voice to `patch`. Sources the patch doesn't use are
    /// stopped, so they cost nothing.
    func apply(_ patch: SynthPatch) {
        self.patch = patch

        for (i, oscillator) in oscillators.enumerated() {
            guard i < patch.oscillators.count else { oscillator.stop(); continue }
            oscillator.setWaveform(Self.table(patch.oscillators[i].wave))
            oscillator.amplitude = 0
            oscillator.start()
        }

        fm.amplitude = 0
        if let fmPatch = patch.fm {
            fm.carrierMultiplier = fmPatch.carrier
            fm.modulatingMultiplier = fmPatch.modulator
            fm.start()
        } else {
            fm.stop()
        }

        if let filterPatch = patch.filter {
            filter.resonance = filterPatch.resonance
            filter.start()
        } else {
            filter.bypass()
        }

        node.attackDuration  = patch.envelope.attack
        node.decayDuration   = patch.envelope.decay
        node.sustainLevel    = patch.envelope.sustain
        node.releaseDuration = patch.envelope.release
    }

    func noteOn(midiNote: Int) {
        let hz = midiToHz(midiNote)

        // Source levels share the patch's level, so layering oscillators
        // thickens a sound without making it louder.
        let total = patch.oscillators.reduce(patch.fm?.level ?? 0) { $0 + $1.level }
        let gain = total > 0 ? patch.level / total : 0

        for (oscillator, part) in zip(oscillators, patch.oscillators) {
            oscillator.frequency = hz * pow(2, AUValue(part.octave) + part.detuneCents / 1200)
            oscillator.amplitude = part.level * gain
        }
        if let fmPatch = patch.fm {
            fm.baseFrequency = hz
            fm.amplitude = fmPatch.level * gain
            start(fmPatch.index, on: fm.$modulationIndex) { $0 }
        }
        if let filterPatch = patch.filter {
            start(filterPatch.cutoff, on: filter.$cutoffFrequency) {
                ($0 * hz).clamped(to: Self.cutoffRange)
            }
        }
        node.openGate()
    }

    func noteOff() {
        node.closeGate()
    }

    /// Restarts `sweep` on `parameter`, mapping its values through `scale`.
    private func start(_ sweep: SynthPatch.Sweep, on parameter: NodeParameter,
                       scale: (AUValue) -> AUValue) {
        parameter.value = scale(sweep.from)
        if sweep.to != sweep.from {
            parameter.ramp(to: scale(sweep.to), duration: sweep.time)
        }
    }

    private func midiToHz(_ note: Int) -> AUValue {
        440.0 * pow(2.0, AUValue(note - 69) / 12.0)
    }

    private static func table(_ wave: SynthPatch.Wave) -> Table {
        switch wave {
        case .sine:     return Table(.sine)
        case .triangle: return Table(.triangle)
        case .square:   return Table(.square)
        case .sawtooth: return Table(.sawtooth)
        case let .pulse(width):
            return Table(waveSamples { $0 < width ? 1 : -1 })
        case let .harmonics(levels):
            return Table(waveSamples { phase in
                levels.enumerated().reduce(0) { sum, partial in
                    sum + partial.element * sin(2 * .pi * phase * Float(partial.offset + 1))
                }
            })
        }
    }

    /// One cycle of `wave` (a function of phase, 0..<1), scaled to peak at 1
    /// like the standard tables.
    private static func waveSamples(_ wave: (Float) -> Float) -> [Float] {
        let count = 4096
        let samples = (0..<count).map { wave(Float($0) / Float(count)) }
        let peak = samples.map(abs).max() ?? 0
        return peak > 0 ? samples.map { $0 / peak } : samples
    }
}
