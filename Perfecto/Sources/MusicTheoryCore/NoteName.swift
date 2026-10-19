// Notes as they are written: a letter and an accidental, not a bare pitch
// class. B Locrian is B C D E F G A, and F♯ major has E♯ and not F, because
// a scale uses each letter once and a chord stacks every other letter.

/// A note's name: one of the seven letters, raised or lowered by up to two
/// semitones.
public struct NoteName: Hashable, Sendable {
    /// 0...6, C D E F G A B.
    public let letter: Int
    /// Semitones from the letter's natural note: -2 is 𝄫, 2 is 𝄪.
    public let accidental: Int

    public init(letter: Int, accidental: Int) {
        precondition((0..<7).contains(letter), "a letter is 0...6")
        self.letter = letter
        self.accidental = accidental
    }

    /// The pitch classes of the natural notes, C to B.
    static let naturals = [0, 2, 4, 5, 7, 9, 11]
    private static let letters = ["C", "D", "E", "F", "G", "A", "B"]

    public var pitchClass: PitchClass {
        PitchClass(rawValue: ((Self.naturals[letter] + accidental) % 12 + 12) % 12)!
    }

    /// "C", "F♯", "B♭", "D𝄪".
    public var name: String {
        let marks = [-2: "𝄫", -1: "♭", 0: "", 1: "♯", 2: "𝄪"]
        return Self.letters[letter] + (marks[accidental] ?? "")
    }

    /// The note `interval` semitones above this one, written `letters`
    /// letters further up: a scale's degree i is `letters` i, and a chord's
    /// tone i is 2i, so each is spelled as the letters fall.
    public func spelled(_ interval: Int, letters: Int) -> NoteName {
        let letter = (self.letter + letters) % 7
        let target = (pitchClass.rawValue + interval) % 12
        var accidental = ((target - Self.naturals[letter]) % 12 + 12) % 12
        if accidental > 6 { accidental -= 12 }
        return NoteName(letter: letter, accidental: accidental)
    }

    /// The twelve notes as a root is chosen from them: C, D♭, D, E♭, E, F,
    /// F♯, G, A♭, A, B♭, B.
    public static let roots: [NoteName] = [
        (0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (3, 1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0),
    ].map { NoteName(letter: $0.0, accidental: $0.1) }

    /// The note as a root it can be: a double sharp or flat is written as
    /// `roots` writes its pitch, and any other name is kept (F♭, E♯).
    public var asRoot: NoteName {
        abs(accidental) >= 2 ? Self.roots[pitchClass.rawValue] : self
    }
}
