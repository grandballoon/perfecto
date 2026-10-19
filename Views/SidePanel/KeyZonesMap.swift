import SwiftUI

/// The seven chord keys in small, side by side, each drawn divided into its
/// zones as it is on the play screen: the Key zones card's picture of what
/// every key plays. A zone that plays something is filled and says what (its
/// effect, its octave); a plain one is left dim.
///
/// Tapping a key chooses it, so the card shows that key's own zones; tapping
/// it again goes back to the zones of every key.
struct KeyZonesMap: View {
    /// The key, which names each chord key ("ii", "vii°").
    let key: Key
    /// The zones each chord key is divided into now.
    let zones: (Degree) -> KeyZoneSettings
    /// Whether a chord key has zones of its own in place of every key's.
    let hasOwn: (Degree) -> Bool
    @Binding var selected: Degree?

    private static let keyHeight: CGFloat = 72
    private static let corner: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Degree.allCases) { degree in
                let name = degreeNumeral(key: key, degree: degree)
                Button { selected = selected == degree ? nil : degree } label: {
                    VStack(spacing: 4) {
                        miniKey(degree)
                        Text(name)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(selected == degree ? .white : Color(white: 0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zones of \(name)")
                .accessibilityAddTraits(selected == degree ? .isSelected : [])
            }
        }
    }

    /// One key: its zones as bands, the top one first, as they lie on the key.
    private func miniKey(_ degree: Degree) -> some View {
        let isSelected = selected == degree
        return VStack(spacing: 1) {
            ForEach(Array(zones(degree).zones.enumerated().reversed()), id: \.offset) { _, zone in
                ZStack {
                    Rectangle().fill(Color.orange.opacity(zone.isPlain ? 0.2 : 0.65))
                    Text(label(of: zone))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: Self.keyHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(RoundedRectangle(cornerRadius: Self.corner)
            .strokeBorder(stroke(of: degree, isSelected: isSelected), lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
    }

    /// A key with zones of its own is outlined as the keys are; one divided
    /// as every key is, faintly.
    private func stroke(of degree: Degree, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return hasOwn(degree) ? .orange : Color(white: 0.3)
    }

    /// What a zone plays, in the little room there is: "AR1", "O5", "REV O3", "I+1".
    private func label(of zone: KeyZone) -> String {
        [zone.effect?.abbreviation, zone.octave.map { "O\($0)" }, zone.inversion.map { "I\($0.label)" }]
            .compactMap { $0 }.joined(separator: " ")
    }
}
