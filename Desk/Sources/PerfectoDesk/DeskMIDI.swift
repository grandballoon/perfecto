import CoreMIDI
import DeskCore
import Foundation
import os

/// The desk's notes as MIDI, from a virtual source called "Perfecto Desk"
/// that a DAW on this Mac lists among its inputs.
///
/// The chords are on channel 1 and the line on channel 2, so a DAW can give
/// each its own instrument. Unlike the phone, a note's velocity is how hard
/// it was struck, and what is played on a held note goes out as
/// controllers: its level as expression (CC 11), its brightness as CC 74,
/// and a slide as pitch bend over ±24 semitones (set by RPN 0 when the
/// source is made).
@MainActor
final class DeskMIDI {
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var isReady = false
    /// The notes each line is sounding.
    private var sounding: [Line: [Int]] = [:]
    /// The level each line's notes were struck at: what is played after is
    /// expression relative to it.
    private var struck: [Line: Double] = [:]
    /// What was last sent to each line's controllers, so nothing is sent twice.
    private var sent: [Line: (level: UInt8, brightness: UInt8, bend: UInt16)] = [:]
    private let log = Logger(subsystem: "com.perfecto.desk", category: "midi")

    static let bendRange: UInt8 = 24

    init(name: String = "Perfecto Desk") {
        guard MIDIClientCreateWithBlock(name as CFString, &client, nil) == noErr,
              MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source) == noErr else {
            log.error("could not make the MIDI source")
            return
        }
        isReady = true
        log.info("MIDI source \(name) made")
        for line in Line.allCases {
            let channel = Self.channel(line)
            // RPN 0, pitch bend range, then back to no RPN.
            send([0xB0 | channel, 101, 0], [0xB0 | channel, 100, 0], [0xB0 | channel, 6, Self.bendRange],
                 [0xB0 | channel, 38, 0], [0xB0 | channel, 101, 127], [0xB0 | channel, 100, 127])
        }
    }

    static func channel(_ line: Line) -> UInt8 {
        line == .chord ? 0 : 1
    }

    func sound(_ line: Line, notes: [Int], level: Double, brightness: Double, tie: Bool) {
        let channel = Self.channel(line)
        let held = tie ? sounding[line, default: []].filter(notes.contains) : []
        for note in sounding[line, default: []] where !held.contains(note) {
            send([0x80 | channel, UInt8(note), 0])
        }
        if !tie {
            struck[line] = max(0.01, level)
            shape(line, level: level, brightness: brightness, bend: 0)
        }
        let velocity = UInt8(max(1, min(127, (level * 127).rounded())))
        for note in notes where !held.contains(note) {
            send([0x90 | channel, UInt8(note), velocity])
        }
        sounding[line] = notes
    }

    func shape(_ line: Line, level: Double, brightness: Double, bend: Double) {
        let channel = Self.channel(line)
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(127, (value * 127).rounded()))) }
        let range = Double(Self.bendRange)
        let bendValue = UInt16(max(0, min(16383, 8192 + (bend / range * 8192).rounded())))
        let last = sent[line]
        let expression = byte(level / (struck[line] ?? 1))
        if last?.level != expression { send([0xB0 | channel, 11, expression]) }
        if last?.brightness != byte(brightness) { send([0xB0 | channel, 74, byte(brightness)]) }
        if last?.bend != bendValue {
            send([0xE0 | channel, UInt8(bendValue & 0x7F), UInt8(bendValue >> 7)])
        }
        sent[line] = (expression, byte(brightness), bendValue)
    }

    func silence(_ line: Line) {
        let channel = Self.channel(line)
        for note in sounding[line, default: []] { send([0x80 | channel, UInt8(note), 0]) }
        sounding[line] = []
    }

    func silenceAll() {
        Line.allCases.forEach(silence)
    }

    /// Sends each message at once, as MIDI 1.0 in universal packets.
    private func send(_ messages: [UInt8]...) {
        guard isReady else { return }
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._1_0)
        for message in messages where message.count == 3 {
            var word = UInt32(0x20) << 24 | UInt32(message[0]) << 16 | UInt32(message[1]) << 8 | UInt32(message[2])
            packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        }
        MIDIReceivedEventList(source, &list)
    }
}
