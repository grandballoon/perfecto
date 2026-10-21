import Foundation
import Testing
@testable import Perfecto

/// Recording double for PartialSink: what the kernel would have been asked.
@MainActor
final class RecordingPartialSink: PartialSink {

    enum Call: Equatable {
        case on(NoteID, note: Int, bend: Float, sound: PartialSound, velocity: Float, pan: Float)
        case partial(NoteID, number: Int, PartialSetting)
        case bend(NoteID, Float)
        case off(NoteID)
    }

    let partialCount = 16
    private(set) var calls: [Call] = []
    private(set) var times: [Double] = []

    /// Forgets the calls made so far; what is sounding is kept.
    func clear() { calls = [] }

    /// The notes sounding now, by id, with the MIDI note each started on.
    private(set) var sounding: [NoteID: Int] = [:]

    var partialChanges: [(number: Int, setting: PartialSetting)] {
        calls.compactMap { if case let .partial(_, number, setting) = $0 { (number, setting) } else { nil } }
    }

    func partialNoteOn(_ id: NoteID, note: Int, bend: Float, sound: PartialSound, velocity: Float,
                       pan: Float, at time: TimeInterval) {
        calls.append(.on(id, note: note, bend: bend, sound: sound, velocity: velocity, pan: pan))
        times.append(time)
        sounding[id] = note
    }

    func partialChange(_ id: NoteID, partial: Int, to setting: PartialSetting, at time: TimeInterval) {
        calls.append(.partial(id, number: partial, setting))
        times.append(time)
    }

    func partialBend(_ id: NoteID, to bend: Float, at time: TimeInterval) {
        calls.append(.bend(id, bend))
        times.append(time)
    }

    func partialNoteOff(_ id: NoteID, at time: TimeInterval) {
        calls.append(.off(id))
        times.append(time)
        sounding[id] = nil
    }
}

@Suite("DissonanceSynth")
@MainActor
struct DissonanceSynthTests {

    private let clock = ManualClock()
    private let sink = RecordingPartialSink()
    private let piano = RecordingNoteSink()

    private func synth() -> DissonanceSynth {
        DissonanceSynth(sink: sink, display: [piano], clock: clock)
    }

    private func note(_ pitch: Double, strengths: [Float] = [1, 0.5]) -> PartialNote {
        PartialNote(sound: .held, pitch: pitch, velocity: 0.8, partials: strengths.map { PartialSetting(strength: $0) })
    }

    @Test func aNewLineStartsWithEveryPartialSetAtItsStart() {
        let synth = synth()
        synth.sound([.keyed(57): note(57.25)])
        guard case let .on(id, n, bend, sound, velocity, pan)? = sink.calls.first else {
            Issue.record("no note started"); return
        }
        #expect(n == 57 && abs(bend - 0.25) < 1e-6 && sound == .held && velocity == 0.8 && pan == 0)
        // All sixteen, the ones it does not name silent, at the moment it starts.
        #expect(sink.partialChanges.count == 16)
        #expect(sink.partialChanges[1].setting.strength == 0.5 && sink.partialChanges[2].setting == .silent)
        #expect(sink.calls.dropFirst().allSatisfy { if case let .partial(of, _, _) = $0 { of == id } else { false } })
        #expect(Set(sink.times).count == 1)
        #expect(piano.started == [57])
    }

    /// A change of one partial sends that partial alone, and strikes nothing.
    @Test func aChangeSendsOnlyThePartialsThatDiffer() {
        let synth = synth()
        synth.sound([.keyed(57): note(57)])
        sink.clear()
        synth.sound([.keyed(57): note(57, strengths: [1, 0.25])])
        #expect(sink.calls.count == 1)
        #expect(sink.partialChanges.first?.number == 1 && sink.partialChanges.first?.setting.strength == 0.25)
    }

    /// A small move of pitch, as from equal temperament to just, is glided.
    @Test func aSmallMoveOfPitchIsBent() {
        let synth = synth()
        synth.sound([.keyed(64): note(64)])
        sink.clear()
        synth.sound([.keyed(64): note(63.98)])
        guard case let .bend(_, bend)? = sink.calls.first else { Issue.record("not bent"); return }
        #expect(abs(bend + 0.02) < 1e-5)
        #expect(sink.calls.count == 1)
    }

    /// A move of more than a semitone would be heard as a slide: the line
    /// is struck again, there.
    @Test func aLargeMoveOfPitchStrikesTheLineAgain() {
        let synth = synth()
        synth.sound([.keyed(64): note(64)])
        sink.clear()
        synth.sound([.keyed(64): note(76)])
        #expect(sink.calls.first.map { if case .off = $0 { true } else { false } } == true)
        #expect(sink.sounding.values.sorted() == [76])
        #expect(piano.sounding == [76])
    }

    @Test func aChangeOfPanOrSoundStrikesTheLineAgain() {
        let synth = synth()
        synth.sound([.keyed(57): note(57)])
        var panned = note(57)
        panned.pan = -1
        sink.clear()
        synth.sound([.keyed(57): panned])
        #expect(sink.calls.contains { if case .off = $0 { true } else { false } })
        #expect(sink.calls.contains { if case let .on(_, _, _, _, _, pan) = $0 { pan == -1 } else { false } })
    }

    @Test func aLineGoneEndsAndOnlyKeyedLinesAreShown() {
        let synth = synth()
        synth.sound([.keyed(57): note(57), .root: note(33, strengths: [0.35])])
        #expect(sink.sounding.count == 2)
        #expect(piano.sounding == [57])
        synth.sound([.root: note(33, strengths: [0.35])])
        #expect(sink.sounding.values.sorted() == [33])
        #expect(piano.sounding.isEmpty)
        synth.silence()
        #expect(sink.sounding.isEmpty)
    }

    /// A pitch under MIDI's lowest note, a beat of 5 Hz, is bent down to.
    @Test func aPitchUnderMidisRangeIsBentFromItsLowestNote() {
        let synth = synth()
        synth.sound([.difference: note(LabSounding.midi(ofHz: 5))])
        guard case let .on(_, n, bend, _, _, _)? = sink.calls.first else { Issue.record("no note"); return }
        #expect(n == 0)
        #expect(abs(LabSounding.hz(ofMidi: Double(n) + Double(bend)) - 5) < 1e-3)
    }
}
