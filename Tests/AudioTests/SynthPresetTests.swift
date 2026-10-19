import PerfectoKernel
import Testing
@testable import Perfecto

@Suite("SynthPreset")
@MainActor
struct SynthPresetTests {

    @Test func offersABeginnerSynthsWorthOfSounds() {
        #expect((10...30).contains(SynthPreset.allCases.count))
    }

    @Test func everySoundHasItsOwnNameAndPatch() {
        let presets = SynthPreset.allCases
        #expect(Set(presets.map(\.name)).count == presets.count)
        for (i, a) in presets.enumerated() {
            for b in presets[(i + 1)...] {
                #expect(a.patch != b.patch, "\(a.name) and \(b.name) are the same patch")
            }
        }
    }

    @Test func everyCategoryListsItsSoundsAndNoSoundIsLeftOut() {
        for category in SynthPreset.Category.allCases {
            #expect(!category.presets.isEmpty)
        }
        let listed = SynthPreset.Category.allCases.flatMap(\.presets)
        #expect(listed.count == SynthPreset.allCases.count)
    }

    @Test func theStartingSoundIsOffered() {
        #expect(SynthPreset.allCases.contains(.initial))
    }

    /// The limits a kernel voice can realize: at least one source, no more
    /// oscillators than a voice has, and levels a full chord can sum without
    /// leaning on the limiter.
    @Test(arguments: SynthPreset.allCases)
    func patchFitsAVoice(_ preset: SynthPreset) {
        let patch = preset.patch
        #expect(!patch.oscillators.isEmpty || patch.fm != nil || patch.sample != nil)
        #expect(patch.oscillators.count <= SynthPatch.oscillatorCount)
        #expect(patch.oscillators.allSatisfy { $0.level > 0 })
        #expect(patch.level > 0)
        // A full chord on its own stays near what the output carries; layers past that are the limiter's.
        #expect(patch.level * 8 <= 2.5)

        #expect(patch.envelope.attack > 0)
        #expect(patch.envelope.decay > 0)
        #expect(patch.envelope.release > 0)
        #expect((0...1).contains(patch.envelope.sustain))

        if let filter = patch.filter {
            #expect(filter.cutoff.from > 0 && filter.cutoff.to > 0)
            #expect((0...1).contains(filter.resonance))
        }
        if let fm = patch.fm {
            #expect(fm.carrier > 0 && fm.modulator > 0)
            #expect(fm.index.from >= 0 && fm.index.to >= 0)
        }
        if let unison = patch.unison {
            #expect((2...SynthPatch.unisonLimit).contains(unison.voices))
            #expect(unison.spreadCents > 0)
            #expect(patch.sample == nil)
        }
        #expect(patch.driftCents >= 0)
        #expect(patch.glide >= 0 && (0...1).contains(patch.drive))
        if let noise = patch.noise { #expect(noise.from >= 0 && noise.to >= 0 && noise.from + noise.to > 0) }
        // An LFO moves something the patch has, and no pulse out of its range.
        if let lfo = patch.lfo {
            #expect(lfo.rate > 0 && lfo.rise >= 0)
            #expect(lfo.pitchCents != 0 || lfo.pulseWidth != 0 || lfo.cutoffOctaves != 0)
            if lfo.cutoffOctaves != 0 { #expect(patch.filter != nil) }
            let widths = patch.oscillators.compactMap { oscillator -> Float? in
                if case let .pulse(width) = oscillator.wave { return width }
                return nil
            }
            if lfo.pulseWidth != 0 { #expect(!widths.isEmpty) }
            for width in widths {
                #expect(width - abs(lfo.pulseWidth) > 0 && width + abs(lfo.pulseWidth) < 1)
            }
        }
    }

    @Test func aPatchsUnisonAndDriftAreTheKernels() {
        var patch = SynthPatch(
            oscillators: [.init(wave: .sawtooth)],
            unison: .init(voices: 5, spreadCents: 18),
            driftCents: 6,
            envelope: .init(attack: 0.01, decay: 0.1, sustain: 1, release: 0.1),
            level: 0.2)
        #expect(patch.kernelPatch.unison == 5 && patch.kernelPatch.spread == 18)
        #expect(patch.kernelPatch.drift == 6)
        patch.unison = nil
        patch.driftCents = 0
        #expect(patch.kernelPatch.unison == 0 && patch.kernelPatch.drift == 0)
        #expect(SynthPatch.unisonLimit == Int(PerfectoUnisonCount))
    }

    @Test func aPatchsNoiseGlideAndDriveAreTheKernels() {
        let patch = SynthPatch(
            oscillators: [.init(wave: .sawtooth)],
            noise: .init(from: 0.3, to: 0.1, time: 0.2),
            glide: 0.05,
            drive: 0.6,
            envelope: .init(attack: 0.01, decay: 0.1, sustain: 1, release: 0.1),
            level: 0.2).kernelPatch
        #expect(patch.noise.from == 0.3 && patch.noise.to == 0.1 && patch.noise.time == 0.2)
        #expect(patch.glide == 0.05 && patch.drive == 0.6)
    }

    @Test func aPatchsLfoIsTheKernels() {
        let patch = SynthPatch(
            oscillators: [.init(wave: .pulse(width: 0.5))],
            lfo: .init(rate: 5, rise: 0.4, pitchCents: 12, pulseWidth: 0.3, cutoffOctaves: 1),
            envelope: .init(attack: 0.01, decay: 0.1, sustain: 1, release: 0.1),
            level: 0.2)
        let lfo = patch.kernelPatch.lfo
        #expect(lfo.rate == 5 && lfo.rise == 0.4)
        #expect(lfo.pitch == 12 && lfo.pulse_width == 0.3 && lfo.cutoff == 1)
        var still = patch
        still.lfo = nil
        #expect(still.kernelPatch.lfo.rate == 0)
    }
}
