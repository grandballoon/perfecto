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
        let rig = try KernelOfflineRig { sink = KernelSink(unit: $0) }
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
        sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ))
        try rig.render(9600)
        sink.noteOff(id)
        try rig.render(48_000)
        #expect(loudest(rig.output[4800..<9600]) > 0.05)
        #expect(loudest(rig.output[43_200...]) < 0.0001)
    }

    /// Two notes at once, each in its own preset: the sine pad has only its
    /// fundamental, the square lead its odd partials.
    @Test func eachNoteIsPlayedInItsOwnPreset() throws {
        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        sink.noteOn(.next(), note: 57, sound: NoteSound(preset: .sinePad))
        sink.noteOn(.next(), note: 64, sound: NoteSound(preset: .squareLead))
        try rig.render(48_000)
        let settled = rig.output[24_000..<48_000]
        let e4 = 440 * pow(2, -5.0 / 12)
        #expect(strength(of: a3, in: settled) > 0.1)
        #expect(strength(of: a3 * 3, in: settled) < 0.005)
        #expect(strength(of: e4 * 3, in: settled) > 0.02)
    }

    @Test func aDarkFilterTakesTheTopOffItsOwnNoteOnly() throws {
        func third(filter: FilterSettings) throws -> Double {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            sink.noteOn(.next(), note: 57, sound: NoteSound(preset: .sawLead, filter: filter))
            try rig.render(48_000)
            return strength(of: a3 * 8, in: rig.output[24_000..<48_000])
        }
        let open = try third(filter: FilterSettings(isOn: false, brightness: 0))      // off: fully open
        let dark = try third(filter: FilterSettings(isOn: true, brightness: 0))
        #expect(dark < open * 0.2)
    }

    /// An effect that is off takes none of the note, whatever it is set to.
    @Test func effectsThatAreOffAreNotHeard() {
        let off = NoteSound(filter: FilterSettings(isOn: false, brightness: 0.2),
                            chorus: ChorusSettings(isOn: false, amount: 0.9),
                            reverb: ReverbSettings(isOn: false, mix: 0.9))
        #expect(KernelSink.playing(off) == KernelAudioUnit.Playing(brightness: 1, chorus: 0, reverb: 0))
        let on = NoteSound(filter: FilterSettings(isOn: true, brightness: 0.2),
                           chorus: ChorusSettings(isOn: true, amount: 0.9),
                           reverb: ReverbSettings(isOn: true, mix: 0.4))
        #expect(KernelSink.playing(on) == KernelAudioUnit.Playing(brightness: 0.2, chorus: 0.9, reverb: 0.4))
    }

    /// A note with reverb rings on after it ends; its room is as long as
    /// the note's own setting says.
    @Test func aNotesReverbRingsOnAfterIt() throws {
        func tail(reverb: ReverbSettings) throws -> Float {
            let (sink, rig) = try makeSubject()
            defer { rig.engine.stop() }
            let id = NoteID.next()
            sink.noteOn(id, note: 57, sound: NoteSound(preset: .organ, reverb: reverb))
            try rig.render(4800)
            sink.noteOff(id)
            try rig.render(96_000)
            return loudest(rig.output[72_000...])
        }
        #expect(try tail(reverb: ReverbSettings(isOn: false)) == 0)
        let small = try tail(reverb: ReverbSettings(isOn: true, mix: 0.5, size: 0))
        let large = try tail(reverb: ReverbSettings(isOn: true, mix: 0.5, size: 1))
        #expect(large > 0.001)
        #expect(small < large * 0.2)
    }

    /// A change to a held note's sound reaches it: here its brightness.
    @Test func aHeldNotesEffectsCanBeChanged() throws {
        let (sink, rig) = try makeSubject()
        defer { rig.engine.stop() }
        let id = NoteID.next()
        sink.noteOn(id, note: 57, sound: NoteSound(preset: .sawLead, filter: FilterSettings(isOn: true, brightness: 0)))
        try rig.render(24_000)
        sink.noteChange(id, sound: NoteSound(preset: .sawLead, filter: FilterSettings(isOn: true, brightness: 1)))
        try rig.render(72_000)
        let before = strength(of: a3 * 8, in: rig.output[12_000..<24_000])
        let after = strength(of: a3 * 8, in: rig.output[48_000..<72_000])
        #expect(after > before * 5)
    }
}
