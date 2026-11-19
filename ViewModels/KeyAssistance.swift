/// How the play screen helps keep to the key: whether the choices that
/// would take the chord out of the key are told apart from the rest, and
/// whether they sound. It reaches every color surface (the compass, the
/// table and the tree) and the octave's roots outside the key, and is
/// chosen in Setup (`PerformanceState.keyAssistance`).
///
/// A choice is out of the key when the chord it plays has a tone the key
/// has not (`ColorFit.borrowed`). An avoid note is in the key, so it is not.
/// Which choices those are depends on the chord held, so with none held
/// nothing is told apart.
enum KeyAssistance: CaseIterable {
    /// No help: every choice is drawn alike and sounds.
    case none
    /// The choices in the key and those out of it are drawn in two colors.
    case colorCode
    /// The choices out of the key are greyed out and play nothing: a finger
    /// can press one or slide over it and the chord stays as it was.
    case assist

    var displayName: String {
        switch self {
        case .none:      return "Normal"
        case .colorCode: return "Color code"
        case .assist:    return "Assist"
        }
    }

    /// How a choice is drawn that is in the key or out of it; nil when that
    /// cannot be told (no chord is held).
    func mark(isInKey: Bool?) -> KeyMark {
        guard let isInKey else { return .plain }
        switch self {
        case .none:      return .plain
        case .colorCode: return isInKey ? .inKey : .outOfKey
        case .assist:    return isInKey ? .plain : .silent
        }
    }

    /// Whether a choice that is in the key or out of it sounds.
    func sounds(isInKey: Bool) -> Bool {
        self != .assist || isInKey
    }

    /// The chord a walk of the compass's places makes from `origin` on
    /// `degree` in `key`, each a step from where the last led. A place with
    /// no choice is left out (`StepCompass.walk`), and so, while assisting,
    /// is a step to a chord out of the key, so only chords in the key are
    /// heard however the walk was kept.
    func walk(_ places: [CompassPlace], from origin: ChordTones, key: Key, degree: Degree,
              ranking: ColorStepRanking) -> ChordTones {
        places.reduce(origin) { tones, place in
            guard let step = StepCompass.step(at: place, from: tones, key: key, degree: degree, ranking: ranking),
                  sounds(isInKey: step.fit != .borrowed) else { return tones }
            return step.tones
        }
    }

    /// Whether a finger may take `path` from `origin` on `degree` in `key`:
    /// while assisting, not if a step on it leads out of the key. A place
    /// with no choice is no step, so it does not stop it.
    func sounds(_ path: [CompassPlace], from origin: ChordTones, key: Key, degree: Degree,
                ranking: ColorStepRanking) -> Bool {
        var tones = origin
        for place in path {
            guard let step = StepCompass.step(at: place, from: tones, key: key, degree: degree, ranking: ranking)
            else { continue }
            guard sounds(isInKey: step.fit != .borrowed) else { return false }
            tones = step.tones
        }
        return true
    }

    /// Whether every tone of `tones` on `degree` is in `key`.
    static func isInKey(_ tones: ChordTones, key: Key, degree: Degree) -> Bool {
        let root = key.scale.offset(of: degree)
        return tones.pitchClasses.allSatisfy { key.scale.intervals.contains((root + $0) % 12) }
    }
}

/// How a choice is drawn by the key assistance (`KeyAssistance.mark`).
enum KeyMark: Equatable {
    /// As every other: nothing to tell it apart.
    case plain
    /// In the key, in its color.
    case inKey
    /// Out of the key, in the other color.
    case outOfKey
    /// Out of the key and greyed out: it plays nothing.
    case silent
}
