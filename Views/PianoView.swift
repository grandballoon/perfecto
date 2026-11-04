import SwiftUI

extension PianoSource {
    /// The color the source's notes are lit in.
    var color: Color {
        switch self {
        case .keys:    return .orange
        case .layers:  return Color(red: 0.35, green: 0.7, blue: 1)
        }
    }
}

extension Hand {
    /// The color a hand's keys are lit in by score practice.
    var color: Color {
        switch self {
        case .right: return Color(red: 0.35, green: 0.85, blue: 0.5)
        case .left:  return Color(red: 0.78, green: 0.52, blue: 1)
        }
    }
}

/// The piano (`PianoState`): the white keys of its span across the frame
/// it is given, each key lit in the colors of the sources sounding its
/// note. A key that several sources are sounding is divided between their
/// colors along its length, and a lit key out of view is marked in its
/// colors at the end it lies beyond.
///
/// Score practice lights keys too (`practice`): a key a hand is playing in
/// the hand's color, flashing white as it is struck so a key struck again
/// is seen to be, and the hand's next keys with a dot of its color.
///
/// No touch plays it: a pinch and a drag change what is in view
/// (`PianoTouches`), and its corner button or a double tap gives it the
/// whole screen or puts it back.
struct PianoView: View {
    @Environment(PerformanceState.self) private var state

    /// Whether this is the piano that has the whole screen, which has its
    /// own button to put it back.
    var isExpanded = false
    /// The keys lit by score practice.
    var practice: [Int: [KeyLight]] = [:]

    /// The narrowest white key that has room for its octave's name.
    private static let namedKeyWidth: CGFloat = 14
    private static let edgeMarkWidth: CGFloat = 3
    /// How much closer each step of an assistive technology's adjusting
    /// brings the piano.
    private static let adjustingStep = 1.5
    /// How long a struck key flashes.
    private static let strike = 0.15

    var body: some View {
        let piano = state.piano
        GeometryReader { geo in
            let keys = PianoKeys(size: geo.size, span: piano.span)
            let lights = piano.lights
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // The black keys lie over the white ones.
                    ForEach((PianoKeys.whites + PianoKeys.blacks).filter(keys.shows), id: \.self) { note in
                        key(note, in: keys, lit: lights[note] ?? [], practice: practice[note] ?? [])
                    }
                    edgeMarks(lights, in: keys)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                PianoTouches(
                    onZoom: { scale, x in
                        let at = Double(x / geo.size.width)
                        piano.span = piano.span.moved(by: Double(scale), from: at, to: at)
                    },
                    onDrag: { dx in
                        piano.span = piano.span.moved(from: 0, to: Double(dx / geo.size.width))
                    },
                    onDoubleTap: toggleExpanded)
                if !isExpanded { expandButton(insets: geo.safeAreaInsets) }
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

    private func key(_ note: Int, in keys: PianoKeys, lit: [PianoSource], practice: [KeyLight]) -> some View {
        let isBlack = PianoKeys.isBlack(note)
        let frame = keys.frame(of: note)
        let sounding = practice.compactMap { light -> (hand: Hand, since: Double)? in
            if case let .sounding(since) = light.kind { return (light.hand, since) }
            return nil
        }
        let next = practice.filter { $0.kind == .next }.map(\.hand)
        let colors = lit.map(\.color) + sounding.map(\.hand.color)
        let flash = sounding.map { max(0, 1 - $0.since / Self.strike) }.max() ?? 0
        return VStack(spacing: 0) {
            if colors.isEmpty {
                Color(white: isBlack ? 0.08 : 0.92)
            } else {
                ForEach(colors.indices, id: \.self) { colors[$0] }
            }
        }
        // A lit black key is a shade darker than the white keys lit beside it.
        .overlay(Color.black.opacity(isBlack && !colors.isEmpty ? 0.25 : 0))
        .overlay(Color.white.opacity(0.55 * flash))
        .overlay(alignment: .bottom) {
            VStack(spacing: 3) {
                ForEach(next, id: \.self) { hand in
                    Circle()
                        .fill(hand.color)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                        .frame(width: frame.width * 0.5, height: frame.width * 0.5)
                }
                if keys.whiteWidth >= Self.namedKeyWidth, let name = PianoKeys.octaveName(of: note) {
                    Text(name)
                        // Larger as the keys are, up to a size that still reads as a label.
                        .font(.system(size: (keys.whiteWidth * 0.3).clamped(to: 8...14),
                                      weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(colors.isEmpty ? 0.45 : 0.8))
                        .fixedSize()
                }
            }
            .padding(.bottom, 4)
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
