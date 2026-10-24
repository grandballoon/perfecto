// A chord given by its tones: the pitch classes above its root, whatever
// stack or table they came from. The step compass makes its colors this way
// (a tone added to a chord, taken away or moved a semitone), so a color is
// what sounds, named the way a lead sheet names it.

/// The pitch classes of a chord above its root, 0 (the root) always among
/// them: C E G B♭ on C is [0, 4, 7, 10].
public struct ChordTones: Hashable, Codable, Sendable {
    /// Ascending, unique, each 0...11, the first 0.
    public let pitchClasses: [Int]

    public init(_ pitchClasses: some Sequence<Int>) {
        self.pitchClasses = Array(Set(pitchClasses.map { ($0 % 12 + 12) % 12 } + [0])).sorted()
    }

    public func has(_ pitchClass: Int) -> Bool { pitchClasses.contains(pitchClass) }

    /// The intervals the chord is voiced in: each tone in the octave above
    /// the root, but a tension over the chord (a 9th, 11th or 13th) an
    /// octave higher, where a lead sheet puts it, so it stays on top of an
    /// inversion (`Inversion`).
    public var intervals: [Int] {
        let third = has(3) || has(4), seventh = has(10) || has(11)
        return pitchClasses.map { p in
            let isTension = ((p == 1 || p == 2) && third) || (p == 3 && has(4)) || (p == 5 && third)
                || (p == 6 && has(7)) || (p == 8 && has(7) && seventh) || (p == 9 && seventh)
            return isTension ? p + 12 : p
        }.sorted()
    }

    /// The chord's quality, as the rest of the app names chords ("maj",
    /// "min7", "7♭9", "min add9", "sus4"): the 3rd (or a suspension), the
    /// 5th, the 7th or a 6th, then the tensions, and a tone a chord of its
    /// kind would have but this one has not as "no5".
    public var name: String {
        var used: Set<Int> = [0]
        let third: Int? = has(4) ? 4 : has(3) ? 3 : nil
        if let third { used.insert(third) }
        var sus: String?
        if third == nil {
            if has(5) { sus = "sus4"; used.insert(5) } else if has(2) { sus = "sus2"; used.insert(2) }
        }
        let fifth: Int?
        if has(7) { fifth = 7 }
        else if has(6), third != 4 { fifth = 6 }
        else if has(8), third == 4 { fifth = 8 }
        else if has(6), third == 4, !has(10), !has(11) { fifth = 6 }
        else { fifth = nil }
        if let fifth { used.insert(fifth) }
        let dim = third == 3 && fifth == 6
        let seventh: Int? = has(11) ? 11 : has(10) ? 10 : (dim && has(9)) ? 9 : nil
        if let seventh { used.insert(seventh) }
        // A chord with both 7ths has the major one as its 7th.
        let bothSevenths = has(10) && has(11)
        if bothSevenths { used.insert(10) }
        let six = seventh == nil && has(9)
        if six { used.insert(9) }
        var tensions = [1, 2, 3, 5, 6, 8, 9].filter { has($0) && !used.contains($0) }

        var name: String
        if dim {
            switch seventh {
            case 10: name = "min7♭5"
            case 9:  name = "dim7"
            case 11: name = "dim(maj7)"
            default: name = "dim"
            }
        } else if third == 4, fifth == 8, seventh == nil {
            name = "aug"
        } else {
            let minor = third == 3 ? "min" : ""
            switch seventh {
            case 11: name = third == 3 ? "min(maj7)" : "maj7"
            case 10: name = minor + "7"
            default: name = six ? minor + "6" : (third == 3 ? "min" : "maj")
            }
            if fifth == 8 { name += "♯5" }
        }
        // A natural 9th over a 7th is the 9th chord; over a 6th, the 6/9.
        if seventh != nil, name != "dim7", let nine = tensions.firstIndex(of: 2) {
            name = name.replacingFirst("7", with: "9")
            tensions.remove(at: nine)
        }
        if six, let nine = tensions.firstIndex(of: 2) {
            name += "/9"
            tensions.remove(at: nine)
        }
        if let sus { name = (name == "maj" ? "" : name) + sus }
        if third == nil, sus == nil, fifth == 7, pitchClasses.count == 2 { return "5" }

        let tensionName = [1: "♭9", 2: "9", 3: "♯9", 5: "11", 6: "♯11", 8: "♭13", 9: "13"]
        // Over no 7th every tension is added; over one, a natural 9th, 11th
        // or 13th is the chord's own number and an altered one joins it.
        var marks = tensions.map { (seventh == nil ? "add" : "") + tensionName[$0]! }
        if bothSevenths { marks.insert("add♭7", at: 0) }
        if fifth == 6, !dim { marks.insert("♭5", at: 0) }
        if fifth == nil, third != nil || sus != nil { marks.append("no5") }
        if third == nil, sus == nil { marks.insert("no3", at: 0) }

        // One alteration joins the name (7♭9, add9); a natural tension over
        // a 7th, a tone left out, or more than one go in brackets.
        if marks.count == 1, let mark = marks.first,
           !mark.hasPrefix("no"), mark != "♭5", mark != "add♭7",
           !(seventh != nil && ["9", "11", "13"].contains(mark)) {
            let base = name == "maj" ? "" : name
            return base + (base.isEmpty || mark.hasPrefix("♭") || mark.hasPrefix("♯") ? "" : " ") + mark
        }
        guard !marks.isEmpty else { return name }
        return name + "(" + marks.joined(separator: ", ") + ")"
    }

    /// A chord whose own name is awkward (a tone left out, a ♭13 over no
    /// 7th) but whose tones are a plain triad or 7th chord on another of
    /// them, over this root: C E G over E is "C/E". The other chord's root,
    /// in semitones above this one's, and its quality.
    public var slash: (root: Int, quality: String)? {
        let own = name
        guard pitchClasses.count == 3 || pitchClasses.count == 4,
              own.contains("(") || own.hasSuffix("♯5") || own.contains("♭13") else { return nil }
        let plain: [([Int], String)] = [([0, 4, 7], ""), ([0, 3, 7], "min"), ([0, 4, 7, 10], "7"),
                                        ([0, 3, 7, 10], "min7"), ([0, 4, 7, 11], "maj7")]
        for root in pitchClasses where root != 0 {
            let shifted = pitchClasses.map { ($0 - root + 12) % 12 }.sorted()
            if let match = plain.first(where: { $0.0 == shifted }) { return (root, match.1) }
        }
        return nil
    }
}

private extension String {
    /// The string with the first `target` replaced, or as it is.
    func replacingFirst(_ target: Character, with replacement: String) -> String {
        guard let i = firstIndex(of: target) else { return self }
        return String(self[..<i]) + replacement + String(self[index(after: i)...])
    }
}
