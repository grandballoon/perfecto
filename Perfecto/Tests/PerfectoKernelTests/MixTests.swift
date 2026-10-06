import Foundation
import PerfectoKernel
import Testing

/// Where a note's sound goes after its voice: left and right, into the
/// chorus and the reverb, and through the limiter.
@Suite("Kernel mix")
struct MixTests {

    private let settled = 24_000..<48_000

    private func loudest(_ samples: ArraySlice<Float>) -> Float {
        samples.map(abs).max() ?? 0
    }

    // MARK: – Left and right

    @Test func aNoteInTheCentreIsTheSameOnBothSides() {
        let rig = KernelRig()
        rig.noteOn(1)
        rig.render(48_000)
        #expect(rig.output == rig.right)
        #expect(abs(rig.loudest(settled) - 0.2) < 0.005)
    }

    @Test func aNoteToOneSideFallsAwayOnTheOther() {
        let rig = KernelRig()
        rig.noteOn(1, pan: -1)
        rig.noteOn(2, note: 76, pan: 0.5, at: 24_000)
        rig.render(24_000)
        #expect(abs(rig.loudest(12_000..<24_000) - 0.2) < 0.005)
        #expect(loudest(rig.right[12_000..<24_000]) == 0)

        rig.render(24_000)
        // The second note is whole on the right and half on the left.
        #expect(abs(rig.strength(of: hz(76), in: 36_000..<48_000) - 0.1) < 0.005)
        let right = KernelRig()
        right.noteOn(2, note: 76, pan: 0.5)
        right.render(24_000)
        #expect(abs(loudest(right.right[12_000..<24_000]) - 0.2) < 0.005)
    }

    // MARK: – Limiter

    /// However many notes add up, no frame leaves over full scale, and
    /// what comes out is the mix turned down, not cut off: still the one
    /// pitch, with nothing added.
    @Test func theLimiterHoldsEveryVoiceUnderFullScale() {
        let rig = KernelRig()
        for id in 1...Int(perfecto_kernel_voice_count()) { rig.noteOn(UInt64(id), note: 57, at: 4800) }
        rig.render(48_000)
        #expect(rig.loudest(0..<48_000) <= 0.98)
        #expect(rig.loudest(settled) > 0.9)
        let stray = rig.remainder(without: [hz(57)], in: settled)
        #expect(stray < rig.power(settled) * 0.01)
    }

    /// A peak is turned down before it comes out, not after: the first
    /// frames of a sudden loud sound are under the ceiling too.
    @Test func aSuddenPeakIsCaughtFromItsFirstFrame() {
        let rig = KernelRig()
        var loud = PerfectoPatch.wave(PerfectoWaveSquare, level: 1).envelope(attack: 0.002, decay: 1, sustain: 1, release: 0.01)
        loud.operators.0.ratio = 1
        rig.setSound(1, loud)
        for id in 1...8 { rig.noteOn(UInt64(id), note: 45, sound: 1, at: 9600) }
        rig.render(24_000)
        #expect(rig.loudest(0..<24_000) <= 0.98)
        #expect(rig.loudest(9600..<10_000) > 0.9)
    }

