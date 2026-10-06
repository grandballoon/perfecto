import Foundation
import PerfectoKernel
import Testing

/// What a patch makes of a note: its waves, the modulation between its
/// operators, its filter, its envelope, and the note's own brightness.
@Suite("Kernel sounds")
struct SoundTests {

    /// A second of a held note of `patch`, as sound number 1.
    private func held(_ patch: PerfectoPatch, note: Int = 57, brightness: Float = 1,
                      seconds: Double = 1) -> KernelRig {
        let rig = KernelRig()
        rig.setSound(1, patch)
        rig.noteOn(1, note: note, sound: 1, brightness: brightness)
        rig.render(frames(seconds))
        return rig
    }

    /// The part of a held second where the note has settled.
    private let settled = 24_000..<48_000

    /// The strengths of the first `count` partials of `note`, each as a
    /// share of the first.
    private func partials(_ rig: KernelRig, note: Int, count: Int) -> [Double] {
        let first = rig.strength(of: hz(note), in: settled)
        return (1...count).map { rig.strength(of: hz(note) * Double($0), in: settled) / first }
    }

    // MARK: – Waves

    @Test func theNamedWavesHaveTheirPartials() {
        let saw = partials(held(.wave(PerfectoWaveSawtooth)), note: 57, count: 6)
        for (index, strength) in saw.enumerated() {
            #expect(abs(strength - 1 / Double(index + 1)) < 0.01, "saw partial \(index + 1)")
        }
        let square = partials(held(.wave(PerfectoWaveSquare)), note: 57, count: 5)
        #expect(abs(square[2] - 1.0 / 3) < 0.01 && abs(square[4] - 1.0 / 5) < 0.01)
        #expect(square[1] < 0.005 && square[3] < 0.005)                  // no even partials
        let triangle = partials(held(.wave(PerfectoWaveTriangle)), note: 57, count: 5)
        #expect(abs(triangle[2] - 1.0 / 9) < 0.01 && abs(triangle[4] - 1.0 / 25) < 0.01)
        #expect(triangle[1] < 0.005)
        let sine = partials(held(.wave(PerfectoWaveSine)), note: 57, count: 4)
        #expect(sine.dropFirst().allSatisfy { $0 < 0.005 })
    }

    @Test func aPulseOfHalfWidthIsASquareAndANarrowOneHasEvenPartials() {
        let half = partials(held(.wave(PerfectoWavePulse, pulseWidth: 0.5)), note: 57, count: 3)
        #expect(half[1] < 0.005 && abs(half[2] - 1.0 / 3) < 0.01)
        let narrow = partials(held(.wave(PerfectoWavePulse, pulseWidth: 0.2)), note: 57, count: 3)
        #expect(narrow[1] > 0.5)
    }

    /// A narrow pulse, which sits mostly to one side of zero, still peaks
    /// at the patch's level (and a little over, as every sharp edge made of
    /// a limited number of partials does).
    @Test(arguments: [0.1, 0.2, 0.5, 0.8] as [Float])
    func aPulsePeaksAtTheLevelWhateverItsWidth(width: Float) {
        let peak = held(.wave(PerfectoWavePulse, pulseWidth: width, level: 0.5), note: 45).loudest(settled)
        #expect(peak > 0.5 * 0.97 && peak < 0.5 * 1.2, "\(peak)")
    }

    /// A wave given as partials has those partials, and peaks at the
    /// patch's level whatever they add up to.
    @Test func aWaveOfPartialsHasThemAndPeaksAtTheLevel() {
        let rig = held(.wave(PerfectoWavePartials, partials: [1, 0, 0.5, 0, 0, 0.25], level: 0.3))
        let found = partials(rig, note: 57, count: 6)
        #expect(abs(found[2] - 0.5) < 0.01 && abs(found[5] - 0.25) < 0.01)
        #expect(found[1] < 0.005 && found[3] < 0.005)
        #expect(abs(Double(rig.loudest(settled)) - 0.3) < 0.01)
    }

    /// A partial over half the sample rate cannot be played: left in, it
    /// folds back as a tone that belongs to no note. High notes are where it
    /// shows, so a high sawtooth must be nothing but its own partials.
    @Test(arguments: [84, 96, 103, 108])
    func aHighSawtoothHasNoFalseTones(note: Int) {
        let rig = held(.wave(PerfectoWaveSawtooth), note: note)
        let own = (1...40).map { hz(note) * Double($0) }.filter { $0 < KernelRig.sampleRate / 2 }
        let stray = rig.remainder(without: own, in: settled)
        #expect(stray < rig.power(settled) * 0.003, "\(20 * log10(stray / rig.power(settled))) dB")
    }

