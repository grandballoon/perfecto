/// ChordLink wire protocol v1 — the semantic chord announcement Perfecto
/// broadcasts alongside plain MIDI notes, encoded as a SysEx frame so it
/// travels over any MIDI transport (USB, RTP-MIDI network session) and is
/// ignored by receivers that only want notes (GarageBand).
///
/// Pure Swift by design: both directions (encode + decode) live here so the
/// frame layout is testable as a round-trip without CoreMIDI, and so a future
/// desktop receiver written in Swift gets the decoder for free. The wire
/// numbering is fixed by the explicit tables below, never by enum declaration
/// order — reordering a Swift enum must not silently change the protocol.
/// The full spec (shared with Harmonicland) is in chordlink.md.

/// Everything a receiver needs to reconstruct the musical intent of one
/// chord event: the selection context plus the exact voicing that sounded.
public struct ChordAnnouncement: Equatable, Sendable {
    public let key: Key
    public let degree: Degree
    public let joystickMode: JoystickMode
    public let joystickDirection: JoystickDirection
    public let inversion: Inversion
    public let octave: Int
    public let voiceLeading: Bool
    public let voicing: Voicing

    public init(key: Key,
                degree: Degree,
                joystickMode: JoystickMode,
                joystickDirection: JoystickDirection,
                inversion: Inversion,
                octave: Int,
                voiceLeading: Bool,
                voicing: Voicing) {
        self.key = key
        self.degree = degree
        self.joystickMode = joystickMode
        self.joystickDirection = joystickDirection
        self.inversion = inversion
        self.octave = octave
        self.voiceLeading = voiceLeading
        self.voicing = voicing
    }
}

public enum ChordWire {

    /// A decoded frame: either a chord with full context, or a release.
    public enum Frame: Equatable, Sendable {
        case chord(ChordAnnouncement)
        case release
    }

    // Frame header: F0 <non-commercial mfr> 'P' 'F' <version>.
    public static let sysExStart: UInt8 = 0xF0
    public static let sysExEnd:   UInt8 = 0xF7
    static let manufacturer: UInt8 = 0x7D   // MIDI "non-commercial / research" ID
    static let tagP: UInt8 = 0x50
    static let tagF: UInt8 = 0x46
    static let version: UInt8 = 0x01

    static let typeChord:   UInt8 = 0x01
    static let typeRelease: UInt8 = 0x02

    // Wire numbering tables. Order here IS the protocol; do not reorder.
    static let scaleOrder: [ScaleType] = [
        .major, .naturalMinor, .harmonicMinor, .melodicMinor,
        .majorPentatonic, .minorPentatonic, .blues,
        .dorian, .mixolydian, .lydian,
    ]
    static let modeOrder: [JoystickMode] = [.default, .extended, .chromatic]
    static let directionOrder: [JoystickDirection] = [
        .center, .up, .upRight, .right, .downRight,
        .down, .downLeft, .left, .upLeft,
    ]
    static let inversionOrder: [Inversion] = [.root, .first, .second]

    // MARK: – Encode

    public static func encodeChord(_ a: ChordAnnouncement) -> [UInt8] {
        var bytes: [UInt8] = [
            sysExStart, manufacturer, tagP, tagF, version, typeChord,
            UInt8(a.key.root.rawValue),
            UInt8(scaleOrder.firstIndex(of: a.key.scale) ?? 0),
            UInt8(a.degree.rawValue),
            UInt8(modeOrder.firstIndex(of: a.joystickMode) ?? 0),
            UInt8(directionOrder.firstIndex(of: a.joystickDirection) ?? 0),
            UInt8(inversionOrder.firstIndex(of: a.inversion) ?? 0),
            UInt8(clamping7Bit: a.octave),
            a.voiceLeading ? 1 : 0,
            a.voicing.bassNote == nil ? 0 : 1,
            UInt8(clamping7Bit: a.voicing.bassNote ?? 0),
            UInt8(clamping7Bit: a.voicing.notes.count),
        ]
        bytes += a.voicing.notes.map { UInt8(clamping7Bit: $0) }
        bytes.append(sysExEnd)
        return bytes
    }

    public static func encodeRelease() -> [UInt8] {
        [sysExStart, manufacturer, tagP, tagF, version, typeRelease, sysExEnd]
    }

    // MARK: – Decode

    /// Returns nil for anything that is not a well-formed ChordLink v1 frame:
    /// foreign SysEx, truncated payloads, and out-of-range fields are all
    /// rejected rather than partially interpreted.
    public static func decode(_ bytes: [UInt8]) -> Frame? {
        guard bytes.count >= 7,
              bytes[0] == sysExStart,
              bytes[1] == manufacturer,
              bytes[2] == tagP,
              bytes[3] == tagF,
              bytes[4] == version,
              bytes[bytes.count - 1] == sysExEnd
        else { return nil }

        let type = bytes[5]
        if type == typeRelease {
            return bytes.count == 7 ? .release : nil
        }
        guard type == typeChord, bytes.count >= 18 else { return nil }

        let root      = Int(bytes[6])
        let scaleIdx  = Int(bytes[7])
        let degreeRaw = Int(bytes[8])
        let modeIdx   = Int(bytes[9])
        let dirIdx    = Int(bytes[10])
        let invIdx    = Int(bytes[11])
        let octave    = Int(bytes[12])
        let vlFlag    = bytes[13]
        let bassFlag  = bytes[14]
        let bass      = Int(bytes[15])
        let count     = Int(bytes[16])

        guard let pitch = PitchClass(rawValue: root),
              scaleIdx < scaleOrder.count,
              let degree = Degree(rawValue: degreeRaw),
              modeIdx < modeOrder.count,
              dirIdx < directionOrder.count,
              invIdx < inversionOrder.count,
              vlFlag <= 1, bassFlag <= 1,
              bytes.count == 17 + count + 1
        else { return nil }

        let notes = (0..<count).map { Int(bytes[17 + $0]) }
        return .chord(ChordAnnouncement(
            key: Key(root: pitch, scale: scaleOrder[scaleIdx]),
            degree: degree,
            joystickMode: modeOrder[modeIdx],
            joystickDirection: directionOrder[dirIdx],
            inversion: inversionOrder[invIdx],
            octave: octave,
            voiceLeading: vlFlag == 1,
            voicing: Voicing(notes: notes, bassNote: bassFlag == 1 ? bass : nil)
        ))
    }
}

private extension UInt8 {
    /// SysEx data bytes must stay below 0x80; clamp rather than truncate so an
    /// out-of-range value can never masquerade as a status byte.
    init(clamping7Bit value: Int) {
        self = UInt8(Swift.min(Swift.max(value, 0), 127))
    }
}
