/// Standard MIDI File (SMF) encoder — turns timed note and meta events into
/// the bytes of a `.mid` file that any DAW (GarageBand, Logic, Ableton) imports
/// as an ordinary instrument track.
///
/// Pure Swift by design, like ChordWire: the byte layout is fully testable
/// without CoreMIDI or AudioToolbox. Only what Perfecto needs is modelled —
/// notes, tempo, time/key signature and text — and no program change is ever
/// written, so the importing DAW is free to assign any instrument.
///
/// Events carry absolute tick positions; encoding sorts them and converts to
/// the delta times the format requires.

public struct MidiFile: Equatable, Sendable {
    /// Timing resolution (PPQN): ticks per quarter note.
    public var ticksPerQuarter: Int
    public var tracks: [MidiTrack]

    public init(ticksPerQuarter: Int, tracks: [MidiTrack]) {
        self.ticksPerQuarter = ticksPerQuarter
        self.tracks = tracks
    }

    /// The complete file. A single track is written as format 0, several as
    /// format 1 (simultaneous tracks).
    public func encoded() -> [UInt8] {
        var bytes: [UInt8] = Array("MThd".utf8)
        bytes += bigEndian(6, byteCount: 4)
        bytes += bigEndian(tracks.count == 1 ? 0 : 1, byteCount: 2)
        bytes += bigEndian(tracks.count, byteCount: 2)
        bytes += bigEndian(ticksPerQuarter, byteCount: 2)
        for track in tracks {
            let body = track.encodedBody()
            bytes += Array("MTrk".utf8)
            bytes += bigEndian(body.count, byteCount: 4)
            bytes += body
        }
        return bytes
    }
}

public struct MidiTrack: Equatable, Sendable {
    public var events: [MidiEvent]
    /// Tick at which the track ends. The end-of-track marker is placed here
    /// (or at the last event, if later) so trailing silence survives import —
    /// a pattern ending in rests keeps its full bar length.
    public var length: Int

    public init(events: [MidiEvent], length: Int = 0) {
        self.events = events
        self.length = length
    }

    func encodedBody() -> [UInt8] {
        // Order within a tick: meta first (tempo/key apply before any note),
        // then note-offs, then note-ons — so a pitch released and re-struck on
        // the same tick is heard as a new note rather than cut short.
        let ordered = events.enumerated().sorted {
            ($0.element.tick, $0.element.kind.orderWithinTick, $0.offset)
                < ($1.element.tick, $1.element.kind.orderWithinTick, $1.offset)
        }.map(\.element)

        var bytes: [UInt8] = []
        var lastTick = 0
        for event in ordered {
            let tick = max(event.tick, 0)
            bytes += variableLengthQuantity(tick - lastTick)
            bytes += event.kind.encoded()
            lastTick = tick
        }
        let end = max(length, lastTick)
        bytes += variableLengthQuantity(end - lastTick)
        bytes += [0xFF, 0x2F, 0x00]   // end of track
        return bytes
    }
}

public struct MidiEvent: Equatable, Sendable {
    public var tick: Int
    public var kind: Kind

    public init(tick: Int, _ kind: Kind) {
        self.tick = tick
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        /// `channel` is 0-based (0 = MIDI channel 1).
        case noteOn(channel: Int, note: Int, velocity: Int)
        case noteOff(channel: Int, note: Int)
        case tempo(bpm: Double)
        case timeSignature(numerator: Int, denominator: Int)
        case keySignature(MidiKeySignature)
        case trackName(String)
        /// Timeline marker; DAWs such as Logic show these by name.
        case marker(String)

        var orderWithinTick: Int {
            switch self {
            case .noteOff: return 1
            case .noteOn:  return 2
            default:       return 0
            }
        }

        func encoded() -> [UInt8] {
            switch self {
            case let .noteOn(channel, note, velocity):
                return [0x90 | UInt8(clamping: channel & 0x0F),
                        UInt8(clamping: min(max(note, 0), 127)),
                        UInt8(clamping: min(max(velocity, 1), 127))]
            case let .noteOff(channel, note):
                return [0x80 | UInt8(clamping: channel & 0x0F),
                        UInt8(clamping: min(max(note, 0), 127)),
                        0]
            case let .tempo(bpm):
                let micros = min(max(Int((60_000_000 / bpm).rounded()), 1), 0xFF_FFFF)
                return meta(0x51, bigEndian(micros, byteCount: 3))
            case let .timeSignature(numerator, denominator):
                // Denominator is stored as a power of two; 24 MIDI clocks per
                // metronome click and 8 thirty-seconds per quarter are the
                // universal defaults.
                var power = 0
                while (1 << (power + 1)) <= denominator { power += 1 }
                return meta(0x58, [UInt8(clamping: numerator), UInt8(power), 24, 8])
            case let .keySignature(signature):
                return meta(0x59, [UInt8(bitPattern: Int8(signature.sharps)),
                                   signature.isMinor ? 1 : 0])
            case let .trackName(name):
                return meta(0x03, Array(name.utf8))
            case let .marker(text):
                return meta(0x06, Array(text.utf8))
            }
        }

        private func meta(_ type: UInt8, _ data: [UInt8]) -> [UInt8] {
            [0xFF, type] + variableLengthQuantity(data.count) + data
        }
    }
}

/// An SMF key signature: count of sharps (positive) or flats (negative) in
/// −7…7, plus the major/minor flag. The tonic is implied by the pair.
public struct MidiKeySignature: Equatable, Sendable {
    public let sharps: Int
    public let isMinor: Bool

    public init(sharps: Int, isMinor: Bool) {
        self.sharps = sharps
        self.isMinor = isMinor
    }
}

extension Key {
    /// The key signature a DAW should adopt for this key. SMF (like
    /// GarageBand) only knows major and minor keys, so every scale maps to the
    /// major or minor key on the same tonic, decided by its third: D Dorian →
    /// D minor, G Mixolydian → G major. Flat spellings are used for the black
    /// keys except F# (six sharps), matching common usage.
    public var midiKeySignature: MidiKeySignature {
        let isMinor = scale.intervals.contains(3)
        // A minor key shares its signature with the major key a minor third up.
        let relativeMajor = (root.rawValue + (isMinor ? 3 : 0)) % 12
        // Position on the circle of fifths: C=0, G=1, D=2 … F=11.
        let fifths = (relativeMajor * 7) % 12
        return MidiKeySignature(sharps: fifths > 6 ? fifths - 12 : fifths,
                                isMinor: isMinor)
    }
}

// MARK: – Encoding primitives

/// SMF variable-length quantity: 7 bits per byte, most significant first,
/// high bit set on every byte except the last.
func variableLengthQuantity(_ value: Int) -> [UInt8] {
    var remaining = max(value, 0)
    var bytes = [UInt8(remaining & 0x7F)]
    remaining >>= 7
    while remaining > 0 {
        bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
        remaining >>= 7
    }
    return bytes
}

private func bigEndian(_ value: Int, byteCount: Int) -> [UInt8] {
    (0..<byteCount).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}
