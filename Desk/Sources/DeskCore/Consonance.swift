import MusicTheoryCore

// The consonance guard: a switch that makes the chords and notes that are
// not consonant unplayable, in every layout. What is unplayable stays where
// it is, dimmed and out of reach, so a direction keeps its meaning; a button
// that would strike it does nothing, and the controller says no.
//
// "Consonant" is one rule (`VoiceLeading.consonant`: triads, 7ths, added
// 9ths, 9ths, and the evenly divided diminished and augmented), and the
// guard's mode says against what it is read.

/// Against what the guard reads a chord or a note.
public enum GuardMode: String, CaseIterable, Codable, Sendable {
    case off
    /// A chord of a consonant quality; a note of the key.
    case always
    /// As always, and with what is sounding now: a chord that shares a note
    /// with the chord sounding (the move is near), and is consonant with the
    /// line's note; a note consonant with the chord sounding.
    case sounding
    /// As always, and within the run: the notes of the last few chords
    /// played, so a chord can bring at most one note from outside them and
    /// the music drifts a step at a time.
    case run

    public var name: String {
        switch self {
        case .off: "Off"
        case .always: "Always"
        case .sounding: "With what's sounding"
        case .run: "With the run"
        }
    }
}

public struct ConsonanceGuard: Codable, Equatable, Sendable {
    public var mode = GuardMode.off
    /// Whether a chord or note from outside the key is unplayable too.
    public var inKey = false

    /// How many chords the run remembers.
    public static let window = 6

    /// The pitch classes of the last chords played, oldest first.
    public private(set) var recent: [Set<Int>] = []
    /// The chord sounding now, and the line's note, as pitch classes.
    public private(set) var chord: Set<Int>?
    public private(set) var note: Int?

    private enum CodingKeys: String, CodingKey { case mode, inKey }

    public init() {}

    public init(from decoder: any Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? saved.decodeIfPresent(GuardMode.self, forKey: .mode)) ?? .off
        inKey = (try? saved.decodeIfPresent(Bool.self, forKey: .inKey)) ?? false
    }

    /// The notes of the run: every pitch class of its chords.
    public var pool: Set<Int> { recent.reduce(into: Set()) { $0.formUnion($1) } }

    // MARK: – Hearing

    /// Hears what the layouts had sounded: chords struck, lines let go.
    public mutating func hear(_ effects: [DeskEffect]) {
        for effect in effects {
            switch effect {
            case let .sound(.chord, notes, _, _, _, _) where notes.count >= 2:
                let pitches = Set(notes.map { (($0 % 12) + 12) % 12 })
                chord = pitches
                if recent.last != pitches {
                    recent.append(pitches)
                    if recent.count > Self.window { recent.removeFirst() }
                }
            case .silence(.chord):
                chord = nil
            case let .sound(.melody, notes, _, _, _, _):
                note = notes.first.map { (($0 % 12) + 12) % 12 }
            case .silence(.melody):
                note = nil
            default:
                break
            }
        }
    }

    /// Forgets the run, as if nothing had been played.
    public mutating func forgetRun() {
        recent = []
    }

    // MARK: – Reading

    /// Why `chord` cannot be played in `key` now; nil if it can.
    public func refusal(of chord: DeskChord, in key: Key) -> String? {
        guard mode != .off else { return nil }
        let pitches = chord.pitchClasses
        guard VoiceLeading.isConsonant(pitches) else { return "\(chord.name) is not consonant" }
        if inKey, !pitches.allSatisfy({ key.has($0) }) { return "\(chord.name) is outside the key" }
        switch mode {
        case .off, .always:
            return nil
        case .sounding:
            if let sounding = self.chord, sounding != pitches, sounding.isDisjoint(with: pitches) {
                return "\(chord.name) shares no note with what is sounding"
            }
            if let note, !pitches.contains(note), !VoiceLeading.isConsonant(pitches.union([note])) {
                return "\(chord.name) clashes with the line's note"
            }
            return nil
        case .run:
            let pool = self.pool
            if !pool.isEmpty, pitches.subtracting(pool).count > 1 { return "\(chord.name) is outside the run" }
            return nil
        }
    }

    /// Why `note` cannot be played in `key` now, over the chord sounding;
    /// nil if it can.
    public func refusal(ofNote note: Int, in key: Key) -> String? {
        guard mode != .off else { return nil }
        let pitch = ((note % 12) + 12) % 12
        let name = PitchClass(rawValue: pitch)!.name
        guard key.has(note) || !inKey && mode != .always else { return "\(name) is outside the key" }
        switch mode {
        case .off, .always:
            return nil
        case .sounding:
            if let chord, !chord.contains(pitch), !VoiceLeading.isConsonant(chord.union([pitch])) {
                return "\(name) clashes with the chord"
            }
            return nil
        case .run:
            let pool = self.pool
            if !pool.isEmpty, !pool.contains(pitch) { return "\(name) is outside the run" }
            return nil
        }
    }

    public func allows(_ chord: DeskChord, in key: Key) -> Bool {
        refusal(of: chord, in: key) == nil
    }

    public func allows(note: Int, in key: Key) -> Bool {
        refusal(ofNote: note, in: key) == nil
    }
}

extension DeskSettings {
    /// Whether the guard lets `chord` be played now.
    public func playable(_ chord: DeskChord) -> Bool {
        consonance.allows(chord, in: key)
    }

    /// The guard's mode the next one along (`steps` < 0, the one before).
    public mutating func moveGuard(by steps: Int) {
        let all = GuardMode.allCases
        consonance.mode = all[((all.firstIndex(of: consonance.mode)! + steps) % all.count + all.count) % all.count]
    }
}