    /// A low note keeps the high partials a high note has to drop.
    @Test func aLowNoteKeepsItsHighPartials() {
        let low = held(.wave(PerfectoWaveSawtooth), note: 33)                // 55 Hz
        let found = partials(low, note: 33, count: 200)
        #expect(abs(found[99] - 0.01) < 0.002)                               // partial 100, at 5.5 kHz
        #expect(abs(found[199] - 0.005) < 0.002)                             // partial 200, at 11 kHz
    }

    // MARK: – Operators

    /// Two operators share the patch's level, so layering thickens a sound
    /// without making it louder.
    @Test func twoOperatorsShareTheLevel() {
        var patch = PerfectoPatch.wave(PerfectoWaveSine, level: 0.4)
        patch.operators.1 = patch.operators.0
        patch.operators.1.ratio = 2
        patch.operators.1.level = 3
        let rig = held(patch)
        #expect(abs(rig.strength(of: hz(57), in: settled) - 0.1) < 0.002)
        #expect(abs(rig.strength(of: hz(57) * 2, in: settled) - 0.3) < 0.002)
    }

    @Test func anOperatorCanBeDetuned() {
        var patch = PerfectoPatch.wave(PerfectoWaveSine)
        patch.operators.0.ratio = Float(pow(2, 7.0 / 12))                    // a fifth up
        let rig = held(patch)
        #expect(rig.strength(of: hz(64), in: settled) > 0.49)
        #expect(rig.strength(of: hz(57), in: settled) < 0.005)
    }

    /// Bending a sine by another puts partials either side of it, the
    /// modulator's pitch apart, and the modulator is not heard itself.
    @Test func aModulatedSineHasSidebands() {
        let plain = held(.modulated(ratio: 3, index: .steady(0)))
        #expect(abs(plain.strength(of: hz(57), in: settled) - 0.5) < 0.005)
        #expect(plain.strength(of: hz(57) * 3, in: settled) < 0.002)

        let bent = held(.modulated(ratio: 3, index: .steady(1)))
        // With index 1, the carrier is J0(1) = 0.765 of itself and the first
        // sidebands, at 2 and 4 times the pitch, are J1(1) = 0.440.
        #expect(abs(bent.strength(of: hz(57), in: settled) - 0.5 * 0.765) < 0.005)
        #expect(abs(bent.strength(of: hz(57) * 4, in: settled) - 0.5 * 0.440) < 0.005)
        #expect(abs(bent.strength(of: hz(57) * 2, in: settled) - 0.5 * 0.440) < 0.005)
    }

    /// The index swept down gives the bright attack and plain tail of a
    /// struck sound.
    @Test func theIndexSweepsOverTheNote() {
        let rig = held(.modulated(ratio: 3, index: PerfectoSweep(from: 2, to: 0, time: 0.25)))
        #expect(rig.strength(of: hz(57) * 4, in: 1200..<3600) > 0.1)
        #expect(rig.strength(of: hz(57) * 4, in: settled) < 0.002)
        #expect(abs(rig.strength(of: hz(57), in: settled) - 0.5) < 0.005)
    }

    // MARK: – Filter

