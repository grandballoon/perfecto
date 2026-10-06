import Testing
@testable import Perfecto

@Suite("SynthPreset")
@MainActor
struct SynthPresetTests {

    @Test func offersABeginnerSynthsWorthOfSounds() {
        #expect((10...15).contains(SynthPreset.allCases.count))
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

    /// The limits a `SynthVoice` can realize: at least one source, no more
    /// oscillators than a voice has, and levels a full chord can sum without
    /// leaning on the limiter.
    @Test(arguments: SynthPreset.allCases)
    func patchFitsAVoice(_ preset: SynthPreset) {
        let patch = preset.patch
        #expect(!patch.oscillators.isEmpty || patch.fm != nil)
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
    }
}
