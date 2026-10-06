import PerfectoKernel
import Testing

/// The kernel on its own, rendering offline. These tests are built so that
/// any memory allocated while rendering stops them on the spot.
@Suite("Kernel")
struct KernelTests {

    // MARK: – Time

    @Test func itIsSilentUntilANoteStarts() {
        let rig = KernelRig()
        rig.render(4800)
        #expect(rig.loudest(0..<4800) == 0)
        #expect(rig.time == 4800)
    }

    /// The note's first frame is the frame it names: it starts from zero
    /// there, so the first frame that is not silent is the one after.
    @Test(arguments: [1, 64, 256, 1024, 4096])
    func aNoteStartsOnTheFrameItNames(bufferSize: Int) {
        let rig = KernelRig()
        rig.noteOn(1, at: 1000)
        rig.render(4800, chunk: bufferSize)
        #expect(rig.loudest(0..<1001) == 0)
        #expect(rig.output[1001] != 0)
    }

    /// Notes and their ends fall inside render calls, at their edges and
    /// across them; none of it may depend on where the calls divide time.
    @Test func whatIsRenderedDoesNotDependOnHowTheFramesAreDivided() {
        func performance(chunks: [Int]) -> [Float] {
            let rig = KernelRig()
            rig.noteOn(1, note: 60, at: 100)
            rig.noteOn(2, note: 64, at: 256)
            rig.noteOn(3, note: 67, velocity: 0.5, at: 777)
            rig.noteOff(1, at: 2000)
            rig.noteOff(2, at: 2048)
            rig.noteOn(4, note: 72, at: 2049)
            rig.noteOff(3, at: 5000)
            rig.noteOff(4, at: 5001)
            rig.render(chunks: chunks)
            return rig.output
        }
        let total = 9600
        let whole = performance(chunks: [total])
        #expect(whole.contains { $0 != 0 })
        for size in [1, 64, 256, 1000] {
            let chunks = stride(from: 0, to: total, by: size).map { min(size, total - $0) }
            #expect(performance(chunks: chunks) == whole, "in calls of \(size)")
        }
        let uneven = [1, 7, 300, 92, 1, 1647, 512, 2440, 4600]
        #expect(uneven.reduce(0, +) == total)
        #expect(performance(chunks: uneven) == whole)
    }

    @Test func anEventWhoseFrameHasPassedTakesEffectOnTheNextFrame() {
        let rig = KernelRig()
        rig.render(500, chunk: 100)
        rig.noteOn(1, at: 0)
        rig.render(500, chunk: 100)
        #expect(rig.loudest(0..<501) == 0)
        #expect(rig.output[501] != 0)
    }

    /// A note's end can be sent before a later note's start is known, so
    /// events arrive in any order and are applied in time order.
    @Test func eventsSentOutOfOrderAreAppliedInTimeOrder() {
        let rig = KernelRig()
        rig.noteOff(1, at: 3000)
        rig.noteOn(1, at: 1000)
        rig.render(9600)
        #expect(rig.loudest(0..<1001) == 0)
        #expect(rig.loudest(2000..<3000) > 0.15)
        #expect(rig.loudest(3000 + frames(0.06)..<9600) == 0)
    }

    // MARK: – Notes

    @Test func aNoteDiesAwayAfterItEndsAndThenIsSilent() {
        let rig = KernelRig()
        rig.noteOn(1)
        rig.noteOff(1, at: 4800)
        rig.render(9600)
        #expect(rig.loudest(4000..<4800) > 0.19)
        #expect(rig.loudest(4800..<4800 + frames(0.01)) > 0.05)      // still ringing
        #expect(rig.loudest(4800 + frames(0.06)..<9600) == 0)
    }

    /// Neither the start nor the end of a note is a step in the sound.
    @Test func aNoteNeitherStartsNorEndsWithAClick() {
        let rig = KernelRig()
        rig.noteOn(1, at: 1000)
        rig.noteOff(1, at: 5020)                                       // near a peak of the wave
        rig.render(9600)
        let ownSlope = rig.biggestStep(3000..<5000)
        #expect(rig.biggestStep(0..<9600) <= ownSlope * 1.01)
    }

