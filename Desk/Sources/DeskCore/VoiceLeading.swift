import MusicTheoryCore

// Chords as voices moving, after Dmitri Tymoczko's "A Geometry of Music":
// a chord is a point with a coordinate for each voice, and the distance to
// another chord is how far its voices move. A triad is a point in three
// dimensions, and a semitone of one voice is a step along one axis. The
// consonant chords are the nearly even ones, which are exactly the ones a
// small motion of the voices joins, so a space laid out by nearness keeps
// consonance close at hand.
//
// Every move here is exact, so a direction always means the same motion:
// the top voice up, the middle down, the two in contrast. A move that lands
// on a chord that is not consonant is offered dimmed and cannot be taken.

/// A motion of the voices: which move and how far.
public struct VoiceMove: Hashable, Sendable {
    /// For the right stick, a direction clockwise from up (`VoiceLeading.moves`);
    /// for the bass, up or down.
    public let direction: Int
    /// Semitones each moving voice goes: 1 in the inner shell, 2 in the outer.
    public let shell: Int

    public init(direction: Int, shell: Int) {
        self.direction = direction
        self.shell = shell
    }
}

public enum VoiceLeading {
    /// The right stick's eight directions, clockwise from up, as how far the
    /// top voice and the middle voice move (in steps of the shell): up and
    /// down the top, right and left the middle, the diagonals both, the
    /// upper right and lower left together and the other two in contrast.
    public static let moves: [(top: Int, middle: Int)] = [
        (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
    ]

    public static let names = [
        "top ↑", "both ↑", "middle ↑", "closer", "top ↓", "both ↓", "middle ↓", "wider",
    ]

    public static let gate = PieGate.even(8)
    /// The bass on the left stick: up and down.
    public static let bassGate = PieGate(bearings: [0, 180], width: 60)
    public static let shells = 1...2

    /// The notes a chord can be moved among.
    public static let range = 24...108

    /// `notes` (ascending) with the two highest voices moved as `move` says;
    /// nil if a voice would cross another, meet it, or leave the range.
    public static func moved(_ notes: [Int], by move: VoiceMove) -> [Int]? {
        guard notes.count >= 3 else { return nil }
        var next = notes
        let (top, middle) = moves[move.direction]
        next[next.count - 1] += top * move.shell
        next[next.count - 2] += middle * move.shell
        return ordered(next)
    }

    /// `notes` with the lowest voice moved up (direction 0) or down.
    public static func bassMoved(_ notes: [Int], by move: VoiceMove) -> [Int]? {
        guard notes.count >= 2 else { return nil }
        var next = notes
        next[0] += (move.direction == 0 ? 1 : -1) * move.shell
        return ordered(next)
    }

    private static func ordered(_ notes: [Int]) -> [Int]? {
        guard zip(notes, notes.dropFirst()).allSatisfy({ $0 < $1 }), notes.allSatisfy(range.contains) else { return nil }
        return notes
    }

    /// The chord qualities that count as consonant, as tones above the root,
    /// in the order an ambiguous set is read: triads, then the 7ths and the
    /// added 9ths, then the evenly divided ones, then the 9ths. The 11ths
    /// and 13ths, which stack a tone over another, are not among them.
    public static let consonant: [[Int]] = [
        [0, 4, 7], [0, 3, 7], [0, 5, 7],
        [0, 4, 7, 10], [0, 4, 7, 11], [0, 3, 7, 10], [0, 3, 6, 10], [0, 5, 7, 10],
        [0, 2, 4, 7], [0, 2, 3, 7],
        [0, 3, 6], [0, 4, 8], [0, 3, 6, 9],
        [0, 2, 4, 7, 10], [0, 2, 4, 7, 11], [0, 2, 3, 7, 10], [0, 2, 4, 7, 9], [0, 2, 5, 7, 10],
    ]

    /// Whether `pitches` (pitch classes, three or more) make a consonant chord
    /// on one of them.
    public static func isConsonant(_ pitches: Set<Int>) -> Bool {
        guard pitches.count >= 3 else { return false }
        return pitches.contains { root in consonant.contains(pitches.map { ($0 - root + 12) % 12 }.sorted()) }
    }

    /// The chord `notes` sound, read in `key`, if it is consonant: the root
    /// is the bass if it can be, and otherwise the note that reads most
    /// plainly.
    public static func chord(of notes: [Int], in key: Key) -> DeskChord? {
        let pitches = Set(notes.map { (($0 % 12) + 12) % 12 })
        guard pitches.count >= 3 else { return nil }
        let bass = (((notes.first ?? 0) % 12) + 12) % 12
        var best: (rank: Int, root: Int)?
        for root in pitches {
            let above = pitches.map { ($0 - root + 12) % 12 }.sorted()
            guard let rank = consonant.firstIndex(of: above) else { continue }
            // The bass as the root wins a tie of plainness, and is worth a step of it.
            let score = rank * 2 + (root == bass ? 0 : 1)
            if best == nil || score < best!.rank { best = (score, root) }
        }
        guard let best else { return nil }
        let tones = ChordTones(pitches.map { ($0 - best.root + 12) % 12 })
        return DeskChord(root: PitchClass(rawValue: best.root)!, tones: tones, in: key, voicing: notes)
    }

    /// The chord a move of the upper voices makes from `notes`, if consonant.
    public static func neighbour(of notes: [Int], by move: VoiceMove, in key: Key) -> DeskChord? {
        moved(notes, by: move).flatMap { chord(of: $0, in: key) }
    }

    /// The chord a move of the bass makes from `notes`, if consonant.
    public static func bassNeighbour(of notes: [Int], by move: VoiceMove, in key: Key) -> DeskChord? {
        bassMoved(notes, by: move).flatMap { chord(of: $0, in: key) }
    }
}
