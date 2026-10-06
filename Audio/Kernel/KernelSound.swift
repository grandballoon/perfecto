import Foundation
import PerfectoKernel

/// A `SynthPatch` as the kernel takes it: two operators, mixed or one
/// bending the other, or a recording in their place.
///
/// A patch here is either oscillators or an FM pair, and each becomes the
/// kernel's two operators: the oscillators mixed, or the pair's modulator
/// bending its carrier. A patch with both has no kernel form (none of the
/// app's sounds is one); its oscillators are the ones dropped.
extension SynthPatch {

    var kernelPatch: PerfectoPatch {
        var patch = PerfectoPatch()
        if let sample {
            patch.sampled = true
            patch.capture = Int32(sample.capture)
            patch.root = Float(sample.root)
        } else if let fm {
            patch.operators.0 = Self.kernelOperator(.sine, ratio: fm.carrier, level: 1)
            patch.operators.1 = Self.kernelOperator(.sine, ratio: fm.modulator, level: 1)
            patch.modulates = true
            patch.index = fm.index.kernelSweep
        } else {
            let parts = oscillators.prefix(Self.oscillatorCount).map {
                Self.kernelOperator($0.wave, ratio: pow(2, Float($0.octave) + $0.detuneCents / 1200), level: $0.level)
            }
            if parts.count > 0 { patch.operators.0 = parts[0] }
            if parts.count > 1 { patch.operators.1 = parts[1] }
        }
        if let filter {
            patch.filtered = true
            patch.cutoff = filter.cutoff.kernelSweep
            patch.resonance = filter.resonance
            patch.steep = filter.isSteep
        }
        patch.attack = envelope.attack
        patch.decay = envelope.decay
        patch.sustain = envelope.sustain
        patch.release = envelope.release
        patch.level = level
        return patch
    }

    private static func kernelOperator(_ wave: Wave, ratio: Float, level: Float) -> PerfectoOperator {
        var op = PerfectoOperator()
        op.ratio = ratio
        op.level = level
        switch wave {
        case .sine:     op.wave = PerfectoWaveSine
        case .triangle: op.wave = PerfectoWaveTriangle
        case .square:   op.wave = PerfectoWaveSquare
        case .sawtooth: op.wave = PerfectoWaveSawtooth
        case let .pulse(width):
            op.wave = PerfectoWavePulse
            op.pulse_width = width
        case let .harmonics(levels):
            op.wave = PerfectoWavePartials
            withUnsafeMutableBytes(of: &op.partials) { bytes in
                let partials = bytes.bindMemory(to: Float.self)
                for (index, level) in levels.prefix(partials.count).enumerated() { partials[index] = level }
            }
        }
        return op
    }
}

private extension SynthPatch.Sweep {
    var kernelSweep: PerfectoSweep { PerfectoSweep(from: from, to: to, time: time) }
}