    @Test func aSofterNoteIsQuieter() {
        let rig = KernelRig()
        rig.noteOn(1, velocity: 0.5)
        rig.render(4800)
        #expect(abs(rig.loudest(2400..<4800) - 0.1) < 0.005)
    }

    /// Two layers can play the same pitch: they are two notes, and ending
    /// one leaves the other.
    @Test func twoNotesOfOnePitchAreTwoNotes() {
        let rig = KernelRig()
        rig.noteOn(1, note: 69)
        rig.noteOn(2, note: 69)
        rig.noteOff(1, at: 4800)
        rig.render(14_400)
        #expect(abs(rig.loudest(2400..<4800) - 0.4) < 0.01)
        #expect(abs(rig.loudest(9600..<14_400) - 0.2) < 0.01)
    }

    @Test func endingANoteThatIsNotSoundingDoesNothing() {
        let rig = KernelRig()
        rig.noteOn(1)
        rig.noteOff(99, at: 1000)
        rig.render(4800)
        #expect(rig.loudest(2400..<4800) > 0.19)
    }

    // MARK: – Voices

    @Test func everyVoiceCanSoundAtOnce() {
        let rig = KernelRig()
        let voices = Int(perfecto_kernel_voice_count())
        for id in 1...voices { rig.noteOn(UInt64(id), note: 69) }
        rig.render(4800)
        #expect(abs(rig.loudest(2400..<4800) - 0.2 * Float(voices)) < 0.2)
    }

    /// With every voice held, a new note takes the one held longest, and
    /// fades it out to do so. The oldest note here is the only one that can
    /// be heard, so a voice cut off, not faded, would show as a step, and
    /// the steal is tried at eight places round the wave.
    @Test(arguments: 0..<8)
    func aNoteTakingOverAVoiceDoesNotClick(offset: Int) {
        let rig = KernelRig()
        let voices = Int(perfecto_kernel_voice_count())
        rig.noteOn(1, note: 69, velocity: 1)
        for id in 2...voices { rig.noteOn(UInt64(id), note: 60, velocity: 0, at: 1) }
        let steal = 4800 + offset * 14
        rig.noteOn(1000, note: 60, velocity: 0, at: steal)
        rig.render(9600)

        let ownSlope = rig.biggestStep(2400..<4800)
        #expect(rig.loudest(2400..<4800) > 0.19)
        #expect(rig.biggestStep(0..<9600) <= ownSlope * 1.2)
        #expect(rig.loudest(steal + frames(0.01)..<9600) == 0)         // the oldest note is gone
    }

    /// A note ringing out is given up before a note still held.
    @Test func aNoteDyingAwayIsTakenBeforeANoteStillHeld() {
        let rig = KernelRig()
        let voices = Int(perfecto_kernel_voice_count())
        rig.noteOn(1, note: 69, velocity: 1)
        for id in 2...voices { rig.noteOn(UInt64(id), note: 60, velocity: 0, at: 1) }
        rig.noteOff(2, at: 2400)
        rig.noteOn(1000, note: 60, velocity: 0, at: 2401)
        rig.render(9600)
        #expect(rig.loudest(4800..<9600) > 0.19)                       // the oldest is still held
    }

    // MARK: – Limits

    /// Events wait in the kernel until their frames, and it holds only so
    /// many: past that it says no, and never loses one it accepted.
    @Test func sendingIsRefusedWhileTooManyEventsAreWaiting() {
        let rig = KernelRig()
        let capacity = Int(perfecto_kernel_event_capacity())
        #expect(rig.noteOn(1, velocity: 0.5, at: 1000))
        for id in 1..<capacity { #expect(rig.noteOff(UInt64(1000 + id), at: 1000)) }
        #expect(!rig.noteOn(2, at: 1000))

        rig.render(512)                      // taken in, but still waiting
        #expect(!rig.noteOn(2, at: 1000))

        rig.render(512)                      // their frame has come
        #expect(rig.noteOn(2, at: 2000))
        rig.render(4800)
        #expect(rig.loudest(0..<1001) == 0)
        #expect(abs(rig.loudest(1500..<2000) - 0.1) < 0.005)           // the first one sent was kept
        #expect(rig.loudest(4800..<5824) > 0.15)                         // and so was the last
    }
}
