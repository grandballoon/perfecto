import Foundation

/// Sounds notes through the audio kernel. Each note goes to it with its own
/// sound: its preset (one of the kernel's sounds, loaded here once) and how
/// much chorus, reverb and vocoder it has, so the keys and every layer of
/// the timeline can each be heard in their own.
///
/// The kernel has the voices and decides which to give up when there are
/// more notes than it has (`perfecto_kernel_voice_count`).
///
/// A note's time is turned into the frame the kernel is to act on
/// (`KernelAudioUnit.frame(atUptime:)`), so a note stamped ahead of time
/// sounds on exactly its frame. A time already past, or no way to tell
/// (nothing rendered yet), is as soon as possible.
///
/// Two settings are not a note's but the whole mix's: how fast the chorus
/// wavers, and the size of the reverb's room. There is one of each
/// (`ChorusSettings`, `ReverbSettings`), set here once.
@MainActor
final class KernelSink: NoteSink, PartialSink, TempoControl {

    private let unit: KernelAudioUnit
    /// Each preset's number among the kernel's sounds, and each sound made
    /// of partials' after them.
    private let numbers: [SynthPreset: Int]
    private let partialNumbers: [PartialSound: Int]

    /// How hard every note is struck: the keys do not sense it. It is set
    /// so that a chord of four notes in the loudest preset, alone, stays
    /// under what the limiter holds; the limiter is for layers piling up.
    private static let velocity: Float = 0.7
    /// Chorus speeds from a slow drift to a fast shimmer, in Hz.
    static let chorusRates: ClosedRange<Float> = 0.2...5
    /// Reverb tails, in seconds to fall 60 dB.
    static let reverbTails: ClosedRange<Float> = 1...8
    /// A bigger room is further away, so it answers later (seconds), and
    /// is softer, so the top of its tail dies sooner (Hz).
    static let reverbPredelays: ClosedRange<Float> = 0.005...0.04
    static let reverbDampings: ClosedRange<Float> = 3500...7000

    /// The frame the kernel renders at a moment of the device's uptime.
    private let frameAt: (TimeInterval) -> UInt64?

    /// Loads every preset into `unit`, which must not be rendering yet.
    /// `frameAt` is for tests, whose engine renders in no real time.
    init(unit: KernelAudioUnit, frameAt: ((TimeInterval) -> UInt64?)? = nil) {
        self.unit = unit
        self.frameAt = frameAt ?? { [unit] in unit.frame(atUptime: $0) }
        let presets = SynthPreset.allCases
        let partialSounds = PartialSound.allCases
        precondition(presets.count + partialSounds.count <= KernelAudioUnit.soundCount,
                     "more sounds than the kernel holds")
        numbers = Dictionary(uniqueKeysWithValues: presets.enumerated().map { ($1, $0) })
        for (number, preset) in presets.enumerated() { unit.setSound(number, to: preset.patch) }
        partialNumbers = Dictionary(uniqueKeysWithValues: partialSounds.enumerated()
            .map { ($1, presets.count + $0) })
        for (sound, number) in partialNumbers { unit.setSound(number, to: sound.patch) }
        unit.setChorusRate(Self.chorusRates.exponential(at: ChorusSettings.rate))
        unit.setReverbTail(Self.reverbTails.exponential(at: ReverbSettings.size))
        unit.setReverbPredelay(Self.reverbPredelays.exponential(at: ReverbSettings.size))
        unit.setReverbDamping(Self.reverbDampings.exponential(at: 1 - ReverbSettings.size))
        unit.setDelayFeedback(DelaySettings.feedback)
        setTempo(MusicalTime.defaultTempo)
    }

    /// The delay's echoes are a length of the beat apart.
    func setTempo(_ bpm: Double) {
        unit.setDelayTime(Float(DelaySettings.seconds(atBPM: bpm)))
    }

    func noteOn(_ id: NoteID, note: Int, sound: NoteSound, at time: TimeInterval) {
        unit.noteOn(id.number, note: note, velocity: Self.velocity, sound: numbers[sound.preset] ?? 0,
                    pan: sound.pan.clamped(to: -1...1), playing: Self.playing(sound), at: frameAt(time) ?? 0)
    }

    func noteChange(_ id: NoteID, sound: NoteSound, at time: TimeInterval) {
        unit.noteChange(id.number, to: Self.playing(sound), at: frameAt(time) ?? 0)
    }

    func noteOff(_ id: NoteID, at time: TimeInterval) {
        unit.noteOff(id.number, at: frameAt(time) ?? 0)
    }

    // MARK: – Notes made of partials

    var partialCount: Int { KernelAudioUnit.partialCount }

    func partialNoteOn(_ id: NoteID, note: Int, bend: Float, sound: PartialSound, velocity: Float,
                       pan: Float, at time: TimeInterval) {
        unit.noteOn(id.number, note: note, velocity: Self.velocity * velocity.clamped(to: 0...1),
                    sound: partialNumbers[sound] ?? 0, pan: pan.clamped(to: -1...1),
                    playing: KernelAudioUnit.Playing(bend: bend), at: frameAt(time) ?? 0)
    }

    func partialChange(_ id: NoteID, partial: Int, to setting: PartialSetting, at time: TimeInterval) {
        unit.partialChange(id.number, partial: partial, level: setting.strength, offset: setting.offset,
                           depth: setting.depth, rate: setting.rate, at: frameAt(time) ?? 0)
    }

    func partialBend(_ id: NoteID, to bend: Float, at time: TimeInterval) {
        unit.noteChange(id.number, to: KernelAudioUnit.Playing(bend: bend), at: frameAt(time) ?? 0)
    }

    func partialNoteOff(_ id: NoteID, at time: TimeInterval) {
        unit.noteOff(id.number, at: frameAt(time) ?? 0)
    }

    /// An effect that is off takes none of the note.
    static func playing(_ sound: NoteSound) -> KernelAudioUnit.Playing {
        KernelAudioUnit.Playing(
            brightness: sound.brightness.clamped(to: 0...1),
            chorus: sound.chorus.isOn ? ChorusSettings.amount : 0,
            reverb: sound.reverb.isOn ? ReverbSettings.mix : 0,
            vocoder: sound.vocoder.isOn ? sound.vocoder.amount.clamped(to: 0...1) : 0,
            delay: sound.delay.isOn ? DelaySettings.amount : 0,
            bend: sound.bend,
            level: sound.level.clamped(to: 0...1))
    }
}

extension ClosedRange where Bound == Float {
    /// The value `amount` (0...1) of the way through the range, placed so
    /// equal steps multiply it by equal amounts, the way speeds, lengths and
    /// pitches are heard.
    func exponential(at amount: Float) -> Float {
        lowerBound * pow(upperBound / lowerBound, amount.clamped(to: 0...1))
    }
}

extension PartialSound {
    /// Partials falling away as a sawtooth's to start with, quiet enough
    /// that two notes with one partial spotlighted 12 dB stay under the
    /// limiter; the Dissonance Lab sets them note by note.
    var patch: SynthPatch {
        let partials = (1...KernelAudioUnit.partialCount).map { 1 / Float($0) }
        switch self {
        case .held:
            return SynthPatch(partials: partials,
                              envelope: .init(attack: 0.03, decay: 0.1, sustain: 1, release: 0.15),
                              level: 0.06)
        case .struck:
            return SynthPatch(partials: partials,
                              envelope: .init(attack: 0.004, decay: 1.2, sustain: 0, release: 0.3),
                              level: 0.06)
        }
    }
}
