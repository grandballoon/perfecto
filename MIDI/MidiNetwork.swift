import CoreMIDI

/// Opts the app into Apple's RTP-MIDI network session so both virtual sources
/// ("Perfecto" notes, "Perfecto Link" SysEx) reach a Mac over Wi-Fi as well as
/// USB. The Mac side pairs once in Audio MIDI Setup → Network; after that the
/// sources appear to GarageBand and Web MIDI exactly as they do over USB.
@MainActor
enum MidiNetwork {
    static func enableSession(logger: (any Logger)? = nil) {
        let session = MIDINetworkSession.default()
        session.isEnabled = true
        session.connectionPolicy = .anyone
        logger?.log(.midi_network_session_enabled(name: session.networkName))
    }
}
