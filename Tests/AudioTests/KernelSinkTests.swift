import AVFoundation
import Testing
@testable import Perfecto

/// Notes on their way to the kernel: each with its own preset and effects.
@Suite("KernelSink", .serialized)
@MainActor
struct KernelSinkTests {

    /// A kernel sink whose sound is rendered into memory.
    private func makeSubject() throws -> (sink: KernelSink, rig: KernelOfflineRig) {
        var sink: KernelSink?
        // The engine renders in no real time; a moment is its count of seconds rendered.
        let rig = try KernelOfflineRig { unit in
            sink = KernelSink(unit: unit) { UInt64(($0 * KernelOfflineRig.rate).rounded()) }
            // A mic sample to play, as there is once one has been recorded.
            unit.load(.tone(), into: SynthPreset.micCapture)
        }
        return (try #require(sink), rig)
    }

    /// How strong the sine at `hz` is in `samples`.
    private func strength(of hz: Double, in samples: ArraySlice<Float>) -> Double {
        var (sine, cosine) = (0.0, 0.0)
        for (index, sample) in samples.enumerated() {
            let angle = 2 * Double.pi * hz * Double(index) / KernelOfflineRig.rate
            sine += Double(sample) * sin(angle)
            cosine += Double(sample) * cos(angle)
        }
        return 2 * (sine * sine + cosine * cosine).squareRoot() / Double(samples.count)
    }

    private let a3 = 220.0

    @Test func aNoteIsHeardAndEnds() throws {
        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        let id = NoteID.next()
        sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ), at: 0)
        try rig.render(9600)
        sink.noteOff(id, at: 0)
        try rig.render(48_000)
        #expect(loudest(rig.output[4800..<9600]) > 0.05)
        #expect(loudest(rig.output[43_200...]) < 0.0001)
    }

    /// Two notes at once, each in its own preset: the sine pad has only its
    /// fundamental, the square lead its odd partials.
    @Test func eachNoteIsPlayedInItsOwnPreset() throws {
        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        sink.noteOn(.next(), note: 57, sound: NoteSound(preset: .sinePad), at: 0)
        sink.noteOn(.next(), note: 64, sound: NoteSound(preset: .squareLead), at: 0)
        try rig.render(48_000)
        let settled = rig.output[24_000..<48_000]
        let e4 = 440 * pow(2, -5.0 / 12)
        #expect(strength(of: a3, in: settled) > 0.1)
        #expect(strength(of: a3 * 3, in: settled) < 0.005)
        #expect(strength(of: e4 * 3, in: settled) > 0.02)
    }

    /// An effect that is off takes none of the note; the chorus and the
    /// reverb, on, take the one amount each has.
    @Test func effectsThatAreOffAreNotHeard() {
        let off = NoteSound(vocoder: VocoderSettings(isOn: false, amount: 0.9))
        #expect(KernelSink.playing(off) == KernelAudioUnit.Playing(chorus: 0, reverb: 0, vocoder: 0))
        let on = NoteSound(chorus: ChorusSettings(isOn: true), reverb: ReverbSettings(isOn: true),
                           vocoder: VocoderSettings(isOn: true, amount: 0.4))
        #expect(KernelSink.playing(on) == KernelAudioUnit.Playing(chorus: ChorusSettings.amount,
                                                                  reverb: ReverbSettings.mix, vocoder: 0.4))
    }

    /// A note is as far from its pitch and as loud as its sound says, from
    /// its start and when it is changed.
    @Test func aNoteIsBentAndAsLoudAsItsSoundSays() throws {
        #expect(KernelSink.playing(NoteSound()).bend == 0)
        #expect(KernelSink.playing(NoteSound()).level == 1)
        #expect(KernelSink.playing(NoteSound(bend: -2.5, level: 0.3)) == KernelAudioUnit.Playing(bend: -2.5, level: 0.3))

        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        let id = NoteID.next()
        sink.noteOn(id, note: 45, sound: NoteSound(preset: .organ, bend: 12), at: 0)
        try rig.render(24_000)
        let struck = rig.output[12_000..<24_000]
        #expect(strength(of: a3, in: struck) > 10 * strength(of: a3 / 2, in: struck))

        sink.noteChange(id, sound: NoteSound(preset: .organ, bend: 12, level: 0.25), at: 0)
        try rig.render(48_000)
        let quieter = strength(of: a3, in: rig.output[36_000..<48_000]) / strength(of: a3, in: struck)
        #expect(abs(quieter - 0.25) < 0.02)
    }

    /// A note played dark loses its high partials and keeps its low ones.
    @Test func aDarkNoteIsHeardDark() throws {
        func heard(brightness: Float) throws -> ArraySlice<Float> {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            sink.noteOn(.next(), note: 57, sound: NoteSound(preset: .sawLead, brightness: brightness), at: 0)
            try rig.render(48_000)
            return rig.output[24_000..<48_000]
        }
        let (open, dark) = (try heard(brightness: 1), try heard(brightness: 0))
        #expect(strength(of: a3 * 8, in: dark) < strength(of: a3 * 8, in: open) / 10)
        #expect(strength(of: a3, in: dark) > strength(of: a3, in: open) / 2)
        #expect(KernelSink.playing(NoteSound(brightness: 0.4)).brightness == 0.4)
    }

    /// A note with the delay on is echoed a dotted eighth later at the
    /// tempo, and one without is not.
    @Test func aNoteIsEchoedInTimeWithTheTempo() throws {
        func heard(delay: Bool, bpm: Double) throws -> [Float] {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            sink.setTempo(bpm)
            let id = NoteID.next()
            sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ, delay: DelaySettings(isOn: delay)), at: 0)
            try rig.render(2400)
            sink.noteOff(id, at: 0)
            try rig.render(48_000)
            return rig.output
        }
        // At 120 the echo is 0.375 s after the note; at 90, half a second.
        // Where it is not, there is only what is left of the note dying away.
        let fast = try heard(delay: true, bpm: 120)
        #expect(loudest(fast[18_500..<20_000]) > 0.01)
        let slow = try heard(delay: true, bpm: 90)
        #expect(loudest(slow[18_500..<20_000]) < 0.003)
        #expect(loudest(slow[24_500..<26_000]) > 0.01)
        #expect(loudest(try heard(delay: false, bpm: 120)[18_500...]) < 0.003)
        #expect(KernelSink.playing(NoteSound(delay: DelaySettings(isOn: true))).delay == DelaySettings.amount)
    }

    /// A note with reverb rings on after it ends, and one without does not.
    @Test func aNotesReverbRingsOnAfterIt() throws {
        func heard(reverb: ReverbSettings) throws -> [Float] {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            let id = NoteID.next()
            sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ, reverb: reverb), at: 0)
            try rig.render(4800)
            sink.noteOff(id, at: 0)
            try rig.render(96_000)
            return rig.output
        }
        #expect(loudest(try heard(reverb: ReverbSettings(isOn: false))[72_000...]) == 0)
        #expect(loudest(try heard(reverb: ReverbSettings(isOn: true))[48_000...]) > 0.001)
    }

    /// A change to a held note's sound reaches it: here its reverb, which
    /// the note rings on in once it has it.
    @Test func aHeldNotesEffectsCanBeChanged() throws {
        func heard(changing: Bool) throws -> [Float] {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            let id = NoteID.next()
            sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ), at: 0)
            try rig.render(4800)
            if changing {
                sink.noteChange(id, sound: NoteSound(preset: .organ, reverb: ReverbSettings(isOn: true)), at: 0)
            }
            try rig.render(24_000)
            sink.noteOff(id, at: 0)
            try rig.render(120_000)
            return rig.output
        }
        #expect(loudest(try heard(changing: false)[96_000...]) == 0)
        #expect(loudest(try heard(changing: true)[72_000...]) > 0.001)
    }

    /// A chord of four notes in any preset, on its own, stays under what
    /// the limiter holds: the limiter is for layers piling up, and typical
    /// playing leaves it idle.
    @Test(arguments: SynthPreset.allCases)
    func aChordAloneLeavesTheLimiterIdle(_ preset: SynthPreset) throws {
        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        for note in [48, 55, 64, 71] {
            sink.noteOn(.next(), note: note, sound: NoteSound(preset: preset), at: 0)
        }
        try rig.render(72_000)
        let peak = loudest(rig.output[...])
        #expect(peak < 0.9, "\(preset.name) peaks at \(peak)")
        #expect(peak > 0.1, "\(preset.name) peaks at \(peak)")
    }

    /// A note sent to the vocoder is heard only as the voice at the unit's
    /// input shapes it: where the voice is, and not where it is not.
    @Test func aNoteSentToTheVocoderIsShapedByWhatTheUnitHears() throws {
        func heard(vocoding: Bool) throws -> ArraySlice<Float> {
            var sink: KernelSink?
            let rig = try KernelOfflineRig(hearing: Tone(hz: 1000, rate: KernelOfflineRig.rate)) { unit in
                sink = KernelSink(unit: unit) { UInt64(($0 * KernelOfflineRig.rate).rounded()) }
                unit.setVocoder(vocoding)
            }
            defer { rig.engine.stop() }
            let sound = NoteSound(preset: .sawLead, vocoder: VocoderSettings(isOn: true))
            try #require(sink).noteOn(.next(), note: 45, sound: sound, at: 0)
            try rig.render(48_000)
            return rig.output[24_000..<48_000]
        }
        // 990 Hz is the note's ninth partial, under the voice; 2970 Hz is
        // its twenty-seventh, far from it.
        let whole = try heard(vocoding: false)
        let shaped = try heard(vocoding: true)
        let before = strength(of: 990, in: whole) / strength(of: 2970, in: whole)
        let after = strength(of: 990, in: shaped) / strength(of: 2970, in: shaped)
        #expect(strength(of: 990, in: shaped) > 0.01)
        #expect(after > before * 20)
    }
}
