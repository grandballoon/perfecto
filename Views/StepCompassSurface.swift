import SwiftUI

/// Where the step compass's places are: a cross on a grid of five columns
/// and five rows, the plain chord in the middle. Up adds a tone, right
/// raises one, left lowers one, down takes one away; each kind's first
/// choice is next to the middle and its second beyond it.
enum StepCompassGrid {
    static let size = 5
    static let middle = (column: 2, row: 2)
    /// The gap between neighbouring cells.
    static let spacing: CGFloat = 4

    /// What a finger can be on: a place, or the middle.
    enum Target: Hashable {
        case place(CompassPlace)
        case middle
    }

    /// The column and row of `place`.
    static func cell(of place: CompassPlace) -> (column: Int, row: Int) {
        let out = place.rank
        switch place.kind {
        case .add:      return (2, 2 - out)
        case .takeAway: return (2, 2 + out)
        case .raise:    return (2 + out, 2)
        case .lower:    return (2 - out, 2)
        }
    }

    /// The frame of the cell at `column` and `row` in a compass of `size`.
    static func frame(column: Int, row: Int, in size: CGSize) -> CGRect {
        let n = CGFloat(Self.size)
        let width = (size.width - spacing * (n - 1)) / n
        let height = (size.height - spacing * (n - 1)) / n
        return CGRect(x: CGFloat(column) * (width + spacing), y: CGFloat(row) * (height + spacing),
                      width: width, height: height)
    }

    /// What is under `point` in a compass of `size`: nil in a gap between
    /// cells, in a corner, or outside it, so a finger sliding across one
    /// stays on what it was on.
    static func target(at point: CGPoint, in size: CGSize) -> Target? {
        let candidates = [Target.middle] + CompassPlace.all.map { .place($0) }
        return candidates.first { target in
            let cell = target.cell
            return frame(column: cell.column, row: cell.row, in: size).contains(point)
        }
    }
}

extension StepCompassGrid.Target {
    /// The column and row the target is drawn at.
    var cell: (column: Int, row: Int) {
        switch self {
        case .place(let place): return StepCompassGrid.cell(of: place)
        case .middle:           return StepCompassGrid.middle
        }
    }
}

/// The step compass, wired to the live performance. With no chord held, or
/// with Setup's switch off (`compassShowsChords`), its places are named by
/// what they do, and one can come down before the
/// chord, so the chord starts in its color; with a chord held each place is
/// named by the chord it plays. While the compass keeps its color (the pin),
/// each tap is a step from the last and the middle clears them.
///
/// A finger slides from cell to cell: the compass is read as one surface
/// (`StepCompassGrid.target`), and a cell the finger moves onto is pressed
/// as a tap there would be, so a finger played is the latest place it is
/// on and a finger kept walks a step for every place it crosses. A gap, a
/// corner or a place with no chord leaves it on what it was on.
struct StepCompassSurface: View {
    @Environment(PerformanceState.self) private var state

    /// What the finger on the compass is on, while one is.
    @State private var touched: StepCompassGrid.Target?

