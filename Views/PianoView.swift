import SwiftUI

extension PianoSource {
    /// The color the source's notes are lit in.
    var color: Color {
        switch self {
        case .keys:    return .orange
        case .layers:  return Color(red: 0.35, green: 0.7, blue: 1)
        case .tonnetz: return Color(red: 0.8, green: 0.5, blue: 1)
        case .pads:    return Color(red: 1, green: 0.45, blue: 0.6)
        case .trautonium: return Color(red: 0.3, green: 0.85, blue: 0.8)
        case .tree:       return Color(red: 0.95, green: 0.85, blue: 0.35)
        case .lab:        return Color(red: 0.95, green: 0.55, blue: 0.35)
        }
    }
}

/// The piano (`PianoState`): the white keys of its span across the width
/// it is given, each key lit in the colors of the sources sounding its
/// note. A key that several sources are sounding is divided between their
/// colors along its length, and a lit key out of view is marked in its
/// colors at the end it lies beyond.
///
/// No touch plays it: a pinch and a drag change what is in view
/// (`PianoTouches`), and its corner button or a double tap gives it the
/// whole screen or puts it back.
struct PianoView: View {
    @Environment(PerformanceState.self) private var state

    /// Whether this is the piano that has the whole screen.
    var isExpanded = false

    /// The narrowest white key that has room for its octave's name.
    private static let namedKeyWidth: CGFloat = 14
    private static let edgeMarkWidth: CGFloat = 3
    /// How much closer each step of an assistive technology's adjusting
    /// brings the piano.
    private static let adjustingStep = 1.5

    var body: some View {
        let piano = state.piano
        GeometryReader { geo in
            // The strip's keys are as long as it is high; the whole
            // screen's keep a piano's proportions.
            let place = isExpanded
                ? PianoKeys.standing(in: geo.size, above: geo.safeAreaInsets.bottom, span: piano.span)
                : CGRect(origin: .zero, size: geo.size)
            let keys = PianoKeys(size: place.size, span: piano.span)
            let lights = piano.lights
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // The black keys lie over the white ones.
                    ForEach((PianoKeys.whites + PianoKeys.blacks).filter(keys.shows), id: \.self) { note in
                        key(note, in: keys, lit: lights[note] ?? [])
                    }
                    edgeMarks(lights, in: keys)
                }
                .frame(width: place.width, height: place.height, alignment: .topLeading)
                .offset(y: place.minY)
                PianoTouches(
                    onZoom: { scale, x in
                        let at = Double(x / geo.size.width)
                        piano.span = piano.span.moved(by: Double(scale), from: at, to: at)
                    },
                    onDrag: { dx in
                        piano.span = piano.span.moved(from: 0, to: Double(dx / geo.size.width))
                    },
                    onDoubleTap: toggleExpanded)
                expandButton(insets: geo.safeAreaInsets)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .background(Color.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano")
        .accessibilityAction(named: isExpanded ? "Shrink" : "Expand", toggleExpanded)
        .accessibilityAdjustableAction { direction in
            let scale = direction == .increment ? Self.adjustingStep : 1 / Self.adjustingStep
            piano.span = piano.span.moved(by: scale, from: 0.5, to: 0.5)
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeOut(duration: 0.25)) { state.piano.isExpanded.toggle() }
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
                    // Larger as the keys are, up to a size that still reads as a label.
                    .font(.system(size: (keys.whiteWidth * 0.3).clamped(to: 8...14),
                                  weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(lit.isEmpty ? 0.45 : 0.8))
                    .fixedSize()
                    .padding(.bottom, 4)
            }
        }
        .border(Color.black, width: 0.5)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    /// A mark at each end for the lit keys beyond it, in their sources'
    /// colors, so a zoomed piano still says that something is sounding.
    private func edgeMarks(_ lights: [Int: [PianoSource]], in keys: PianoKeys) -> some View {
        func sources(where isBeyond: (CGRect) -> Bool) -> [PianoSource] {
            let beyond = Set(lights.filter { isBeyond(keys.frame(of: $0.key)) }.values.joined())
            return PianoSource.allCases.filter(beyond.contains)
        }
        return HStack(spacing: 0) {
            edgeMark(sources { $0.maxX <= 0 })
            Spacer(minLength: 0)
            edgeMark(sources { $0.minX >= keys.size.width })
        }
        .frame(width: keys.size.width, height: keys.size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeMark(_ sources: [PianoSource]) -> some View {
        if !sources.isEmpty {
            VStack(spacing: 0) {
                ForEach(sources, id: \.self) { $0.color }
            }
            .frame(width: Self.edgeMarkWidth)
        }
    }

    private func expandButton(insets: EdgeInsets) -> some View {
        Button(action: toggleExpanded) {
            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left"
                                         : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4 + insets.top)
        .padding(.trailing, 4 + insets.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
