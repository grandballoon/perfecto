import CoreMIDI

// Seam for testing: separates MIDI byte construction from CoreMIDI transport.
@MainActor
protocol MidiBackend: AnyObject {
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8)
    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8)
}

// Production backend. Creates a virtual source (visible to Mac via USB) and an output
// port that sends directly to all destinations (e.g. "GarageBand Virtual In" on-device).
// GarageBand does not auto-subscribe to virtual sources; direct destination sends are required.
@MainActor
final class CoreMidiBackend: MidiBackend {

    private var client:     MIDIClientRef   = 0
    private var source:     MIDIEndpointRef = 0
    private var outputPort: MIDIPortRef     = 0
    private var isReady = false
    private let logger: (any Logger)?

    init(name: String = "Perfecto", logger: (any Logger)? = nil) {
        self.logger = logger
        let clientStatus = MIDIClientCreateWithBlock(name as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            logger?.log(.midi_source_created(name: name, status: clientStatus))
            return
        }
        let sourceStatus = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        MIDIOutputPortCreate(client, "PerfectoOut" as CFString, &outputPort)
        isReady = sourceStatus == noErr
        logger?.log(.midi_source_created(name: name, status: sourceStatus))
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        send(status: 0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) {
        send(status: 0x80 | (channel & 0x0F), data1: note, data2: velocity)
    }

    // MARK: – Private

    private func send(status: UInt8, data1: UInt8, data2: UInt8) {
        guard isReady else { return }
        // UMP MIDI 1.0 channel voice: bits 31-28 = type 0x2, 27-24 = group 0x0,
        // 23-16 = status, 15-8 = data1, 7-0 = data2
        var word = (UInt32(0x20) << 24) | (UInt32(status) << 16)
                 | (UInt32(data1) << 8) | UInt32(data2)
        var eventList = MIDIEventList()
        let packetPtr = MIDIEventListInit(&eventList, ._1_0)
        // MIDIEventListAdd is imported as returning a non-optional pointer, so its
        // result can't signal failure; adding one word to a fresh list always fits.
        _ = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packetPtr, 0, 1, &word)

        // Broadcast via virtual source (Mac via USB; apps that subscribe to "Perfecto")
        MIDIReceivedEventList(source, &eventList)

        // Send directly to all destinations (GarageBand Virtual In, etc.)
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            let result = MIDISendEventList(outputPort, dest, &eventList)
            if result != noErr {
                logger?.log(.midi_send_failed(status: result, attemptedNote: Int(data1)))
                print("[MIDI] MIDISendEventList dest[\(i)] error: \(result)")
            }
        }
    }
}

// Silent backend — used when CoreMIDI is unavailable or unwanted.
@MainActor
final class NoopMidiBackend: MidiBackend {
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {}
    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) {}
}

/// Broadcasts chord voicings as MIDI note-on/off messages via an on-device virtual source.
/// GarageBand on the same device sees "Perfecto" in its MIDI input list.
/// When the iPhone is connected to a Mac via USB, the source also appears there automatically.
///
/// Channel 1, velocity 100 fixed in v1. Per-note Note Off (no CC 123 / All Notes Off).
@MainActor
final class MidiSink: ChordEventSink {

    private let backend: any MidiBackend
    private let logger: (any Logger)?
    private var activeNotes: [UInt8] = []

    init(backend: (any MidiBackend)? = nil, logger: (any Logger)? = nil) {
        self.logger  = logger
        self.backend = backend ?? CoreMidiBackend(logger: logger)
    }

    func playChord(_ voicing: Voicing) {
        stopChord()
        activeNotes = voicing.notes.map { UInt8(clamping: $0) }
        for note in activeNotes {
            backend.sendNoteOn(note: note, velocity: 100, channel: 0)
            logger?.log(.midi_note_sent(note: Int(note), velocity: 100, channel: 0, kind: .noteOn))
        }
    }

    func stopChord() {
        for note in activeNotes {
            backend.sendNoteOff(note: note, velocity: 0, channel: 0)
            logger?.log(.midi_note_sent(note: Int(note), velocity: 0, channel: 0, kind: .noteOff))
        }
        activeNotes = []
    }

    // MARK: – Diagnostics

    nonisolated static func logTopology() {
        let srcCount  = MIDIGetNumberOfSources()
        let destCount = MIDIGetNumberOfDestinations()
        print("[MIDI] topology: \(srcCount) src, \(destCount) dest")
        for i in 0..<srcCount {
            let ep = MIDIGetSource(i)
            var cf: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cf)
            print("[MIDI]   src[\(i)] \(cf?.takeRetainedValue() as String? ?? "?")")
        }
        for i in 0..<destCount {
            let ep = MIDIGetDestination(i)
            var cf: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cf)
            print("[MIDI]   dest[\(i)] \(cf?.takeRetainedValue() as String? ?? "?")")
        }
    }
}
