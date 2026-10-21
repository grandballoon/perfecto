// A chord built from buttons, as an Orchid builds one: a type (the triad)
// and any extensions added to it. Each button says one thing about the
// chord, so the chord is the same on every root and in every key.

/// The triad a chord is built on, chosen by a button.
public enum ChordType: CaseIterable, Hashable, Codable, Sendable {
    /// The root alone, with nothing built on it.
    case note
    case diminished, minor, major
    /// The fourth in the third's place.
    case suspended

    /// What its button is marked.
    public var mark: String {
        switch self {
        case .note:       return "Note"
        case .diminished: return "Dim"
        case .minor:      return "Min"
        case .major:      return "Maj"
        case .suspended:  return "Sus"
        }
    }
}

/// A note added to a chord's triad, chosen by a button.
public enum ChordExtension: CaseIterable, Hashable, Codable, Sendable {
    /// The sixth, which over a seventh is a thirteenth.
    case sixth
    case minorSeventh, majorSeventh
    case ninth

    /// What its button is marked.
    public var mark: String {
        switch self {
        case .sixth:        return "6"
        case .minorSeventh: return "m7"
        case .majorSeventh: return "M7"
        case .ninth:        return "9"
        }
    }
}

/// A chord as buttons build it: a type, or the degree's own triad, and the
/// extensions added to it.
public struct ChordBuild: Hashable, Codable, Sendable {
    /// nil: the triad of the degree that plays, as the key has it.
    public let type: ChordType?
    /// A note has none: they are kept only for a triad.
    public let extensions: Set<ChordExtension>

    public init(type: ChordType?, extensions: Set<ChordExtension> = []) {
        self.type = type
        self.extensions = type == .note ? [] : extensions
    }

    /// The buttons that build it, as an Orchid's are marked: "Min · m7 9".
    public var legend: String {
        let extensions = ChordExtension.allCases.filter(self.extensions.contains).map(\.mark)
        let parts = [type?.mark].compactMap { $0 } + (extensions.isEmpty ? [] : [extensions.joined(separator: " ")])
        return parts.isEmpty ? "Base" : parts.joined(separator: " · ")
    }

    /// The chord on a degree whose own triad is `base`.
    ///
    /// The extensions are added above the triad: the sixth (a diminished
    /// triad's is its seventh, so a diminished seventh), a seventh, and
    /// the ninth an octave above the second. The sixth over a seventh is
    /// the thirteenth, above the ninth's octave, and the two sevenths
    /// together are the major one.
    func shape(base: TriadBase) -> ChordShape {
        let triad: Triad
        if let type {
            // A note is its root, and its name is its root's.
            guard let typed = Triad(type) else { return ChordShape([0], "") }
            triad = typed
        } else {
            triad = Triad(base)
        }
        let seventh = extensions.contains(.majorSeventh) ? 11
            : extensions.contains(.minorSeventh) ? 10 : nil
        let sixth = extensions.contains(.sixth)
        let ninth = extensions.contains(.ninth)

        var intervals = triad.intervals
        if sixth { intervals.append(seventh == nil ? 9 : 21) }
        if let seventh { intervals.append(seventh) }
        if ninth { intervals.append(14) }
        return ChordShape(intervals.sorted(),
                          Self.name(triad, sixth: sixth, seventh: seventh, ninth: ninth))
    }

    /// "maj9", "min6/9", "7sus4(13)": the chord's quality as the app names
    /// the joystick's (`JoystickMap`).
    private static func name(_ triad: Triad, sixth: Bool, seventh: Int?, ninth: Bool) -> String {
        guard let seventh else {
            switch (sixth, ninth) {
            case (false, false): return triad.name
            case (false, true):  return triad == .major ? "add9" : "\(triad.name) add9"
            case (true, false):  return triad.sixthName
            case (true, true):   return triad == .diminished ? "dim7 add9" : triad.sixthName + "/9"
            }
        }
        var name = triad.seventhName(major: seventh == 11)
        // A ninth over a seventh names the chord by its ninth.
        if ninth { name = name.replacingFirst("7", with: "9") }
        if sixth { name += "(13)" }
        return name
    }

    /// The triad under the extensions.
    private enum Triad {
        case diminished, minor, major, suspended

        /// nil for a note, which has no triad.
        init?(_ type: ChordType) {
            switch type {
            case .note:       return nil
            case .diminished: self = .diminished
            case .minor:      self = .minor
            case .major:      self = .major
            case .suspended:  self = .suspended
            }
        }

        init(_ base: TriadBase) {
            switch base {
            case .major: self = .major
            case .minor: self = .minor
            case .dim:   self = .diminished
            }
        }

        var intervals: [Int] {
            switch self {
            case .diminished: return [0, 3, 6]
            case .minor:      return [0, 3, 7]
            case .major:      return [0, 4, 7]
            case .suspended:  return [0, 5, 7]
            }
        }

        var name: String {
            switch self {
            case .diminished: return "dim"
            case .minor:      return "min"
            case .major:      return "maj"
            case .suspended:  return "sus4"
            }
        }

        /// With a sixth and no seventh.
        var sixthName: String {
            switch self {
            case .diminished: return "dim7"
            case .minor:      return "min6"
            case .major:      return "6"
            case .suspended:  return "6sus4"
            }
        }

        /// With the major seventh, or the minor one.
        func seventhName(major: Bool) -> String {
            switch self {
            case .diminished: return major ? "dim(maj7)" : "min7♭5"
            case .minor:      return major ? "min(maj7)" : "min7"
            case .major:      return major ? "maj7" : "7"
            case .suspended:  return major ? "maj7sus4" : "7sus4"
            }
        }
    }
}

private extension String {
    func replacingFirst(_ target: Character, with replacement: Character) -> String {
        guard let index = firstIndex(of: target) else { return self }
        var copy = self
        copy.replaceSubrange(index...index, with: String(replacement))
        return copy
    }
}
