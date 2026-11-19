import Foundation

/// A Standard MIDI File read into a `Score`, for a piece that is to be had
/// only as MIDI. MusicXML is the format to prefer (`MusicXML`): it says the
/// hand by the staff, where a MIDI file says it only by how its tracks are
/// divided, if they are.
///
/// Formats 0 and 1 are read: every track's note-ons and note-offs, paired
/// by track, channel and pitch, in seconds by the tempo changes (a
/// microsecond per quarter, which any track may set). Each note-bearing
/// stream of notes is a track, or a channel of a track that uses several,
/// and its hand is decided by `hands`.
enum MidiScore {

    enum Failure: Error, Equatable {
        case notMidi
        case corrupt
        case smpteTiming
        case noNotes
    }

    /// Whether `bytes` begin as a Standard MIDI File does.
    static func isMidi(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && Array(bytes.prefix(4)) == Array("MThd".utf8)
    }

    static func score(from bytes: [UInt8], title fallback: String = "Untitled") throws -> Score {
        guard isMidi(bytes) else { throw Failure.notMidi }
        var reader = Reader(bytes: bytes)
        reader.position = 4
        let headerLength = try reader.u32()
        _ = try reader.u16()                    // format
        let trackCount = try reader.u16()
        let division = try reader.u16()
        guard division & 0x8000 == 0 else { throw Failure.smpteTiming }
        reader.position = 8 + headerLength

        var events: [Event] = []
        var names: [Int: String] = [:]
        var title: String?
        for track in 0..<trackCount {
            guard try reader.bytes(4) == Array("MTrk".utf8) else { throw Failure.corrupt }
            let length = try reader.u32()
            let end = reader.position + length
            guard end <= bytes.count else { throw Failure.corrupt }
            var tick = 0
            var status: UInt8 = 0
            while reader.position < end {
                tick += try reader.variable()
                var byte = try reader.u8()
                if byte < 0x80 {
                    // Running status: the byte is the first of the data.
                    reader.position -= 1
                    byte = status
                } else if byte < 0xF0 {
                    status = byte
                }
                switch byte {
                case 0xFF:
                    let type = try reader.u8()
                    let data = try reader.bytes(try reader.variable())
                    if type == 0x51, data.count == 3 {
                        let perQuarter = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
                        events.append(Event(tick: tick, kind: .tempo(perQuarter)))
                    } else if type == 0x03 {
                        // A track's name; the first track's names the piece.
                        let name = String(decoding: data, as: UTF8.self)
                        if names[track] == nil { names[track] = name }
                        if track == 0, title == nil { title = name }
                    }
                case 0xF0, 0xF7:
                    _ = try reader.bytes(try reader.variable())
                case 0x80...0xEF:
                    let channel = Int(byte & 0x0F)
                    switch byte & 0xF0 {
                    case 0xC0, 0xD0:
                        _ = try reader.u8()
                    case 0x90, 0x80:
                        let pitch = Int(try reader.u8()), velocity = try reader.u8()
                        let on = byte & 0xF0 == 0x90 && velocity > 0
                        events.append(Event(tick: tick, kind: on ? .on(pitch) : .off(pitch),
                                            stream: Stream(track: track, channel: channel)))
                    default:
                        _ = try reader.bytes(2)
                    }
                default:
                    throw Failure.corrupt
                }
            }
            reader.position = end
        }

        // Seconds by the tempo map; at equal ticks a tempo comes first, and
        // a note-off before a note-on, so a note struck again is two notes.
        let ordered = events.enumerated().sorted { a, b in
            (a.element.tick, a.element.kind.order, a.offset) < (b.element.tick, b.element.kind.order, b.offset)
        }.map(\.element)
        var perQuarter = 500_000
        var lastTick = 0
        var seconds = 0.0
        var open: [Stream: [Int: [Double]]] = [:]
        var notes: [(stream: Stream, pitch: Int, onset: Double, end: Double)] = []
        for event in ordered {
            seconds += Double(event.tick - lastTick) * Double(perQuarter) / 1_000_000 / Double(division)
            lastTick = event.tick
            switch event.kind {
            case let .tempo(value):
                perQuarter = value
            case let .on(pitch):
                open[event.stream!, default: [:]][pitch, default: []].append(seconds)
            case let .off(pitch):
                guard var held = open[event.stream!]?[pitch], !held.isEmpty else { continue }
                let onset = held.removeFirst()
                open[event.stream!]?[pitch] = held
                notes.append((event.stream!, pitch, onset, seconds))
            }
        }
        guard !notes.isEmpty else { throw Failure.noNotes }

        let streams = Set(notes.map(\.stream)).sorted()
        let hand = hands(streams.map { NoteStream(stream: $0, name: names[$0.track] ?? "") })
        let scoreNotes = notes.map {
            ScoreNote(pitch: $0.pitch, onset: $0.onset, duration: max(0.02, $0.end - $0.onset),
                      hand: hand[$0.stream] ?? ($0.pitch < middleC ? .left : .right))
        }
        let named = title?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return Score(title: named?.isEmpty == false ? named! : fallback, notes: scoreNotes)
    }

