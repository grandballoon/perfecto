import Foundation

enum MidiNoteKind: String, Codable {
    case noteOn, noteOff
}

enum SinkKind: String, Codable {
    case audio, midi, composite
}

enum ChordSource: String, Codable {
    case button, sequencer, arpeggio, looper
}

enum PrePromptChoice: String, Codable {
    case `continue`, notNow
}

enum LogEvent {
    // Audio session
    case audio_session_activated(category: String, mode: String, sampleRate: Double)
    case audio_session_failed(status: Int32)
    case audio_route_changed(to: String, reason: String)
    case audio_session_interrupted(reason: String)
    case audio_session_resumed(reason: String)
    case audio_engine_started
    case audio_engine_stopped
    case audio_engine_failed(message: String)

    // MIDI
    case midi_source_created(name: String, status: Int32)
    case midi_note_sent(note: Int, velocity: Int, channel: Int, kind: MidiNoteKind)
    case midi_send_failed(status: Int32, attemptedNote: Int?)

    // Sinks
    case sink_attached(kind: SinkKind)
    case sink_detached(kind: SinkKind)
    case sink_error(kind: SinkKind, message: String)

    // Performance
    case mode_changed(from: String, to: String)
    case mode_clock_required(mode: String, clockRunning: Bool)
    case chord_button_pressed(degree: Int, key: String, joystick: String, resultingNotes: [Int])
    case chord_played(notes: [Int], source: ChordSource)
    case chord_stopped(notes: [Int], source: ChordSource)

    // Permissions
    case permission_state_observed(permission: String, state: String)
    case permission_pre_prompt_shown(permission: String, feature: String)
    case permission_pre_prompt_response(permission: String, choice: PrePromptChoice)
    case permission_system_prompt_requested(permission: String)
    case permission_system_prompt_response(permission: String, granted: Bool)
    case permission_settings_redirect_shown(permission: String)
    case permission_settings_redirect_taken(permission: String)

    // Diagnostics
    case theory_unexpected_voicing(degree: Int, key: String, notes: [Int])
}

extension LogEvent: Encodable {
    // Dynamic string keys so every case encodes its fields flat alongside "type".
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .audio_session_activated(category, mode, sampleRate):
            try c.encode("audio_session_activated", forKey: Key("type"))
            try c.encode(category,    forKey: Key("category"))
            try c.encode(mode,        forKey: Key("mode"))
            try c.encode(sampleRate,  forKey: Key("sampleRate"))
        case let .audio_session_failed(status):
            try c.encode("audio_session_failed", forKey: Key("type"))
            try c.encode(status, forKey: Key("status"))
        case let .audio_route_changed(to, reason):
            try c.encode("audio_route_changed", forKey: Key("type"))
            try c.encode(to,     forKey: Key("to"))
            try c.encode(reason, forKey: Key("reason"))
        case let .audio_session_interrupted(reason):
            try c.encode("audio_session_interrupted", forKey: Key("type"))
            try c.encode(reason, forKey: Key("reason"))
        case let .audio_session_resumed(reason):
            try c.encode("audio_session_resumed", forKey: Key("type"))
            try c.encode(reason, forKey: Key("reason"))
        case .audio_engine_started:
            try c.encode("audio_engine_started", forKey: Key("type"))
        case .audio_engine_stopped:
            try c.encode("audio_engine_stopped", forKey: Key("type"))
        case let .audio_engine_failed(message):
            try c.encode("audio_engine_failed", forKey: Key("type"))
            try c.encode(message, forKey: Key("message"))
        case let .midi_source_created(name, status):
            try c.encode("midi_source_created", forKey: Key("type"))
            try c.encode(name,   forKey: Key("name"))
            try c.encode(status, forKey: Key("status"))
        case let .midi_note_sent(note, velocity, channel, kind):
            try c.encode("midi_note_sent", forKey: Key("type"))
            try c.encode(note,     forKey: Key("note"))
            try c.encode(velocity, forKey: Key("velocity"))
            try c.encode(channel,  forKey: Key("channel"))
            try c.encode(kind,     forKey: Key("kind"))
        case let .midi_send_failed(status, attemptedNote):
            try c.encode("midi_send_failed", forKey: Key("type"))
            try c.encode(status,        forKey: Key("status"))
            try c.encodeIfPresent(attemptedNote, forKey: Key("attemptedNote"))
        case let .sink_attached(kind):
            try c.encode("sink_attached", forKey: Key("type"))
            try c.encode(kind, forKey: Key("kind"))
        case let .sink_detached(kind):
            try c.encode("sink_detached", forKey: Key("type"))
            try c.encode(kind, forKey: Key("kind"))
        case let .sink_error(kind, message):
            try c.encode("sink_error", forKey: Key("type"))
            try c.encode(kind,    forKey: Key("kind"))
            try c.encode(message, forKey: Key("message"))
        case let .mode_changed(from, to):
            try c.encode("mode_changed", forKey: Key("type"))
            try c.encode(from, forKey: Key("from"))
            try c.encode(to,   forKey: Key("to"))
        case let .mode_clock_required(mode, clockRunning):
            try c.encode("mode_clock_required", forKey: Key("type"))
            try c.encode(mode,         forKey: Key("mode"))
            try c.encode(clockRunning, forKey: Key("clockRunning"))
        case let .chord_button_pressed(degree, key, joystick, resultingNotes):
            try c.encode("chord_button_pressed", forKey: Key("type"))
            try c.encode(degree,        forKey: Key("degree"))
            try c.encode(key,           forKey: Key("key"))
            try c.encode(joystick,      forKey: Key("joystick"))
            try c.encode(resultingNotes,forKey: Key("resultingNotes"))
        case let .chord_played(notes, source):
            try c.encode("chord_played", forKey: Key("type"))
            try c.encode(notes,  forKey: Key("notes"))
            try c.encode(source, forKey: Key("source"))
        case let .chord_stopped(notes, source):
            try c.encode("chord_stopped", forKey: Key("type"))
            try c.encode(notes,  forKey: Key("notes"))
            try c.encode(source, forKey: Key("source"))
        case let .permission_state_observed(permission, state):
            try c.encode("permission_state_observed", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
            try c.encode(state,      forKey: Key("state"))
        case let .permission_pre_prompt_shown(permission, feature):
            try c.encode("permission_pre_prompt_shown", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
            try c.encode(feature,    forKey: Key("feature"))
        case let .permission_pre_prompt_response(permission, choice):
            try c.encode("permission_pre_prompt_response", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
            try c.encode(choice,     forKey: Key("choice"))
        case let .permission_system_prompt_requested(permission):
            try c.encode("permission_system_prompt_requested", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
        case let .permission_system_prompt_response(permission, granted):
            try c.encode("permission_system_prompt_response", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
            try c.encode(granted,    forKey: Key("granted"))
        case let .permission_settings_redirect_shown(permission):
            try c.encode("permission_settings_redirect_shown", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
        case let .permission_settings_redirect_taken(permission):
            try c.encode("permission_settings_redirect_taken", forKey: Key("type"))
            try c.encode(permission, forKey: Key("permission"))
        case let .theory_unexpected_voicing(degree, key, notes):
            try c.encode("theory_unexpected_voicing", forKey: Key("type"))
            try c.encode(degree, forKey: Key("degree"))
            try c.encode(key,    forKey: Key("key"))
            try c.encode(notes,  forKey: Key("notes"))
        }
    }
}
