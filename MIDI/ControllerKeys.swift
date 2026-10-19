/// Which of a controller's keys a note is, worked out from the notes alone.
///
/// The octave buttons shift the notes the keys send and say nothing of
/// it, so the shift is the one that last made sense: it stays as it is
/// while the notes fit the keys, and a note above or below them shifts it
/// by as few octaves as take it in. So a shift is seen from the first note
/// played after it that the keys as they were could not have sent.
struct ControllerKeys: Equatable, Sendable {
    let keyboard: ControllerKeyboard
    /// Octaves up from where the keys are with no shift.
    private(set) var shift = 0

    init(_ keyboard: ControllerKeyboard) {
        self.keyboard = keyboard
    }

    /// The notes the keys send, as shifted now.
    var notes: ClosedRange<Int> {
        let notes = keyboard.notes
        return (notes.lowerBound + shift * 12)...(notes.upperBound + shift * 12)
    }

    /// The key `note` is, from 0 at the lowest, with the shift moved to
    /// take it in if it has to be.
    mutating func key(of note: Int) -> Int {
        while note < notes.lowerBound { shift -= 1 }
        while note > notes.upperBound { shift += 1 }
        return note - notes.lowerBound
    }

    /// The key `note` is as the keys are shifted now; nil for a note they
    /// do not send.
    func key(at note: Int) -> Int? {
        notes.contains(note) ? note - notes.lowerBound : nil
    }
}