    /// What is under the ceiling passes exactly as it is.
    @Test func theLimiterLeavesAQuietMixAlone() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57)
        rig.noteOn(2, note: 64)
        rig.render(48_000)
        #expect(abs(rig.strength(of: hz(57), in: settled) - 0.2) < 0.002)
        #expect(abs(rig.strength(of: hz(64), in: settled) - 0.2) < 0.002)
    }

    /// Once a loud moment has passed the mix comes back up to where it was.
    @Test func theLimiterLetsGoAfterAPeak() {
        let rig = KernelRig()
        rig.noteOn(1, note: 57)
        for id in 2...40 {
            rig.noteOn(UInt64(id), note: 57, at: 9600)
            rig.noteOff(UInt64(id), at: 14_400)
        }
        rig.render(96_000)
        #expect(rig.loudest(0..<96_000) <= 0.98)
        #expect(rig.loudest(20_000..<24_000) < 0.2)                          // still held down just after
        #expect(abs(rig.loudest(72_000..<96_000) - 0.2) < 0.002)             // and back a second on
    }

    @Test func everythingIsHeardTheSameShortTimeLate() {
        let rig = KernelRig()
        #expect(rig.latency == 72)                                           // 1.5 ms at 48 kHz
        rig.render(256)
        #expect(rig.time == 256 + rig.latency)
    }

    // MARK: – Reverb

    /// A short chord sent into the reverb, and the seconds after it. A
    /// chord, because one pitch rings only a few of the room's echoes and
    /// they beat against each other; several die away evenly.
    private func room(tail: Float, reverb: Float = 1, seconds: Double = 4) -> KernelRig {
        let rig = KernelRig()
        rig.setReverbTail(tail)
        for (id, note) in [45, 50, 54, 57, 61, 64].enumerated() {
            rig.noteOn(UInt64(id + 1), note: note, velocity: 0.5, reverb: reverb)
            rig.noteOff(UInt64(id + 1), at: 2400)
        }
        rig.render(frames(seconds))
        return rig
    }

    @Test func aNoteNotSentToTheReverbIsDry() {
        let rig = room(tail: 2, reverb: 0)
        #expect(rig.loudest(2400 + frames(0.1)..<rig.output.count) == 0)
    }

    /// The tail falls 60 dB in the time asked for: here, 30 dB in half of it.
    @Test(arguments: [1.5, 3] as [Float])
    func theReverbsTailLastsAsLongAsItIsSet(tail: Float) {
        let rig = room(tail: tail)
        let (from, window) = (frames(Double(tail) * 0.2), frames(Double(tail) * 0.2))
        let early = rig.power(from..<from + window)
        let late = rig.power(from + frames(Double(tail) * 0.5)..<from + frames(Double(tail) * 0.5) + window)
        #expect(early > 0.0005)
        let fallen = 20 * log10(early / late)
        #expect(abs(fallen - 30) < 4, "\(fallen) dB in half the tail")
    }

    @Test func aNoteSentWhollyToTheReverbIsNotHeardDry() {
        let dry = KernelRig()
        dry.noteOn(1, note: 57)
        dry.render(2400)
        let wet = room(tail: 2)
        // Before the room's first echo comes back, there is nothing.
        #expect(wet.loudest(0..<200) == 0)
        #expect(dry.loudest(0..<200) > 0.01)
    }

    /// The room answers after its pre-delay, and not before.
    @Test func theRoomAnswersAfterItsPredelay() {
        func firstSound(predelay: Float) -> Int {
            let rig = KernelRig()
            rig.setReverbPredelay(predelay)
            rig.noteOn(1, note: 69, reverb: 1)
            rig.render(24_000)
            return rig.output.firstIndex { $0 != 0 } ?? -1
        }
        let near = firstSound(predelay: 0)
        let far = firstSound(predelay: 0.1)
        #expect(near > 0)
        #expect(far - near == 4800)
    }

    /// A duller room loses the top of its tail sooner; the bottom rings as long.
    @Test func dampingTakesTheTopOffTheTail() {
        func tail(damping: Float, of pitch: Int) -> Double {
            let rig = KernelRig()
            rig.setReverbTail(3)
            rig.setReverbDamping(damping)
            for (id, note) in [pitch, pitch + 4, pitch + 7, pitch + 11].enumerated() {
                rig.noteOn(UInt64(id + 1), note: note, velocity: 0.5, reverb: 1)
                rig.noteOff(UInt64(id + 1), at: 2400)
            }
            rig.render(72_000)
            return rig.power(48_000..<72_000)
        }
        #expect(tail(damping: 1000, of: 96) < tail(damping: 12_000, of: 96) * 0.25)
        #expect(tail(damping: 1000, of: 45) > tail(damping: 12_000, of: 45) * 0.5)
    }

    @Test func theReverbIsDifferentOnEachSide() {
        let rig = room(tail: 2)
        let range = 9600..<48_000
        let both = zip(rig.output[range], rig.right[range])
        let alike = both.reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        let power = rig.power(range) * rig.power(range) * Double(range.count)
        #expect(abs(alike / power) < 0.5)
        #expect(loudest(rig.right[range]) > 0.001)
    }

    /// Turning a note's reverb down takes it out of what is sent, not out
    /// of the room: what was already ringing goes on dying away.
    @Test func turningTheSendDownDoesNotCutTheTail() {
        let rig = KernelRig()
        rig.setReverbTail(3)
        rig.noteOn(1, note: 57, reverb: 1)
        rig.noteChange(1, reverb: 0, at: 24_000)
        rig.noteOff(1, at: 26_400)
        rig.render(96_000)
        #expect(rig.power(48_000..<57_600) > 0.001)
    }

    /// The longest tail, fed for a long time, stays in bounds and dies away.
    @Test func theReverbIsStableAtItsLongest() {
        let rig = KernelRig()
        rig.setReverbTail(30)
        for id in 1...12 { rig.noteOn(UInt64(id), note: 40 + id * 3, reverb: 1) }
        for id in 1...12 { rig.noteOff(UInt64(id), at: 192_000) }
        rig.render(480_000)
        #expect(rig.output.allSatisfy { $0.isFinite })
        #expect(rig.loudest(0..<480_000) <= 0.98)
        #expect(rig.power(432_000..<480_000) < rig.power(144_000..<192_000))
    }

    // MARK: – Chorus

    @Test func aNoteWithNoChorusIsItselfAlone() {
        let plain = KernelRig()
        plain.noteOn(1, note: 57)
        plain.render(24_000)
        let rig = KernelRig()
        rig.setChorusRate(3)
        rig.noteOn(1, note: 57, chorus: 0)
        rig.render(24_000)
        #expect(rig.output == plain.output)
    }

    /// The chorus adds a copy whose pitch wavers, so against the note it
    /// beats: the level rises and falls where a plain note's is steady.
    @Test func chorusMakesTheLevelWaver() {
        func swing(chorus: Float) -> Float {
            let rig = KernelRig()
            rig.setChorusRate(2)
            rig.noteOn(1, note: 69, chorus: chorus)
            rig.render(96_000)
            // The loudest sample of each 20 ms, over the last second and a half.
            let peaks = stride(from: 24_000, to: 96_000, by: 960).map { rig.loudest($0..<$0 + 960) }
            return peaks.max()! - peaks.min()!
        }
        #expect(swing(chorus: 0) < 0.002)
        #expect(swing(chorus: 1) > 0.02)
    }

    @Test func chorusSpreadsANoteAcrossTheTwoSides() {
        let rig = KernelRig()
        rig.setChorusRate(2)
        rig.noteOn(1, note: 69, chorus: 1)
        rig.render(48_000)
        let apart = zip(rig.output[settled], rig.right[settled]).map { abs($0 - $1) }.max() ?? 0
        #expect(apart > 0.01)
    }

    /// A note's chorus and reverb are glided to, so playing them makes no
    /// step in the sound.
    @Test func changingTheSendsMakesNoStep() {
        let rig = KernelRig()
        rig.setChorusRate(1)
        rig.noteOn(1, note: 57)
        rig.noteChange(1, chorus: 1, reverb: 0.8, at: 12_000 + 55)           // near a peak of the wave
        rig.noteChange(1, chorus: 0, reverb: 0, at: 24_000 + 55)
        rig.render(48_000)
        // A sound of this pitch and loudness cannot move further in a
        // frame than its loudest sample times its pitch's angle a frame; a
        // send jumped to, at a peak of the wave, would be many times that.
        let steepest = rig.loudest(0..<48_000) * Float(2 * Double.pi * hz(57) / KernelRig.sampleRate) * 1.1
        #expect(rig.biggestStep(0..<48_000) <= steepest)
        #expect(rig.loudest(12_000..<24_000) != rig.loudest(6000..<12_000))  // the sends were heard
    }

    /// Nothing in the mix depends on how rendering is divided into calls.
    @Test func theMixDoesNotDependOnHowTheFramesAreDivided() {
        func performance(chunk: Int) -> ([Float], [Float]) {
            let rig = KernelRig()
            rig.setChorusRate(1.5)
            rig.setReverbTail(1.5)
            for id in 1...30 {
                rig.noteOn(UInt64(id), note: 40 + id, pan: Float(id % 5) / 2 - 1, chorus: Float(id % 3) / 2,
                           reverb: Float(id % 4) / 4, at: id * 97)
                rig.noteOff(UInt64(id), at: 6000 + id * 131)
            }
            rig.noteChange(7, brightness: 0.2, chorus: 1, reverb: 1, at: 3001)
            rig.render(19_200, chunk: chunk)
            return (rig.output, rig.right)
        }
        let whole = performance(chunk: 19_200)
        #expect(whole.0.contains { $0 != 0 })
        for chunk in [1, 64, 255, 256, 1000] {
            let pieces = performance(chunk: chunk)
            #expect(pieces.0 == whole.0 && pieces.1 == whole.1, "in calls of \(chunk)")
        }
    }
}
