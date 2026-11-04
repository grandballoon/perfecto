import Testing
@testable import ScorePractice

/// A Standard MIDI File of `tracks`, each its events' bytes (delta times
/// included), at 480 ticks to a quarter.
func midiFile(_ tracks: [[UInt8]]) -> [UInt8] {
    func u32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    let header = Array("MThd".utf8) + u32(6) + [0, 1, 0, UInt8(tracks.count), 0x01, 0xE0]
    return header + tracks.flatMap { events in
        let body = events + [0x00, 0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + u32(body.count) + body
    }
}

/// A track's name.
func named(_ name: String) -> [UInt8] {
    [0x00, 0xFF, 0x03, UInt8(name.utf8.count)] + Array(name.utf8)
}

/// A delta time of `ticks`, which must fit two bytes of a MIDI number.
func delta(_ ticks: Int) -> [UInt8] {
    ticks < 0x80 ? [UInt8(ticks)] : [UInt8(0x80 | ticks >> 7), UInt8(ticks & 0x7F)]
}

/// A quarter note of `pitch` on `channel`, after `rest` ticks.
func quarter(_ pitch: UInt8, channel: UInt8 = 0, after rest: Int = 0) -> [UInt8] {
    delta(rest) + [0x90 | channel, pitch, 100] + delta(480) + [0x80 | channel, pitch, 0]
}

/// 120 to the quarter.
let tempo120: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]

@Suite("MidiScore")
struct MidiScoreTests {

    @Test func tracksNamedForTheHandsAreThem() throws {
        let score = try MidiScore.score(from: midiFile([
            named("Prelude") + tempo120,
            named("lh:") + quarter(48) + quarter(52),
            named("rh:") + quarter(72) + quarter(76),
        ]))
        #expect(score.title == "Prelude")
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[72], [76]])
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48], [52]])
        // A quarter at 120 is half a second.
        #expect(score.steps(.right).map(\.onset) == [0, 0.5])
        #expect(score.notes.allSatisfy { $0.duration == 0.5 })
    }

    @Test func otherwiseTheFirstTrackWithNotesIsTheRightHand() throws {
        let score = try MidiScore.score(from: midiFile([
            tempo120,
            named("Piano") + quarter(72),
            named("Piano") + quarter(48),
        ]), title: "From the file's name")
        #expect(score.title == "From the file's name")
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[72]])
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48]])
    }

    @Test func channelsOfOneTrackAreStreamsOfTheirOwn() throws {
        let score = try MidiScore.score(from: midiFile([quarter(72, channel: 0) + quarter(48, channel: 1)]))
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[72]])
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48]])
    }

    @Test func oneStreamIsSplitAtMiddleC() throws {
        let chord: [UInt8] = [0x00, 0x90, 48, 100, 0x00, 0x90, 64, 100,
                              0x83, 0x60, 0x80, 48, 0, 0x00, 0x80, 64, 0]
        let score = try MidiScore.score(from: midiFile([chord]))
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48]])
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[64]])
    }

    @Test func aTempoChangeChangesTheSecondsFromItOn() throws {
        // A quarter at 120, then the tempo halves to 60.
        let slower: [UInt8] = [0x83, 0x60, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]
        let score = try MidiScore.score(from: midiFile([
            tempo120 + slower,
            named("rh") + quarter(72) + quarter(74),
        ]))
        #expect(score.notes.map(\.onset) == [0, 0.5])
        #expect(score.notes.map(\.duration) == [0.5, 1])
    }

    @Test func runningStatusAndNoteOnsOfNoVelocityAreRead() throws {
        // One note-on status for four events: two notes struck and ended.
        let events: [UInt8] = [0x00, 0x90, 60, 100, 0x83, 0x60, 60, 0, 0x00, 62, 100, 0x83, 0x60, 62, 0]
        let score = try MidiScore.score(from: midiFile([named("right") + events]))
        #expect(score.notes.map(\.pitch) == [60, 62])
        #expect(score.notes.map(\.onset) == [0, 0.5])
    }

    @Test func aNoteStruckAgainAsItEndsIsTwoNotes() throws {
        let score = try MidiScore.score(from: midiFile([named("rh") + quarter(72) + quarter(72)]))
        #expect(score.notes.map(\.onset) == [0, 0.5])
    }

    @Test func whatIsNotAMidiFileIsRefused() {
        #expect(throws: MidiScore.Failure.notMidi) { try MidiScore.score(from: Array("<score/>".utf8)) }
        #expect(throws: MidiScore.Failure.corrupt) { try MidiScore.score(from: Array(midiFile([quarter(60)]).dropLast(6))) }
        #expect(throws: MidiScore.Failure.noNotes) { try MidiScore.score(from: midiFile([tempo120])) }
    }
}
