import SwiftUI

/// The key strip: the key and the voicing in a row on the play screen. The
/// key's root is changed by a swipe (`KeyField`); the octave and the
/// inversion are one field, changed together by a finger on it
/// (`KeyVoicingField`). The key's root and the octave are the Key page's,
/// within reach while playing; the scale is still set there. A chord being
/// held stays in the key it was struck in, and takes a change of voicing
/// up at once.
struct KeyStrip: View {
    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            KeyField()
            KeyVoicingField()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
    }
}
