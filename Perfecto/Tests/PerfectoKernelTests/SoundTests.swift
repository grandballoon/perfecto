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

    // MARK: – LFO

    /// The frames within `spread` seconds of `seconds`.
    private func around(_ seconds: Double, spread: Double = 0.05) -> Range<Int> {
        frames(seconds - spread)..<frames(seconds + spread)
    }

    /// An LFO of half a cycle a second is at its top half a second into the
    /// note and at its bottom a second later.
    @Test func theLfoMovesThePitchUpAndDownByItsDepth() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSine).lfo(rate: 0.5, pitch: 100), note: 81, seconds: 2)
        #expect(rig.strength(of: hz(82), in: around(0.5)) > 0.4)
        #expect(rig.strength(of: hz(81), in: around(0.5)) < 0.1)
        #expect(rig.strength(of: hz(80), in: around(1.5)) > 0.4)
        #expect(rig.strength(of: hz(81), in: around(1, spread: 0.01)) > 0.4)
    }

    /// Both operators move together, so a modulated sound keeps its
    /// partials where they belong to its pitch.
    @Test func theLfoMovesAModulatorWithItsCarrier() {
        let patch = PerfectoPatch.modulated(ratio: 3, index: .steady(1)).lfo(rate: 0.5, pitch: 100)
        let rig = held(patch, note: 69, seconds: 1)
        #expect(abs(rig.strength(of: hz(70) * 4, in: around(0.5)) - 0.5 * 0.440) < 0.03)
    }

    @Test func theLfoComesUpToItsDepthOverItsRise() {
        let patch = PerfectoPatch.wave(PerfectoWaveSine).lfo(rate: 0.5, rise: 2, pitch: 100)
        let rig = held(patch, note: 81, seconds: 1)
        // A quarter of the way up its rise at its first top: 25 cents.
        #expect(rig.strength(of: hz(81) * pow(2, 25.0 / 1200), in: around(0.5)) > 0.4)
        #expect(rig.strength(of: hz(82), in: around(0.5)) < 0.1)
    }

    /// A square has no even partials and a pulse of any other width has:
    /// the second partial comes and goes as the width moves.
    @Test func theLfoMovesAPulsesWidth() {
        let patch = PerfectoPatch.wave(PerfectoWavePulse, pulseWidth: 0.5).lfo(rate: 0.5, pulseWidth: 0.3)
        let rig = held(patch, note: 81, seconds: 2.5)
        func second(at seconds: Double) -> Double {
            let range = around(seconds, spread: 0.01)
            return rig.strength(of: hz(81) * 2, in: range) / rig.strength(of: hz(81), in: range)
        }
        #expect(second(at: 0.5) > 0.5)                                       // 0.8 wide
        #expect(second(at: 1.5) > 0.5)                                       // 0.2 wide
        #expect(second(at: 2) < 0.1)                                         // a square again
        // It peaks at the patch's level at every width on the way (a low
        // note, whose edges have the partials to be sharp).
        let peak = held(patch, note: 45, seconds: 2.5).loudest(frames(0.2)..<frames(2.5))
        #expect(peak > 0.5 * 0.97 && peak < 0.5 * 1.2, "\(peak)")
    }

    /// A pulse's width is moved a little every frame, so its edge never
    /// jumps: a moving pulse has no more than a still one's false tones.
    @Test func aPulseWhoseWidthMovesHasNoFalseTones() {
        let patch = PerfectoPatch.wave(PerfectoWavePulse, pulseWidth: 0.5).lfo(rate: 8, pulseWidth: 0.4)
        let rig = held(patch, note: 45, seconds: 1)
        // Nothing steps further than a pulse's own edge does.
        let still = held(.wave(PerfectoWavePulse, pulseWidth: 0.5), note: 45)
        #expect(rig.biggestStep(settled) < still.biggestStep(settled) * 1.2)
    }

    @Test func theLfoOpensAndClosesTheFilter() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: .steady(4)).lfo(rate: 0.5, cutoff: 2)
        let rig = held(patch, seconds: 2)
        let open = rig.strength(of: hz(57) * 8, in: around(0.5))             // cutoff at 16 times the note
        let closed = rig.strength(of: hz(57) * 8, in: around(1.5))           // and at the note itself
        #expect(open > 0.5 / 8 * 0.5)
        #expect(closed < open / 10)
    }

    /// Depths with no rate move nothing.
    @Test func anLfoWithNoRateIsNoLfo() {
        let plain = PerfectoPatch.wave(PerfectoWavePulse, pulseWidth: 0.3).filtered(cutoff: .steady(6))
        let rig = held(plain.lfo(rate: 0, pitch: 100, pulseWidth: 0.2, cutoff: 2))
        #expect(rig.output == held(plain).output)
    }

    // MARK: – Unison

    /// The copies are tuned evenly across the spread, and together are as
    /// loud as the one operator: each has the share its power adds up from.
    @Test func unisonSoundsCopiesTunedAcrossItsSpread() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSine).unison(3, spread: 100), note: 81)
        let each = 0.5 / 3.0.squareRoot()
        for note in [80, 81, 82] {
            #expect(abs(rig.strength(of: hz(note), in: settled) - each) < 0.01, "note \(note)")
        }
        #expect(abs(rig.power(settled) - held(.wave(PerfectoWaveSine), note: 81).power(settled)) < 0.01)
    }

    @Test(arguments: [0, 1])
    func aUnisonOfOneIsTheOperatorsAlone(copies: Int) {
        let plain = PerfectoPatch.wave(PerfectoWaveSawtooth)
        #expect(held(plain.unison(copies, spread: 30)).output == held(plain).output)
    }

    /// More copies than a voice has are as many as it has.
    @Test func unisonHasAsManyCopiesAsAVoiceHas() {
        let most = PerfectoUnisonCount
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth)
        #expect(held(patch.unison(most + 5, spread: 20)).output == held(patch.unison(most, spread: 20)).output)
    }

    /// Copies that started together would be one loud wave that then came
    /// apart. Each starts somewhere else in its cycle, so a note is as loud
    /// at its start as later.
    @Test func theCopiesDoNotStartAsOne() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth).unison(7, spread: 20)
        let rig = held(patch, note: 45)
        #expect(rig.loudest(frames(0.01)..<frames(0.06)) < rig.loudest(settled) * 1.3)
    }

    /// Both operators of a modulated sound are copied, each copy bent by
    /// its own modulator, so every copy is the same sound at its own pitch.
    @Test func eachCopyOfAModulatedSoundIsBentByItsOwnModulator() {
        let rig = held(PerfectoPatch.modulated(ratio: 3, index: .steady(1)).unison(2, spread: 100), note: 81)
        let each = 0.5 / 2.0.squareRoot()
        for cents in [-100.0, 100.0] {
            let pitch = hz(81) * pow(2, cents / 1200)
            #expect(abs(rig.strength(of: pitch, in: settled) - each * 0.765) < 0.01)
            #expect(abs(rig.strength(of: pitch * 4, in: settled) - each * 0.440) < 0.01)
        }
    }

    /// The copy tuned highest is the one whose partials must fit.
    @Test func aHighUnisonHasNoFalseTones() {
        let rig = held(PerfectoPatch.wave(PerfectoWaveSawtooth).unison(3, spread: 100), note: 107)
        let own = [106, 107, 108].flatMap { note in
            (1...40).map { hz(note) * Double($0) }.filter { $0 < KernelRig.sampleRate / 2 }
        }
        let stray = rig.remainder(without: own, in: settled)
        #expect(stray < rig.power(settled) * 0.01, "\(20 * log10(stray / rig.power(settled))) dB")
    }

    // MARK: – Drift

    /// The pitch of the note in `range`, from how often it crosses zero.
    private func pitch(_ rig: KernelRig, in range: Range<Int>) -> Double {
        let rising = zip(rig.output[range], rig.output[range].dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        return Double(rising) * KernelRig.sampleRate / Double(range.count)
    }

    /// A drifting note is a little off its pitch, never by more than the
    /// patch's drift, and no two notes are off alike.
    @Test func aDriftingNoteWandersWithinItsDrift() {
        let rig = KernelRig()
        rig.setSound(1, PerfectoPatch.wave(PerfectoWaveSine).drift(20))
        let length = frames(1)
        for note in 0..<6 {
            rig.noteOn(UInt64(note + 1), note: 81, sound: 1, at: note * 2 * length)
            rig.noteOff(UInt64(note + 1), at: note * 2 * length + length)
        }
        rig.render(12 * length)
        let pitches = (0..<6).map { pitch(rig, in: ($0 * 2 * length + 2400)..<($0 * 2 * length + length)) }
        let furthest = hz(81) * (pow(2, 20.0 / 1200) - 1) + 1.5             // and what counting crossings can miss
        #expect(pitches.allSatisfy { abs($0 - hz(81)) < furthest }, "\(pitches)")
        #expect(Set(pitches.map { ($0 * 2).rounded() }).count > 2, "\(pitches)")
    }

    /// Two operators wander each their own way, so the pair beats now
    /// faster and now slower; a modulator keeps to its carrier.
    @Test func operatorsWanderApartAndAModulatorDoesNot() {
        var pair = PerfectoPatch.wave(PerfectoWaveSine)
        pair.operators.1 = pair.operators.0
        let apart = held(pair.drift(20), note: 81, seconds: 2)
        // In tune they are one steady sine; wandering apart they beat.
        let levels = stride(from: 0.2, to: 1.9, by: 0.1).map { apart.loudest(frames($0)..<frames($0 + 0.1)) }
        #expect(levels.min()! < levels.max()! * 0.8, "\(levels)")

        let bent = held(PerfectoPatch.modulated(ratio: 1, index: .steady(1)).drift(20), note: 81, seconds: 2)
        let steady = stride(from: 0.2, to: 1.9, by: 0.1).map { bent.loudest(frames($0)..<frames($0 + 0.1)) }
        #expect(steady.min()! > steady.max()! * 0.97, "\(steady)")
    }

    /// What differs from note to note is the same each time the same
    /// events are played, so a rendering can be made again.
    @Test func driftIsTheSameEachTimeTheKernelIsReadied() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth).drift(15)
        let first = held(patch)
        #expect(first.output == held(patch).output)
        #expect(first.output != held(patch.drift(0)).output)
        first.prepareAgain()
        first.setSound(1, patch)
        first.noteOn(1, note: 57, sound: 1)
        first.render(frames(1))
        #expect(first.output == held(patch).output)
    }

    // MARK: – Noise

    /// A patch of nothing but noise, at half the level.
    private var hiss: PerfectoPatch {
        var patch = PerfectoPatch.wave(PerfectoWaveSine, level: 0.4)
        patch.operators.0.level = 0
        patch.noise = .steady(0.5)
        return patch
    }

    /// Noise is as loud as its share of the level says, has no pitch, and
    /// goes through the filter as the operators do.
    @Test func noiseIsHeardAtItsShareOfTheLevelAndIsFiltered() {
        let rig = held(hiss)
        // Evenly spread from -0.2 to 0.2: a third of that, squared, in
        // power, less the little the note's brightness takes off the top.
        #expect(rig.power(settled) > 0.09 && rig.power(settled) < 0.2 / 3.0.squareRoot())
        #expect(rig.strength(of: hz(57), in: settled) < 0.01)

        let dark = held(hiss.filtered(cutoff: .steady(1), steep: true))
        #expect(dark.power(settled) < rig.power(settled) / 4)
    }

    /// Swept down, noise is the breath at the start of a note and is gone.
    @Test func noiseSweepsOverTheNote() {
        var patch = PerfectoPatch.wave(PerfectoWaveSine)
        patch.noise = PerfectoSweep(from: 0.5, to: 0, time: 0.1)
        let rig = held(patch)
        #expect(rig.remainder(without: [hz(57)], in: frames(0.01)..<frames(0.05)) > 0.05)
        #expect(rig.remainder(without: [hz(57)], in: settled) < 0.001)
    }

    /// Two notes at once do not hiss alike, and the same events hiss the
    /// same each time.
    @Test func eachNotesNoiseIsItsOwnAndIsTheSameEachTime() {
        func chord() -> KernelRig {
            let rig = KernelRig()
            rig.setSound(1, hiss)
            rig.noteOn(1, note: 57, sound: 1)
            rig.noteOn(2, note: 57, sound: 1)
            rig.render(frames(1))
            return rig
        }
        // Alike, two would add to twice one; their own, to the root of two.
        #expect(abs(chord().power(settled) / held(hiss).power(settled) - 2.0.squareRoot()) < 0.1)
        #expect(chord().output == chord().output)
    }

    // MARK: – Glide

    /// Two notes of a gliding sine: the first for `first` seconds, the
    /// second from half a second in.
    private func glided(from: Int, to: Int, firstEnds: Double = 0.5, glide: Float = 0.05) -> KernelRig {
        let rig = KernelRig()
        var patch = PerfectoPatch.wave(PerfectoWaveSine)
        patch.glide = glide
        rig.setSound(1, patch)
        rig.noteOn(1, note: from, sound: 1)
        rig.noteOff(1, at: frames(firstEnds))
        rig.noteOn(2, note: to, sound: 1, at: frames(0.5))
        rig.render(frames(1.5))
        return rig
    }

    /// A note that follows another with no gap starts at that note's
    /// pitch and arrives at its own.
    @Test func aNoteGlidesFromTheOneItFollows() {
        let up = glided(from: 69, to: 81)
        let early = pitch(up, in: frames(0.51)..<frames(0.54))
        #expect(early > hz(69) * 1.1 && early < hz(81) * 0.9, "\(early)")
        #expect(abs(pitch(up, in: frames(1)..<frames(1.5)) - hz(81)) < 3)

        let down = glided(from: 81, to: 69)
        let falling = pitch(down, in: frames(0.51)..<frames(0.54))
        #expect(falling < hz(81) * 0.9 && falling > hz(69) * 1.1, "\(falling)")
        #expect(abs(pitch(down, in: frames(1)..<frames(1.5)) - hz(69)) < 3)
    }

    /// After a gap a note is at its own pitch from the start, and a sound
    /// with no glide never glides.
    @Test func aNoteAfterAGapOrWithNoGlideStartsAtItsPitch() {
        let apart = glided(from: 69, to: 81, firstEnds: 0.3)
        #expect(abs(pitch(apart, in: frames(0.51)..<frames(0.61)) - hz(81)) < 12)
        let plain = glided(from: 69, to: 81, glide: 0)
        #expect(abs(pitch(plain, in: frames(0.51)..<frames(0.61)) - hz(81)) < 12)
    }

    /// Of a chord that ended as the note started, it glides from the note
    /// nearest it, so each note of the next chord has the shortest way.
    @Test func aNoteGlidesFromTheNearestOfTheNotesItFollows() {
        let rig = KernelRig()
        var patch = PerfectoPatch.wave(PerfectoWaveSine)
        patch.glide = 0.05
        rig.setSound(1, patch)
        rig.noteOn(1, note: 57, sound: 1)
        rig.noteOn(2, note: 84, sound: 1)
        rig.noteOff(1, at: frames(0.5))
        rig.noteOff(2, at: frames(0.5))
        rig.noteOn(3, note: 81, sound: 1, at: frames(0.5))
        rig.render(frames(1))
        #expect(pitch(rig, in: frames(0.51)..<frames(0.54)) > hz(81))
    }

    /// A glide down through octaves keeps the high partials the lower
    /// pitch has room for.
    @Test func aNoteThatGlidedDownHasItsHighPartials() {
        let rig = KernelRig()
        var patch = PerfectoPatch.wave(PerfectoWaveSawtooth)
        patch.glide = 0.02
        rig.setSound(1, patch)
        rig.noteOn(1, note: 93, sound: 1)
        rig.noteOff(1, at: frames(0.2))
        rig.noteOn(2, note: 33, sound: 1, at: frames(0.2))
        rig.render(frames(1.5))
        let window = frames(1)..<frames(1.5)
        let partial = rig.strength(of: hz(33) * 200, in: window) / rig.strength(of: hz(33), in: window)
        #expect(abs(partial - 0.005) < 0.002)                                // partial 200, at 11 kHz
    }

    // MARK: – Drive

    /// A driven sine is flattened towards a square: it grows odd partials,
    /// and still peaks at about the patch's level.
    @Test func driveFlattensTheSoundAndKeepsItsLevel() {
        var patch = PerfectoPatch.wave(PerfectoWaveSine, level: 0.4)
        #expect(held(patch).strength(of: hz(57) * 3, in: settled) < 0.002)
        patch.drive = 1
        let driven = held(patch)
        #expect(driven.strength(of: hz(57) * 3, in: settled) > 0.1)
        #expect(driven.strength(of: hz(57) * 2, in: settled) < 0.005)
        #expect(abs(driven.loudest(settled) - 0.4) < 0.01)

        patch.drive = 0.3
        let warmed = held(patch)
        #expect(warmed.strength(of: hz(57) * 3, in: settled) > 0.005)
        #expect(warmed.strength(of: hz(57) * 3, in: settled) < driven.strength(of: hz(57) * 3, in: settled) * 0.7)
        #expect(abs(warmed.loudest(settled) - 0.4) < 0.01)
    }

    /// Drive comes after the filter, so what the filter took out is not
    /// what is driven, and before the envelope, so a note dying away is as
    /// driven as it was.
    @Test func driveIsAfterTheFilterAndBeforeTheEnvelope() {
        var patch = PerfectoPatch.wave(PerfectoWaveSine, level: 0.4)
            .envelope(attack: 0.003, decay: 0.05, sustain: 0.1, release: 0.006)
        patch.drive = 1
        let rig = held(patch)
        let third = rig.strength(of: hz(57) * 3, in: settled) / rig.strength(of: hz(57), in: settled)
        #expect(third > 0.25)                                                // near a square's third
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

    // MARK: – Bend and level

    /// A note played bent sounds that far from its pitch from its start,
    /// and a part of a semitone is a part of one.
    @Test func aNoteStartsAsFarFromItsPitchAsItIsBent() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57, bend: 2.5)
        rig.render(48_000)
        let bent = hz(57) * pow(2, 2.5 / 12)
        #expect(abs(rig.strength(of: bent, in: settled) - 0.2) < 0.002)
        #expect(rig.strength(of: hz(57), in: settled) < 0.002)
    }

    /// A change of bend is glided to: the note is on its way just after,
    /// and then at the pitch it was bent to, with no click on the way.
    @Test func aChangeOfBendIsGlidedTo() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57)
        rig.noteChange(1, bend: 12, at: 12_000)
        rig.render(48_000)
        #expect(abs(pitch(rig, in: 4800..<12_000) - hz(57)) < 8)
        let onTheWay = pitch(rig, in: 12_000..<12_480)
        #expect(onTheWay > hz(57) + 20 && onTheWay < hz(69) - 20)
        #expect(abs(rig.strength(of: hz(69), in: settled) - 0.2) < 0.002)
        // A sine an octave up is twice as steep, and nowhere steeper.
        #expect(rig.biggestStep(11_000..<48_000) < rig.biggestStep(settled) * 1.05)
    }

    /// A bent note's patch is as bright as it is at the pitch it is bent
    /// to: its filter follows the bend.
    @Test func aBentNotesFilterFollowsIt() {
        let patch = PerfectoPatch.wave(PerfectoWaveSawtooth).filtered(cutoff: PerfectoSweep(from: 4, to: 4, time: 0))
        let bent = KernelRig()
        bent.setSound(1, patch)
        bent.noteOn(1, note: 45, sound: 1)
        bent.noteChange(1, bend: 12, at: 2400)
        bent.render(48_000)
        let played = held(patch, note: 57)
        for partial in [1.0, 3, 6] {
            let expected = played.strength(of: hz(57) * partial, in: settled)
            #expect(abs(bent.strength(of: hz(57) * partial, in: settled) - expected) < expected * 0.03 + 0.0005)
        }
    }

    /// A note's level is how loud it is beside itself played whole, and a
    /// change of it is glided to.
    @Test func aNoteIsAsLoudAsItsLevel() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57, level: 0.5)
        rig.noteChange(1, level: 1, at: 24_000)
        rig.noteChange(1, level: 0, at: 36_000)
        rig.render(48_000)
        #expect(abs(rig.strength(of: hz(57), in: 12_000..<24_000) - 0.1) < 0.001)
        #expect(abs(rig.strength(of: hz(57), in: 30_000..<36_000) - 0.2) < 0.002)
        #expect(rig.loudest(24_000..<24_048) < 0.15)                         // on its way, not there
        #expect(rig.loudest(42_000..<48_000) < 0.0005)
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

    /// The most a voice can be asked for: every copy of both operators,
    /// wandering, under an LFO.
    @Test func everyVoiceAtItsFullestRendersFasterThanItIsHeard() {
        let rig = KernelRig()
        var patch = PerfectoPatch.wave(PerfectoWavePulse, pulseWidth: 0.4, level: 0.01)
            .filtered(cutoff: PerfectoSweep(from: 12, to: 2, time: 0.5), resonance: 0.4, steep: true)
            .unison(PerfectoUnisonCount, spread: 25)
            .drift(8)
            .lfo(rate: 5, pitch: 10, pulseWidth: 0.2, cutoff: 1)
        patch.operators.1 = patch.operators.0
        patch.operators.1.ratio = 0.5
        rig.setSound(1, patch)
        for id in 1...Int(perfecto_kernel_voice_count()) {
            rig.noteOn(UInt64(id), note: 36 + id % 48, sound: 1, brightness: 0.5,
                       pan: Float(id % 3) - 1, chorus: 0.5, reverb: 0.3)
        }
        let clock = ContinuousClock()
        let taken = clock.measure { rig.render(48_000) }
        // Fourteen times the waves of the test above. Built to be run it
        // takes about a fifth of a second on a Mac; a debug build, which
        // is what tests usually are, leaves the kernel as written, and
        // takes seven times as long.
        #if DEBUG
        let allowed = Duration.seconds(3)
        #else
        let allowed = Duration.seconds(1)
        #endif
        #expect(taken < allowed, "\(taken) to render a second")
        #expect(rig.output.allSatisfy { $0.isFinite })
    }
}
