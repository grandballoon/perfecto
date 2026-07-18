import CoreMIDI

// Seam for testing: separates ChordLink frame construction from CoreMIDI
// transport, mirroring the MidiBackend seam in MidiSink.
@MainActor
protocol SysExTransport: AnyObject {
    /// Sends one complete SysEx frame (F0 ... F7 inclusive).
    func send(_ frame: [UInt8])
}

// Production transport. Owns its own virtual source, "Perfecto Link", kept
// separate from the "Perfecto" note source so receivers can tell the note
// plane and the semantic plane apart by name. Frames are re-chunked into
// UMP SysEx7 messages (type 0x3, 6 data bytes per message, F0/F7 stripped —
// CoreMIDI restores legacy framing for MIDI 1.0 consumers on the far side).
@MainActor
final class CoreMidiSysExTransport: SysExTransport {

    private var client:     MIDIClientRef   = 0
    private var source:     MIDIEndpointRef = 0
    private var outputPort: MIDIPortRef     = 0
    private var isReady = false
    private let logger: (any Logger)?

    init(name: String = "Perfecto Link", logger: (any Logger)? = nil) {
        self.logger = logger
        let clientStatus = MIDIClientCreateWithBlock(name as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            logger?.log(.midi_source_created(name: name, status: clientStatus))
            return
        }
        let sourceStatus = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        MIDIOutputPortCreate(client, "PerfectoLinkOut" as CFString, &outputPort)
        isReady = sourceStatus == noErr
        logger?.log(.midi_source_created(name: name, status: sourceStatus))
    }

    func send(_ frame: [UInt8]) {
        guard isReady, frame.count >= 2,
              frame.first == ChordWire.sysExStart, frame.last == ChordWire.sysExEnd
        else { return }

        // UMP SysEx7 carries data bytes only; framing is implicit in the
        // start/continue/end status nibble.
        let data = Array(frame.dropFirst().dropLast())
        let chunks = stride(from: 0, to: data.count, by: 6).map {
            Array(data[$0..<min($0 + 6, data.count)])
        }

        var eventList = MIDIEventList()
        var packet = MIDIEventListInit(&eventList, ._1_0)
        for (i, chunk) in chunks.enumerated() {
            // status: 0 = complete in one message, 1 = start, 2 = continue, 3 = end
            let status: UInt32 = chunks.count == 1 ? 0x0
                : i == 0 ? 0x1
                : i == chunks.count - 1 ? 0x3
                : 0x2
            let padded = chunk + Array(repeating: UInt8(0), count: 6 - chunk.count)
            let word0 = (UInt32(0x3) << 28) | (status << 20) | (UInt32(chunk.count) << 16)
                      | (UInt32(padded[0]) << 8) | UInt32(padded[1])
            let word1 = (UInt32(padded[2]) << 24) | (UInt32(padded[3]) << 16)
                      | (UInt32(padded[4]) << 8) | UInt32(padded[5])
            var words: [UInt32] = [word0, word1]
            packet = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size,
                                      packet, 0, words.count, &words)
        }

        // Broadcast via the virtual source (Mac over USB / network session)
        // and directly to on-device destinations, matching CoreMidiBackend.
        MIDIReceivedEventList(source, &eventList)
        for i in 0..<MIDIGetNumberOfDestinations() {
            let result = MIDISendEventList(outputPort, MIDIGetDestination(i), &eventList)
            if result != noErr {
                logger?.log(.midi_send_failed(status: result, attemptedNote: nil))
            }
        }
    }
}

// Silent transport — used when CoreMIDI is unavailable or unwanted.
@MainActor
final class NoopSysExTransport: SysExTransport {
    func send(_ frame: [UInt8]) {}
}

/// ChordLink announcer — one more ChordEventSink in the CompositeSink, beside
/// AudioSink and MidiSink. Where those consume only the Voicing, this one
/// pairs each event with the semantic selection (key, degree, joystick,
/// octave) pulled from a context provider at send time, and broadcasts the
/// result as a ChordWire SysEx frame for Harmonicland and other listeners.
///
/// The provider is settable after init because PerformanceState owns the
/// context but is itself constructed with the CompositeSink: build the
/// announcer, build the state, then point the provider at the state.
/// Events arriving before the provider is set (or when it returns nil, e.g.
/// no active degree yet) are silently skipped — the note plane still sounds.
@MainActor
final class MidiAnnouncerSink: ChordEventSink {

    struct Context {
        let key: Key
        let degree: Degree
        let joystickMode: JoystickMode
        let joystickDirection: JoystickDirection
        let inversion: Inversion
        let octave: Int
        let voiceLeading: Bool
    }

    var contextProvider: (() -> Context?)?

    private let transport: any SysExTransport
    private let logger: (any Logger)?

    init(transport: (any SysExTransport)? = nil, logger: (any Logger)? = nil) {
        self.logger = logger
        self.transport = transport ?? CoreMidiSysExTransport(logger: logger)
    }

    func playChord(_ voicing: Voicing) {
        guard let ctx = contextProvider?() else { return }
        let frame = ChordWire.encodeChord(ChordAnnouncement(
            key: ctx.key,
            degree: ctx.degree,
            joystickMode: ctx.joystickMode,
            joystickDirection: ctx.joystickDirection,
            inversion: ctx.inversion,
            octave: ctx.octave,
            voiceLeading: ctx.voiceLeading,
            voicing: voicing
        ))
        transport.send(frame)
        logger?.log(.chordlink_frame_sent(kind: .chord, byteCount: frame.count))
    }

    func stopChord() {
        let frame = ChordWire.encodeRelease()
        transport.send(frame)
        logger?.log(.chordlink_frame_sent(kind: .release, byteCount: frame.count))
    }
}
