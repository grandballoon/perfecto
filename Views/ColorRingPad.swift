import SwiftUI

/// The color ring (`ColorRing`), drawn for one degree in one key: each cell
/// named by the chord it plays on that degree, the degree's own mode's
/// sector shaded and its name lit, the chosen cell lit, and the cells one
/// step from what it plays (`colorSteps`) lit more faintly, each as it would
/// be with the tone marks on. Cells with the same notes as the chosen one
/// are outlined. A finger chooses the cell it is on, and the cells it
/// crosses as it moves (`onChoose` once for each), and says when it lifts
/// (`onLift`); the ring keeps nothing else, so the caller says what is
/// chosen.
struct ColorRingPad: View {
    let key: Key
    let degree: Degree
    let arrangement: ColorRingArrangement
    let chosen: ColorRingPosition
    let marks: ToneMarks
    let onChoose: (ColorRingPosition) -> Void
    var onLift: () -> Void = {}

    @State private var lastCell: ColorRingPosition? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        GeometryReader { geo in
            let geometry = ColorRingGeometry(size: geo.size, turn: ColorRing.turn(arrangement, key: key, degree: degree),
                                             fitsGap: arrangement == .fixed)
            let own = ChordGrid.ownMode(key: key, degree: degree)
            let playing = ColorRing.color(at: chosen, marks: marks, key: key, degree: degree)
            let chosenSector = ColorRing.sector(of: chosen, key: key, degree: degree)
            let fontSize = min(max(geometry.band * 0.4, 6), 11)
            ZStack {
                ForEach(ColorRing.modes.indices, id: \.self) { sector in
                    ForEach(ColorRingGeometry.heights, id: \.self) { height in
                        let position = ColorRing.position(height: height, sector: sector, arrangement: arrangement,
                                                          key: key, degree: degree)
                        let color = ColorRing.color(at: position, marks: marks, key: key, degree: degree)
                        let isChosen = sector == chosenSector && height == chosen.height
                        let steps = colorSteps(playing, color, key: key, degree: degree)
                        cell(geometry.path(height: height, sector: sector), isChosen: isChosen, steps: steps,
                             isOwn: ColorRing.modes[sector] == own)
                        Text(Self.shortName(ColorRing.modes[sector], height))
                            .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isChosen ? Color.black : Color(white: steps <= 1 ? 1 : 0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(width: geometry.band * 2.2)
                            .position(geometry.middle(height: height, sector: sector))
                    }
                    Text(Self.abbreviation(ColorRing.modes[sector]))
                        .font(.system(size: max(fontSize - 1, 6), weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorRing.modes[sector] == own ? Color.orange : Color(white: 0.4))
                        .position(geometry.modeLabel(sector: sector))
                }
                geometry.seam
                    .stroke(Color(white: 0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard let cell = geometry.cell(at: value.location) else { return }
                        let position = ColorRing.position(height: cell.height, sector: cell.sector,
                                                          arrangement: arrangement, key: key, degree: degree)
                        guard position != lastCell else { return }
                        lastCell = position
                        haptic.impactOccurred()
                        onChoose(position)
                    }
                    .onEnded { _ in
                        lastCell = nil
                        onLift()
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color ring")
    }

    @ViewBuilder
    private func cell(_ path: Path, isChosen: Bool, steps: Int, isOwn: Bool) -> some View {
        let fill: Color = isChosen ? .orange
            : steps == 0 ? Color(white: 0.23)
            : steps == 1 ? Color(red: 0.42, green: 0.27, blue: 0.06)
            : Color(white: isOwn ? 0.18 : 0.12)
        path.fill(fill)
        path.stroke(Color.black, lineWidth: 1.5)
        if steps == 0 && !isChosen {
            path.stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }

    /// A cell's name with room for it: "m" for "min" and "°" for a
    /// diminished triad.
    static func shortName(_ mode: HeptatonicMode, _ height: StackHeight) -> String {
        let name = tertianChordName(mode, height: height)
        if name == "dim" { return "°" }
        if name == "min" { return "m" }
        return name.replacingOccurrences(of: "min", with: "m")
    }

    /// A mode's name in three letters.
    static func abbreviation(_ mode: HeptatonicMode) -> String {
        String(mode.displayName.prefix(3)).uppercased()
    }
}
