import Foundation
import PerfectoKernel
import Testing

/// What an additive sound makes of a note: its partials as they are set when
/// it starts, and each partial set apart from the rest while it sounds.
@Suite("Kernel additive sounds")
struct AdditiveTests {

    /// A sawtooth's first `count` partials (1/n), at `level` each.
    private static func sawtooth(_ count: Int = 10, level: Float = 0.05) -> PerfectoPatch {
        .additive(partials: (1...count).map { 1 / Float($0) }, level: level)
    }

    /// How strong the sine at `hz` is in `range`, through a Hann window, whose
    /// sides fall away fast enough that a partial a few Hz away is not heard
    /// in it.
    private func strength(of hz: Double, in range: Range<Int>, of rig: KernelRig) -> Double {
        var (sine, cosine, weights) = (0.0, 0.0, 0.0)
        for (index, frame) in range.enumerated() {
            let weight = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(range.count - 1))
            let angle = 2 * Double.pi * hz * Double(frame) / KernelRig.sampleRate
            sine += weight * Double(rig.output[frame]) * sin(angle)
            cosine += weight * Double(rig.output[frame]) * cos(angle)
            weights += weight
        }
        return 2 * (sine * sine + cosine * cosine).squareRoot() / weights
    }

    /// A major third in equal temperament, A3 and C#4, held for a second:
    /// every partial of both notes is there, as strong as it was set.
    @Test func aMajorThirdHasEachPartialOfBothNotes() {
        let rig = KernelRig()
        rig.setSound(1, Self.sawtooth())
        rig.noteOn(1, note: 57, sound: 1)
        rig.noteOn(2, note: 61, sound: 1)
        rig.render(frames(1.5))
        let second = frames(0.25)..<frames(1.25)
        for note in [57, 61] {
            for n in 1...10 {
                let found = strength(of: hz(note) * Double(n), in: second, of: rig)
                let expected = 0.05 / Double(n)
                #expect(abs(found - expected) < expected * 0.03, "note \(note) partial \(n): \(found)")
            }
        }
        let own = [57, 61].flatMap { note in (1...10).map { hz(note) * Double($0) } }
        #expect(rig.remainder(without: own, in: second) < 0.002)
    }

    /// The partials of an additive sound are not scaled together: one
    /// partial set alone is as strong as the patch's level says.
    @Test func aPartialIsAsStrongAsItIsSet() {
        let rig = KernelRig()
        rig.setSound(1, .additive(partials: [0, 0, 0.5], level: 0.2))
        rig.noteOn(1, note: 57, sound: 1)
        rig.render(frames(0.5))
        let settled = frames(0.2)..<frames(0.5)
        #expect(abs(strength(of: hz(57) * 3, in: settled, of: rig) - 0.1) < 0.002)
        #expect(strength(of: hz(57), in: settled, of: rig) < 0.001)
    }

    /// A partial moved by some Hz is moved alone: the rest of the note stays
    /// where it was, so its pitch does.
    @Test func aPartialMovedIsMovedAlone() {
        let rig = KernelRig()
        rig.setSound(1, Self.sawtooth(4))
        rig.noteOn(1, note: 57, sound: 1)
        rig.partialChange(1, partial: 2, level: 1.0 / 3, offset: 5, at: frames(0.1))
        rig.render(frames(1))
        let settled = frames(0.3)..<frames(1)
        let third = hz(57) * 3
        #expect(abs(strength(of: third + 5, in: settled, of: rig) - 0.05 / 3) < 0.0005)
        #expect(strength(of: third, in: settled, of: rig) < 0.001)
        #expect(abs(strength(of: hz(57) * 2, in: settled, of: rig) - 0.025) < 0.0005)
    }

    /// A partial set on the frame its note starts is set from its first frame;
    /// set later, it glides there, and never with a click.
    @Test func aPartialIsSetAtOnceOnItsFirstFrameAndGlidedToAfter() {
        let rig = KernelRig()
        rig.setSound(1, .additive(partials: [1], level: 0.2).envelope(attack: 0.002, decay: 0.05,
                                                                      sustain: 1, release: 0.006))
        rig.noteOn(1, note: 57, sound: 1)
        rig.partialChange(1, partial: 0, level: 0)
        rig.partialChange(1, partial: 1, level: 1)
        rig.partialChange(1, partial: 1, level: 0, at: frames(0.3))
        rig.partialChange(1, partial: 0, level: 1, at: frames(0.3))
        rig.render(frames(0.6))
        #expect(strength(of: hz(57), in: frames(0.05)..<frames(0.3), of: rig) < 0.001)
        #expect(abs(strength(of: hz(57) * 2, in: frames(0.05)..<frames(0.3), of: rig) - 0.2) < 0.003)
        // Within its first few milliseconds it is on its way, not there.
        let early = rig.power(frames(0.3)..<frames(0.3) + 96)
        let later = rig.power(frames(0.45)..<frames(0.6))
        #expect(abs(early - later) > 0.001)
        #expect(abs(strength(of: hz(57), in: frames(0.45)..<frames(0.6), of: rig) - 0.2) < 0.003)
        // No step through the change is bigger than the sound's own before it.
        #expect(rig.biggestStep(frames(0.29)..<frames(0.4)) <= rig.biggestStep(frames(0.2)..<frames(0.29)) * 1.02)
    }

    /// A swing of full depth takes the partial down to silence and back, as
    /// many times a second as it is set to, starting at its loudest.
    @Test func aSwungPartialFallsToSilenceAndComesBack() {
        let rig = KernelRig()
        rig.setSound(1, .additive(partials: [1], level: 0.2))
        rig.noteOn(1, note: 69, sound: 1)
        rig.partialChange(1, partial: 0, level: 1, depth: 1, rate: 5)
        rig.render(frames(1))
        // Five swings a second: loudest every 0.2 s, silent between.
        let loud = rig.power(frames(0.39)..<frames(0.41))
        let quiet = rig.power(frames(0.49)..<frames(0.51))
        #expect(loud > 0.12)
        #expect(quiet < 0.01)
    }

    /// Partials over half the sample rate cannot be played: a high note has
    /// only those under it.
    @Test func aPartialOverHalfTheSampleRateIsSilent() {
        let rig = KernelRig()
        rig.setSound(1, Self.sawtooth(16))
        rig.noteOn(1, note: 105, sound: 1)
        rig.render(frames(0.5))
        let settled = frames(0.2)..<frames(0.5)
        let under = (1...16).map { hz(105) * Double($0) }.filter { $0 < KernelRig.sampleRate * 0.45 }
        #expect(under.count < 16)
        #expect(rig.remainder(without: under, in: settled) < 0.001)
    }

    /// A note that takes over another's voice keeps the partials it was given
    /// while it waited for the voice.
    @Test func aNoteWaitingForAVoiceKeepsItsPartials() {
        let rig = KernelRig()
        rig.setSound(1, .additive(partials: [1], level: 0.002))
        for id in 1...UInt64(perfecto_kernel_voice_count()) { rig.noteOn(id, note: 40, sound: 1) }
        rig.render(256)
        rig.setSound(2, .additive(partials: [1], level: 0.2))
        let id = UInt64(perfecto_kernel_voice_count()) + 1
        rig.noteOn(id, note: 69, sound: 2, at: 256)
        rig.partialChange(id, partial: 0, level: 0, at: 256)
        rig.partialChange(id, partial: 1, level: 1, at: 256)
        rig.render(frames(0.5))
        let settled = frames(0.2)..<frames(0.5)
        #expect(abs(strength(of: hz(69) * 2, in: settled, of: rig) - 0.2) < 0.005)
        #expect(strength(of: hz(69), in: settled, of: rig) < 0.002)
    }
}

extension PerfectoPatch {
    /// An additive sound whose partials start as `partials`, held at full
    /// level, with an organ's envelope.
    static func additive(partials: [Float], level: Float) -> PerfectoPatch {
        var patch = wave(PerfectoWavePartials, partials: partials, level: level)
        patch.additive = true
        return patch
    }
}

extension KernelRig {
    /// Sets one partial of a sounding note.
    @discardableResult
    func partialChange(_ id: UInt64, partial: Int, level: Float, offset: Float = 0,
                       depth: Float = 0, rate: Float = 0, at frame: Int = 0) -> Bool {
        var event = PerfectoEvent()
        event.time = UInt64(frame)
        event.note_id = id
        event.type = PerfectoEventPartialChange
        event.note = Int32(partial)
        event.level = level
        event.offset = offset
        event.depth = depth
        event.rate = rate
        return send(event)
    }
}
