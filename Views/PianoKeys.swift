import CoreGraphics

/// Where a piano's 88 keys are in a strip of `size`: the white keys side by
/// side across it, and each black key over the line between the two white
/// keys it lies between. The piano is drawn from these frames.
struct PianoKeys {
    /// A0 to C8, as MIDI notes.
    static let notes = 21...108

    static let whites = notes.filter { !isBlack($0) }
    static let blacks = notes.filter(isBlack)

    /// A black key's width and length, as shares of a white key's.
    static let blackWidth: CGFloat = 0.6
    static let blackLength: CGFloat = 0.62

    let size: CGSize

    static func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note % 12)
    }

    /// The octave a C begins, as the app numbers them (middle C is "C4");
    /// nil for any other note.
    static func octaveName(of note: Int) -> String? {
        note % 12 == 0 ? "C\(note / 12 - 1)" : nil
    }

    /// The height the strip is given in a screen `width` wide: keys of
    /// about a piano's proportions, kept tall enough to be read on a phone
    /// and short enough to leave a wide window to the rest.
    static func height(forWidth width: CGFloat) -> CGFloat {
        (width / CGFloat(whites.count) * 4.5).clamped(to: 44...104)
    }

    var whiteWidth: CGFloat { size.width / CGFloat(Self.whites.count) }

    /// The frame of `note`'s key, for a note in `notes`.
    func frame(of note: Int) -> CGRect {
        let whitesBelow = CGFloat((Self.notes.lowerBound..<note).filter { !Self.isBlack($0) }.count)
        guard Self.isBlack(note) else {
            return CGRect(x: whitesBelow * whiteWidth, y: 0, width: whiteWidth, height: size.height)
        }
        let width = whiteWidth * Self.blackWidth
        return CGRect(x: whitesBelow * whiteWidth - width / 2, y: 0,
                      width: width, height: size.height * Self.blackLength)
    }
}