    var body: some View {
        // The chord the places are named for, if they are named by chords.
        let degree = state.compassShowsChords ? state.activeDegree : nil
        let steps = degree.map {
            StepCompass.steps(from: state.compassOrigin(for: $0), key: state.playedKey, degree: $0,
                              ranking: state.compassRanking)
        }
        let stepOf = { (place: CompassPlace) -> ColorStep? in
            steps?[place.kind].flatMap { $0.indices.contains(place.rank - 1) ? $0[place.rank - 1] : nil }
        }
        GeometryReader { geo in
            let middle = StepCompassGrid.frame(column: StepCompassGrid.middle.column,
                                               row: StepCompassGrid.middle.row, in: geo.size)
            let keepSide = min(middle.height, 34)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(CompassPlace.all, id: \.self) { place in
                        let cell = StepCompassGrid.cell(of: place)
                        let frame = StepCompassGrid.frame(column: cell.column, row: cell.row, in: geo.size)
                        placeButton(place, step: degree.flatMap { _ in stepOf(place) }, degree: degree)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                    middleButton(degree: degree)
                        .frame(width: middle.width, height: middle.height)
                        .offset(x: middle.minX, y: middle.minY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard let target = StepCompassGrid.target(at: drag.location, in: geo.size),
                                  target != touched else { return }
                            if case .place(let place) = target, degree != nil, stepOf(place) == nil { return }
                            touched = target
                            switch target {
                            case .place(let place): state.compassPressed(place)
                            case .middle:           state.compassCleared()
                            }
                        }
                        .onEnded { _ in
                            if case .place(let place) = touched { state.compassLifted(place) }
                            touched = nil
                        }
                )
                @Bindable var state = state
                KeepSwitch(label: "Keep the compass's color", keeps: $state.keepsCompassColor)
                    .frame(height: keepSide)
                    .offset(x: geo.size.width - keepSide, y: geo.size.height - keepSide)
            }
        }
    }

    private func placeButton(_ place: CompassPlace, step: ColorStep?, degree: Degree?) -> some View {
        let isOn = !state.keepsCompassColor && state.compassPlaces.first == place
        let text: String, detail: String
        if let degree {
            text = step.map { name(of: $0, on: degree) } ?? "—"
            detail = step.map { $0.editName + ($0.fit == .avoid ? " · avoid" : $0.fit == .borrowed ? " · out of key" : "") } ?? ""
        } else {
            text = Self.inertName(place.kind)
            detail = place.rank == 1 ? "1ST" : "2ND"
        }
        return CompassChip(text: text, detail: detail, isOn: isOn, isEnabled: degree == nil || step != nil,
                           isBorrowed: step?.fit == .borrowed,
                           onTap: { state.compassPressed(place); state.compassLifted(place) })
            .accessibilityLabel("\(Self.inertName(place.kind)), \(place.rank == 1 ? "first" : "second") choice")
            .accessibilityValue(degree == nil ? "" : text)
    }

    private func middleButton(degree: Degree?) -> some View {
        let keeps = state.keepsCompassColor
        let plain = degree.map { chordLabel(key: state.playedKey, spec: ChordSpec(degree: $0, color: .base)) }
        return CompassChip(text: keeps ? "clear" : plain ?? "plain", detail: keeps ? "BACK TO PLAIN" : "AS IT IS",
                           isOn: false, isEnabled: true, isBorrowed: false, isMiddle: true,
                           onTap: { state.compassCleared() })
            .accessibilityLabel(keeps ? "Back to the plain chord" : "The plain chord")
    }

    /// A step's chord, "G 7", with its fit marked.
    private func name(of step: ColorStep, on degree: Degree) -> String {
        let name = chordLabel(key: state.playedKey, spec: ChordSpec(degree: degree, color: .tones(step.tones)))
        return name + (step.fit == .borrowed ? "*" : step.fit == .avoid ? "◦" : "")
    }

    private static func inertName(_ kind: ColorStepKind) -> String {
        switch kind {
        case .add:      return "+ tone"
        case .raise:    return "raise ▶"
        case .lower:    return "◀ lower"
        case .takeAway: return "− tone"
        }
    }
}

/// One of the compass's places, as drawn. Its finger is read by the
/// compass as a whole, so it can slide onto another; `onTap` is for
/// accessibility.
private struct CompassChip: View {
    let text: String
    let detail: String
    let isOn: Bool
    let isEnabled: Bool
    let isBorrowed: Bool
    var isMiddle = false
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isOn ? Color.black : Color(white: isEnabled ? 0.95 : 0.3))
            Text(detail)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isOn ? Color.black.opacity(0.7) : Color(white: 0.55))
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isOn ? Color.orange : Color(white: isMiddle ? 0.17 : 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isOn ? Color.orange : Color(white: isBorrowed ? 0.5 : 0.25),
                    style: StrokeStyle(lineWidth: 1, dash: isBorrowed ? [3, 2] : [])))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }
}
