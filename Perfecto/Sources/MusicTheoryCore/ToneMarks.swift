// Marks on a stack of thirds: each tone above the root moved a semitone up
// or down, or left out. A chord symbol is built the same way (C9♯5♯9 is the
// 9th chord with its 5th and 9th raised), so every color a lead sheet names
// is a stack and a few marks, and every mark is one step (`colorSteps`).

/// A tone of a stack of thirds above its root, by the degree it stands for.
public enum ChordTone: Int, CaseIterable, Hashable, Codable, Sendable {
    case third = 3, fifth = 5, seventh = 7, ninth = 9, eleventh = 11, thirteenth = 13

    /// Which third of the stack it is: the 3rd is the first above the root.
    var stackIndex: Int { (rawValue - 1) / 2 }

    /// The semitones above the root a mark can take the tone to, each of
    /// which has a name (`name(at:)`): a 7th lowered to 9 is a 6th, and one
    /// raised past 11 would be the root.
    var range: ClosedRange<Int> {
        switch self {
        case .third:      return 2...5
        case .fifth:      return 6...8
        case .seventh:    return 9...11
        case .ninth:      return 13...15
        case .eleventh:   return 16...18
        case .thirteenth: return 20...22
        }
    }

    /// The tone's name at `semitones` above the root, as a chord symbol
    /// writes it: "sus4", "♯5", "maj7", "♭9".
    public func name(at semitones: Int) -> String {
        switch (self, semitones) {
        case (.third, 2):  return "sus2"
        case (.third, 3):  return "♭3"
        case (.third, 4):  return "3"
        case (.third, 5):  return "sus4"
        case (.seventh, 9):  return "6"
        case (.seventh, 10): return "♭7"
        case (.seventh, 11): return "maj7"
        default:
            let natural = [5: 7, 9: 14, 11: 17, 13: 21][rawValue]!
            let offset = semitones - natural
            return (offset < 0 ? "♭" : offset > 0 ? "♯" : "") + String(rawValue)
        }
    }
}

/// Marks on a stack's tones: a tone moved a semitone up (+1) or down (-1),
/// and tones whose leaving out is turned round. A tone the stack leaves out
/// to begin with (`droppedTones`) is brought back by the same mark that
/// leaves another out.
public struct ToneMarks: Hashable, Codable, Sendable {
    public private(set) var moves: [ChordTone: Int] = [:]
    public private(set) var skips: Set<ChordTone> = []

    public static let none = ToneMarks()

    public init() {}

    public var isEmpty: Bool { moves.isEmpty && skips.isEmpty }

    /// How far `tone` is marked to move: +1, -1 or 0.
    public func move(of tone: ChordTone) -> Int { moves[tone] ?? 0 }

    /// Whether `tone`'s leaving out is turned round.
    public func skips(_ tone: ChordTone) -> Bool { skips.contains(tone) }

    /// Marks `tone` to move by `offset` (+1 or -1); marking it the same way
    /// again takes the mark off.
    public mutating func toggleMove(_ tone: ChordTone, by offset: Int) {
        precondition(offset == 1 || offset == -1, "a mark moves a tone one semitone")
        moves[tone] = move(of: tone) == offset ? nil : offset
    }

    /// Turns round whether `tone` is left out.
    public mutating func toggleSkip(_ tone: ChordTone) {
        if skips.remove(tone) == nil { skips.insert(tone) }
    }

    /// Marks `tone` to move by `offset` (+1 or -1), or not to move (0),
    /// whatever it was marked before.
    public mutating func setMove(_ tone: ChordTone, to offset: Int) {
        precondition((-1...1).contains(offset), "a mark moves a tone one semitone")
        moves[tone] = offset == 0 ? nil : offset
    }

    /// Sets whether `tone`'s leaving out is turned round.
    public mutating func setSkip(_ tone: ChordTone, _ isOn: Bool) {
        if isOn { skips.insert(tone) } else { skips.remove(tone) }
    }
}

/// One tone of a marked stack: which it is, where the mode puts it, and
/// where it sounds once marked.
public struct MarkedTone: Hashable, Sendable {
    public let tone: ChordTone
    /// Semitones above the root, as the mode stacks it.
    public let stacked: Int
    /// Semitones above the root, once its move is made.
    public let sounding: Int
    public var isMoved: Bool { sounding != stacked }
}

/// The tones of `height` thirds stacked through `mode` above the root, with
/// none left out (`stackThirds` leaves out the ones in `droppedTones`).
public func stackedTones(_ mode: [Int], height: StackHeight) -> [(tone: ChordTone, semitones: Int)] {
    precondition(mode.count == 7 && mode.first == 0, "a mode is seven intervals from 0")
    return ChordTone.allCases.prefix(height.rawValue - 1).map { tone in
        let step = 2 * (tone.stackIndex)
        return (tone, mode[step % 7] + (step / 7) * 12)
    }
}