    /// A stream of notes: a track, or one channel of a track that uses
    /// several.
    struct Stream: Hashable, Comparable {
        let track: Int
        let channel: Int

        static func < (a: Stream, b: Stream) -> Bool { (a.track, a.channel) < (b.track, b.channel) }
    }

    struct NoteStream {
        let stream: Stream
        /// The name of its track ("rh:", "Piano left").
        let name: String
    }

    static let middleC = 60

    /// Which hand plays each stream of notes:
    ///
    /// 1. A track named for a hand plays it: "rh", "right", "treble" or
    ///    "upper" the right; "lh", "left", "bass" or "lower" the left.
    /// 2. Of several streams otherwise, the first is the right hand and the
    ///    rest the left, as piano exports write them.
    /// 3. A single stream not named for a hand has no hand of its own
    ///    (none in what this gives back): its notes are split at middle C,
    ///    those below it the left hand's. That is a guess, the only one.
    static func hands(_ streams: [NoteStream]) -> [Stream: Hand] {
        var hands: [Stream: Hand] = [:]
        for stream in streams {
            if let named = hand(named: stream.name) { hands[stream.stream] = named }
        }
        if streams.count == 1 { return hands }
        let unnamed = streams.filter { hands[$0.stream] == nil }
        for (i, stream) in unnamed.enumerated() {
            hands[stream.stream] = i == 0 && !hands.values.contains(.right) ? .right : .left
        }
        return hands
    }

    private static func hand(named name: String) -> Hand? {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: ["rh", "right", "treble", "upper"].contains) { return .right }
        if words.contains(where: ["lh", "left", "bass", "lower"].contains) { return .left }
        return nil
    }

    private struct Event {
        enum Kind {
            case tempo(Int)
            case off(Int)
            case on(Int)

            var order: Int {
                switch self {
                case .tempo: return 0
                case .off:   return 1
                case .on:    return 2
                }
            }
        }

        let tick: Int
        let kind: Kind
        var stream: Stream?
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        mutating func u8() throws -> UInt8 {
            guard position < bytes.count else { throw Failure.corrupt }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func u16() throws -> Int {
            Int(try u8()) << 8 | Int(try u8())
        }

        mutating func u32() throws -> Int {
            try u16() << 16 | (try u16())
        }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, position + count <= bytes.count else { throw Failure.corrupt }
            defer { position += count }
            return Array(bytes[position..<(position + count)])
        }

        mutating func variable() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                let byte = try u8()
                value = value << 7 | Int(byte & 0x7F)
                if byte < 0x80 { return value }
            }
            throw Failure.corrupt
        }

    }
}