    @Test func theFilterTakesTheHighPartialsOut() {
        let open = partials(held(.wave(PerfectoWaveSawtooth)), note: 57, count: 8)
        let closed = partials(held(PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: .steady(2))), note: 57, count: 8)
        #expect(closed[7] < open[7] * 0.1)                                   // two octaves over the cutoff
        #expect(closed[1] > open[1] * 0.6)                                   // at the cutoff, 3 dB down
    }

    /// The cutoff is a multiple of the note's pitch, so a patch is as
    /// bright in every octave.
    @Test func theFilterFollowsTheNote() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: .steady(3))
        let low = partials(held(patch, note: 45), note: 45, count: 6)
        let high = partials(held(patch, note: 69), note: 69, count: 6)
        for index in 0..<6 { #expect(abs(low[index] - high[index]) < 0.02, "partial \(index + 1)") }
    }

    @Test func theCutoffSweepsOverTheNote() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth)
            .filtered(cutoff: PerfectoSweep(from: 16, to: 1, time: 0.25))
        let rig = held(patch)
        let early = rig.strength(of: hz(57) * 6, in: 600..<3000)
        let late = rig.strength(of: hz(57) * 6, in: settled)
        #expect(late < early * 0.1)
    }

    /// A steep filter takes twice as much off, octave for octave, and
    /// leaves what is under the cutoff as it was.
    @Test func aSteepFilterFallsAwayTwiceAsFast() {
        let saw = PerfectoPatch.wave(PerfectoWaveSawtooth)
        let open = partials(held(saw, note: 45), note: 45, count: 16)
        let gentle = partials(held(saw.filtered(cutoff: .steady(4)), note: 45), note: 45, count: 16)
        let steep = partials(held(saw.filtered(cutoff: .steady(4), steep: true), note: 45), note: 45, count: 16)
        // Two octaves over the cutoff: 24 dB down, and 48.
        #expect(abs(20 * log10(gentle[15] / open[15]) + 24) < 2)
        #expect(abs(20 * log10(steep[15] / open[15]) + 48) < 3)
        // An octave under it: untouched by either.
        #expect(abs(gentle[1] / open[1] - 1) < 0.05 && abs(steep[1] / open[1] - 1) < 0.05)
        // At the cutoff both are 3 dB down: flat right up to it.
        #expect(abs(20 * log10(steep[3] / open[3]) + 3) < 1)
    }

    @Test(arguments: [0, 24, 108, 127])
    func theSteepFilterIsStableAtItsExtremes(note: Int) {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth)
            .filtered(cutoff: PerfectoSweep(from: 1000, to: 0.01, time: 0.01), resonance: 1, steep: true)
        let rig = held(patch, note: note, seconds: 0.5)
        #expect(rig.output.allSatisfy { $0.isFinite && abs($0) < 20 })
    }

    @Test func resonanceRaisesWhatIsAtTheCutoff() {
        let flat = held(PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: .steady(4)))
        let ringing = held(PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: .steady(4), resonance: 0.7))
        #expect(ringing.strength(of: hz(57) * 4, in: settled) > flat.strength(of: hz(57) * 4, in: settled) * 3)
        #expect(ringing.output.allSatisfy { $0.isFinite })
    }

    /// Swept as fast as a patch can ask, at full resonance, on the highest
    /// and lowest notes, the filter stays in bounds.
    @Test(arguments: [0, 24, 108, 127])
    func theFilterIsStableAtItsExtremes(note: Int) {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth)
            .filtered(cutoff: PerfectoSweep(from: 1000, to: 0.01, time: 0.01), resonance: 1)
        let rig = held(patch, note: note, seconds: 0.5)
        #expect(rig.output.allSatisfy { $0.isFinite && abs($0) < 10 })
    }

    // MARK: – Envelope

    private func level(_ rig: KernelRig, at seconds: Double) -> Double {
        let middle = frames(seconds)
        return Double(rig.loudest(middle - 110..<middle + 110))              // two cycles of the note
    }

    @Test func theAttackReachesFullLevelOnTime() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSine).envelope(attack: 0.2, decay: 1, sustain: 1, release: 0.1))
        #expect(level(rig, at: 0.05) < 0.3)
        #expect(level(rig, at: 0.1) > 0.3 && level(rig, at: 0.1) < 0.45)
        #expect(abs(level(rig, at: 0.21) - 0.5) < 0.005)
    }

    /// A decay or release time is the time in which the level covers 63% of
    /// the way to where it is going.
    @Test func theLevelFallsToTheSustainAtTheDecaysPace() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSine).envelope(attack: 0.002, decay: 0.2, sustain: 0.4, release: 0.1))
        let covered = 0.5 * (0.4 + 0.6 * exp(-1.0))
        #expect(abs(level(rig, at: 0.202) - covered) < 0.01)
        #expect(abs(level(rig, at: 0.95) - 0.5 * 0.4) < 0.005)
    }

    @Test func aStruckSoundDiesAwayWhileItsKeyIsHeld() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSine).envelope(attack: 0.002, decay: 0.05, sustain: 0, release: 0.05))
        #expect(level(rig, at: 0.01) > 0.35)
        #expect(level(rig, at: 0.9) < 0.0001)
    }

    @Test func aNoteDiesAwayAtItsReleasesPaceAndThenIsSilent() {
        let rig = KernelRig()
        rig.setSound(1, PerfectoPatch.wave(PerfectoWaveSine).envelope(attack: 0.002, decay: 0.1, sustain: 1, release: 0.1))
        rig.noteOn(1, note: 57, sound: 1)
        rig.noteOff(1, at: 9600)
        rig.render(96_000)
        #expect(abs(level(rig, at: 0.2 + 0.1) - 0.5 * exp(-1.0)) < 0.01)
        #expect(level(rig, at: 0.2 + 0.5) < 0.005)
        #expect(rig.loudest(frames(0.2 + 1.0)..<96_000) == 0)                // 80 dB down: the voice is free
    }

    // MARK: – Brightness

    /// A note's brightness is its own low-pass: dark takes the highs off
    /// and leaves the lows.
    @Test func aDarkNoteLosesItsHighPartials() {
        let open = partials(held(.wave(PerfectoWaveSawtooth)), note: 57, count: 20)
        let dark = partials(held(.wave(PerfectoWaveSawtooth), brightness: 0), note: 57, count: 20)
        #expect(dark[19] < open[19] * 0.02)                                  // 4.4 kHz, under a 300 Hz cutoff
        let (openLevel, darkLevel) = (held(.wave(PerfectoWaveSawtooth)).strength(of: hz(57), in: settled),
                                      held(.wave(PerfectoWaveSawtooth), brightness: 0).strength(of: hz(57), in: settled))
        #expect(darkLevel > openLevel * 0.6)
    }

    /// Notes do not share a filter: a dark note and an open one together
    /// sound exactly as each does alone.
    @Test func eachNoteHasItsOwnBrightness() {
        func performance(dark: Bool, open: Bool) -> [Float] {
            let rig = KernelRig()
            rig.setSound(1, .wave(PerfectoWaveSawtooth, level: 0.2))
            if dark { rig.noteOn(1, note: 57, sound: 1, brightness: 0.1) }
            if open { rig.noteOn(2, note: 64, sound: 1, brightness: 1, at: 1000) }
            rig.render(9600)
            return rig.output
        }
        let (dark, open, both) = (performance(dark: true, open: false), performance(dark: false, open: true),
                                  performance(dark: true, open: true))
        for frame in 0..<9600 {
            #expect(abs(both[frame] - (dark[frame] + open[frame])) < 1e-5)
            if abs(both[frame] - (dark[frame] + open[frame])) >= 1e-5 { break }
        }
    }

    /// A change of brightness is glided to: no step in the sound, and it
    /// ends as a note played at that brightness sounds.
    @Test func aChangeOfBrightnessIsGlidedTo() {
        let rig = KernelRig()
        rig.setSound(1, .wave(PerfectoWaveSawtooth))
        rig.noteOn(1, note: 57, sound: 1, brightness: 0)
        rig.noteChange(1, brightness: 1, at: 12_000)
        rig.render(48_000)

        let openNote = held(.wave(PerfectoWaveSawtooth))
        let open = openNote.strength(of: hz(57) * 10, in: settled)
        #expect(rig.strength(of: hz(57) * 10, in: 6000..<12_000) < open * 0.1)
        #expect(abs(rig.strength(of: hz(57) * 10, in: settled) - open) < open * 0.02)

        // A sawtooth's edge is as steep as the sound is bright. Just after
        // the change it is still far from as steep as it will be: the
        // brightness is on its way, and has not jumped.
        let edge = openNote.biggestStep(settled)
        #expect(rig.biggestStep(6000..<12_000) < edge * 0.2)
        #expect(rig.biggestStep(12_000..<12_240) < edge * 0.5)
        #expect(abs(rig.biggestStep(settled) - edge) < edge * 0.05)
    }

    // MARK: – Sounds

    @Test func aSoundNeverSetIsAPlainSine() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57, sound: 40)
        rig.noteOn(2, note: 57, sound: -3)
        rig.noteOn(3, note: 57, sound: 10_000)
        rig.setSound(10_000, .wave(PerfectoWaveSawtooth))                    // no such number: ignored
        rig.render(48_000)
        #expect(abs(rig.strength(of: hz(57), in: settled) - 0.6) < 0.005)
        #expect(rig.strength(of: hz(57) * 2, in: settled) < 0.002)
    }

    @Test func notesNameTheirSounds() {
        let rig = KernelRig()
        rig.setSound(0, .wave(PerfectoWaveSine, level: 0.3))
        rig.setSound(5, .wave(PerfectoWaveSquare, level: 0.3))
        rig.noteOn(1, note: 57, sound: 0)
        rig.noteOn(2, note: 69, sound: 5)
        rig.render(48_000)
        #expect(rig.strength(of: hz(57) * 3, in: settled) < 0.002)           // the sine has no third partial
        #expect(rig.strength(of: hz(69) * 3, in: settled) > 0.1)             // the square has
    }

    /// The whole pool playing the costliest kind of patch, through the
    /// chorus and the reverb, renders faster than it is heard even built for
    /// testing and with other tests running beside it. (Built to run, on a
    /// Mac, a second takes about 40 ms.) The budget on a phone, a quarter of
    /// each render cycle, is measured on the device.
    @Test func everyVoiceRendersFasterThanItIsHeard() {
        let rig = KernelRig()
        var patch = PerfectoPatch.wave(PerfectoWaveSawtooth, level: 0.01)
            .filtered(cutoff: PerfectoSweep(from: 12, to: 2, time: 0.5), resonance: 0.4)
        patch.operators.1 = patch.operators.0
        patch.operators.1.ratio = 1.003
        rig.setSound(1, patch)
        for id in 1...Int(perfecto_kernel_voice_count()) {
            rig.noteOn(UInt64(id), note: 36 + id % 48, sound: 1, brightness: 0.5,
                       pan: Float(id % 3) - 1, chorus: 0.5, reverb: 0.3)
        }
        let clock = ContinuousClock()
        let taken = clock.measure { rig.render(48_000) }
        #expect(taken < .seconds(1), "\(taken) to render a second")
        #expect(rig.output.allSatisfy { $0.isFinite })
    }
}
