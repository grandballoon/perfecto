import SwiftUI

extension PianoSource {
    /// The color the source's notes are lit in.
    var color: Color {
        switch self {
        case .keys:    return .orange
        case .layers:  return Color(red: 0.35, green: 0.7, blue: 1)
        case .solo:    return Color(red: 0.45, green: 0.85, blue: 0.45)
        case .tonnetz: return Color(red: 0.8, green: 0.5, blue: 1)
        }
    }
}

/// The piano (`PianoState`): its 88 keys across the width it is given, each
/// lit in the colors of the sources sounding its note. A key that several
/// sources are sounding is divided between their colors along its length.
/// It is only looked at: no touch plays it.
struct PianoView: View {
    @Environment(PerformanceState.self) private var state

    /// The narrowest white key that has room for its octave's name.
    private static let namedKeyWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let keys = PianoKeys(size: geo.size)
            let lights = state.piano.lights
            ZStack(alignment: .topLeading) {
                // The black keys lie over the white ones.
                ForEach(PianoKeys.whites + PianoKeys.blacks, id: \.self) { note in
                    key(note, in: keys, lit: lights[note] ?? [])
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color.black)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Piano")
    }

    private func key(_ note: Int, in keys: PianoKeys, lit: [PianoSource]) -> some View {
        let isBlack = PianoKeys.isBlack(note)
        let frame = keys.frame(of: note)
        return VStack(spacing: 0) {
            if lit.isEmpty {
                Color(white: isBlack ? 0.08 : 0.92)
            } else {
                ForEach(lit, id: \.self) { $0.color }
            }
        }
        // A lit black key is a shade darker than the white keys lit beside it.
        .overlay(Color.black.opacity(isBlack && !lit.isEmpty ? 0.25 : 0))
        .overlay(alignment: .bottom) {
            if keys.whiteWidth >= Self.namedKeyWidth, let name = PianoKeys.octaveName(of: note) {
                Text(name)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(lit.isEmpty ? 0.45 : 0.8))
                    .fixedSize()
                    .padding(.bottom, 4)
            }
        }
        .border(Color.black, width: 0.5)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}
