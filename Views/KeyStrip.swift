import SwiftUI

/// The key strip: the key, the voicing and the color in a row on the play
/// screen. The key's root is changed by a swipe (`KeyField`); the octave
/// and the inversion are one field, changed together by a finger on it
/// (`KeyVoicingField`), and so is the color, through every one the joystick
/// has in each of its modes (`KeyColorField`). The key's root and the
/// octave are the Key page's, within reach while playing; the scale is
/// still set there. A chord being held stays in the key it was struck in,
/// and takes a change of voicing or color up at once.
struct KeyStrip: View {
    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            // The key gives up room first: its name shrinks to fit.
            KeyField()
            KeyVoicingField()
            KeyColorField()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
    }
}