/// The tones `stackThirds` leaves out: a perfect 11th over a major 3rd
/// clashes, so an 11th chord leaves out its 3rd and a 13th chord its 11th.
public func droppedTones(_ mode: [Int], height: StackHeight) -> Set<ChordTone> {
    let tones = stackedTones(mode, height: height)
    guard tones.count > 4, tones[0].semitones == 4, tones[4].semitones == 17 else { return [] }
    return [height == .eleventh ? .third : .eleventh]
}

/// The tones `height` thirds stacked through `mode` sound with `marks`, from
/// the 3rd up: the ones left out are not there. A move is made only where
/// the tone has a name there and no other tone already sounds that pitch
/// class, since landing on one is not a move but a tone lost; tones are
/// moved in order from the 3rd.
public func markedTones(_ mode: [Int], height: StackHeight, marks: ToneMarks) -> [MarkedTone] {
    let dropped = droppedTones(mode, height: height)
    let present = stackedTones(mode, height: height)
        .filter { dropped.contains($0.tone) == marks.skips($0.tone) }
    var sounding = present.map(\.semitones)
    for (i, entry) in present.enumerated() {
        let offset = marks.move(of: entry.tone)
        guard offset != 0 else { continue }
        let target = entry.semitones + offset
        let others = Set(([0] + sounding.enumerated().filter { $0.offset != i }.map(\.element)).map { $0 % 12 })
        if entry.tone.range.contains(target), !others.contains(target % 12) { sounding[i] = target }
    }
    return zip(present, sounding).map { MarkedTone(tone: $0.tone, stacked: $0.semitones, sounding: $1) }
}

/// `stackThirds` with `marks`: the root and the marked tones. With no marks
/// it is `stackThirds` itself.
public func markedStack(_ mode: [Int], height: StackHeight, marks: ToneMarks) -> [Int] {
    [0] + markedTones(mode, height: height, marks: marks).map(\.sounding)
}

/// The marks a chord symbol adds to the stack's own name, in order from the
/// 3rd: a tone moved by its name there ("♯5"), a tone left out as "no 7",
/// and one brought back as "add 3".
public func markNames(_ mode: [Int], height: StackHeight, marks: ToneMarks) -> [String] {
    let dropped = droppedTones(mode, height: height)
    let sounding = markedTones(mode, height: height, marks: marks)
    return stackedTones(mode, height: height).compactMap { entry in
        if marks.skips(entry.tone) {
            return (dropped.contains(entry.tone) ? "add " : "no ") + String(entry.tone.rawValue)
        }
        guard let marked = sounding.first(where: { $0.tone == entry.tone }), marked.isMoved else { return nil }
        return entry.tone.name(at: marked.sounding)
    }
}

/// The name of a marked stack: the stack's own (`tertianChordName`) and the
/// marks in brackets, e.g. "9(♯5, ♯9)".
public func markedChordName(_ mode: HeptatonicMode, height: StackHeight, marks: ToneMarks) -> String {
    let name = tertianChordName(mode, height: height)
    let added = markNames(mode.intervals, height: height, marks: marks)
    return added.isEmpty ? name : name + "(" + added.joined(separator: ", ") + ")"
}

/// What a tone's marks can do in a stack, for the controls that set them.
public struct ToneMarkOption: Hashable, Sendable {
    public let tone: ChordTone
    /// Whether the stack has the tone at all.
    public let isInStack: Bool
    /// Whether it is left out now, by the stack or by a mark.
    public let isLeftOut: Bool
    /// Whether the stack leaves it out to begin with.
    public let isDroppedByStack: Bool
    /// The tone's name a semitone up or down from where the stack puts it,
    /// or nil where a move cannot be made.
    public let up: String?
    public let down: String?
    /// The move made now: +1, -1 or 0.
    public let moved: Int
}

/// Every tone's options in a stack with `marks`, from the 3rd up.
public func toneMarkOptions(_ mode: [Int], height: StackHeight, marks: ToneMarks) -> [ToneMarkOption] {
    let stacked = stackedTones(mode, height: height)
    let dropped = droppedTones(mode, height: height)
    let sounding = markedTones(mode, height: height, marks: marks)
    return ChordTone.allCases.map { tone in
        guard let entry = stacked.first(where: { $0.tone == tone }) else {
            return ToneMarkOption(tone: tone, isInStack: false, isLeftOut: false, isDroppedByStack: false,
                                  up: nil, down: nil, moved: 0)
        }
        let here = sounding.first { $0.tone == tone }
        let others = Set(([0] + sounding.filter { $0.tone != tone }.map(\.sounding)).map { $0 % 12 })
        func name(_ offset: Int) -> String? {
            let target = entry.semitones + offset
            guard here != nil, tone.range.contains(target), !others.contains(target % 12) else { return nil }
            return tone.name(at: target)
        }
        return ToneMarkOption(tone: tone, isInStack: true, isLeftOut: here == nil,
                              isDroppedByStack: dropped.contains(tone),
                              up: name(1), down: name(-1),
                              moved: here.map { $0.sounding - $0.stacked } ?? 0)
    }
}
