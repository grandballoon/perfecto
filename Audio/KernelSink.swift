import Foundation

/// Sounds notes through the audio kernel. Each note goes to it with its own
/// sound: its preset (one of the kernel's sounds, loaded here once) and how
/// bright it is and how much chorus and reverb it has, so the keys and every
/// layer of the timeline can each be heard in their own.
///
/// The kernel has the voices and decides which to give up when there are
/// more notes than it has (`perfecto_kernel_voice_count`).
///
/// Two settings are not a note's but the whole mix's: how fast the chorus
/// wavers, and the size of the reverb's room. They follow the note played
/// or changed last.
@MainActor
final class KernelSink: NoteSink {

    private let unit: KernelAudioUnit
    /// Each preset's number among the kernel's sounds.
    private let numbers: [SynthPreset: Int]
    private var chorusRate: Float?
    private var reverbSize: Float?

    /// How hard every note is struck: the keys do not sense it.
    private static let velocity: Float = 1
    /// Chorus speeds from a slow drift to a fast shimmer, in Hz.
    static let chorusRates: ClosedRange<Float> = 0.2...5
    /// Reverb tails, in seconds to fall 60 dB.
    static let reverbTails: ClosedRange<Float> = 1...8

    /// Loads every preset into `unit`, which must not be rendering yet.
    init(unit: KernelAudioUnit) {
        self.unit = unit
        let presets = SynthPreset.allCases
        precondition(presets.count <= KernelAudioUnit.soundCount, "more presets than the kernel holds")
        numbers = Dictionary(uniqueKeysWithValues: presets.enumerated().map { ($1, $0) })
        for (number, preset) in presets.enumerated() { unit.setSound(number, to: preset.patch) }
    }

    func noteOn(_ id: NoteID, note: Int, sound: NoteSound) {
        setMix(for: sound)
        unit.noteOn(id.number, note: note, velocity: Self.velocity, sound: numbers[sound.preset] ?? 0,
                    playing: Self.playing(sound))
    }

    func noteChange(_ id: NoteID, sound: NoteSound) {
        setMix(for: sound)
        unit.noteChange(id.number, to: Self.playing(sound))
    }

    func noteOff(_ id: NoteID) {
        unit.noteOff(id.number)
    }

    /// An effect that is off takes none of the note; the filter, off, is
    /// fully open.
    static func playing(_ sound: NoteSound) -> KernelAudioUnit.Playing {
        KernelAudioUnit.Playing(
            brightness: sound.filter.isOn ? sound.filter.brightness.clamped(to: 0...1) : 1,
            chorus: sound.chorus.isOn ? sound.chorus.amount.clamped(to: 0...1) : 0,
            reverb: sound.reverb.isOn ? sound.reverb.mix.clamped(to: 0...1) : 0)
    }

    private func setMix(for sound: NoteSound) {
        if sound.chorus.rate != chorusRate {
            chorusRate = sound.chorus.rate
            unit.setChorusRate(Self.chorusRates.exponential(at: sound.chorus.rate))
        }
        if sound.reverb.size != reverbSize {
            reverbSize = sound.reverb.size
            unit.setReverbTail(Self.reverbTails.exponential(at: sound.reverb.size))
        }
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
