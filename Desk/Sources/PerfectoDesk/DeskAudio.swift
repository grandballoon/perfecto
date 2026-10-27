import AVFoundation
import DeskCore
import PerfectoSound
import os

/// The kernel's sound at the desk: the Audio Unit in an engine, every preset
/// loaded as one of its sounds, and the desk's lines of notes played on it.
///
///     silence ─→ mixer ─→ KernelAudioUnit ─→ output
///
/// The unit is a music effect, and an engine renders one only while
/// something is connected to its input, so a source of silence always is
/// (as the phone's `AudioGraph` does).
@MainActor
final class DeskAudio {
    private let engine = AVAudioEngine()
    private let node: AVAudioUnit
    private let unit: KernelAudioUnit
    private let input = AVAudioMixerNode()
    private let silence = AVAudioPlayerNode()
    /// Each preset's number among the kernel's sounds.
    private let numbers: [String: Int]
    /// The notes each line is sounding, by the kernel's id.
    private var sounding: [Line: [(id: UInt64, note: Int)]] = [:]
    /// Notes of a preview, ended after a moment.
    private var previewing: [UInt64] = []
    private var previewEnd: DispatchWorkItem?
    private var lastID: UInt64 = 0
    private var observer: (any NSObjectProtocol)?
    private let log = Logger(subsystem: "com.perfecto.desk", category: "audio")

    /// How hard every note is struck: the strike's level is the note's own
    /// (`Playing.level`), which a change glides.
    private static let velocity: Float = 0.7
    /// How far a chord's lowest and highest notes sit to either side.
    private static let spread: Float = 0.3
    /// Each line's share of the room: a little, so the desk sounds like a
    /// place without an effects page to set it.
    private static let reverb: [Line: Float] = [.chord: 0.16, .melody: 0.22]

    init() {
        let made = KernelAudioUnit.makeNode()
        node = made.node
        unit = made.unit
        let presets = SynthPreset.allCases.prefix(KernelAudioUnit.soundCount)
        numbers = Dictionary(uniqueKeysWithValues: presets.enumerated().map { ($1.rawValue, $0) })
        for (number, preset) in presets.enumerated() { unit.setSound(number, to: preset.patch) }
        unit.setChorusRate(0.8)
        unit.setReverbTail(2.6)
        unit.setReverbPredelay(0.02)
        unit.setReverbDamping(5200)
        unit.setDelayFeedback(0.35)
        unit.setDelayTime(0.47)
        engine.attach(node)
        engine.attach(input)
        engine.attach(silence)
        start()
        // The engine stops itself when the output changes (headphones in or
        // out, another device chosen); it is connected again at the new rate.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.silenceAll()
                self?.start()
            }
        }
    }

    private func start() {
        engine.stop()
        let format = engine.outputNode.outputFormat(forBus: 0)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate > 0 ? format.sampleRate : 48_000,
                                   channels: 2)
        engine.connect(silence, to: input, format: stereo)
        engine.connect(input, to: node, format: stereo)
        engine.connect(node, to: engine.mainMixerNode, format: stereo)
        do {
            try engine.start()
            log.info("engine started at \(stereo?.sampleRate ?? 0) Hz")
        } catch {
            log.error("engine failed to start: \(error.localizedDescription)")
        }
    }

    /// Sounds `notes` on `line` in place of what it sounds; tied, a note
    /// sounding already is held over.
    func sound(_ line: Line, notes: [Int], sound: String, level: Double, brightness: Double, tie: Bool) {
        let held = tie ? sounding[line, default: []].filter { notes.contains($0.note) } : []
        for note in sounding[line, default: []] where !held.contains(where: { $0.id == note.id }) {
            unit.noteOff(note.id)
        }
        var next = held
        for (i, note) in notes.enumerated() where !held.contains(where: { $0.note == note }) {
            let pan = notes.count > 1 ? Self.spread * (2 * Float(i) / Float(notes.count - 1) - 1) : 0
            lastID += 1
            unit.noteOn(lastID, note: note, velocity: Self.velocity, sound: numbers[sound] ?? 0, pan: pan,
                        playing: playing(line, level: level, brightness: brightness, bend: 0))
            next.append((lastID, note))
        }
        sounding[line] = next
    }

    /// Glides what `line` sounds.
    func shape(_ line: Line, level: Double, brightness: Double, bend: Double) {
        for note in sounding[line, default: []] {
            unit.noteChange(note.id, to: playing(line, level: level, brightness: brightness, bend: bend))
        }
    }

    func silence(_ line: Line) {
        for note in sounding[line, default: []] { unit.noteOff(note.id) }
        sounding[line] = []
    }

    func silenceAll() {
        Line.allCases.forEach(silence)
    }

    /// Plays `notes` in `sound` for a moment, to hear it while choosing it.
    func preview(sound: String, notes: [Int]) {
        endPreview()
        for note in notes {
            lastID += 1
            unit.noteOn(lastID, note: note, velocity: Self.velocity, sound: numbers[sound] ?? 0,
                        playing: playing(.chord, level: 0.8, brightness: 1, bend: 0))
            previewing.append(lastID)
        }
        let end = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.endPreview() } }
        previewEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: end)
    }

    private func endPreview() {
        previewEnd?.cancel()
        for id in previewing { unit.noteOff(id) }
        previewing = []
    }

    /// The delay's echoes are a dotted eighth apart, as the phone's are.
    func setTempo(_ bpm: Double) {
        unit.setDelayTime(Float(60 / bpm * 0.75))
    }

    private func playing(_ line: Line, level: Double, brightness: Double, bend: Double) -> KernelAudioUnit.Playing {
        KernelAudioUnit.Playing(brightness: Float(max(0, min(1, brightness))), reverb: Self.reverb[line] ?? 0,
                                bend: Float(bend), level: Float(max(0, min(1, level))))
    }
}
