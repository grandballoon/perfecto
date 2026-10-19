import SwiftUI

/// The chord keys, drawn in one of their arrangements
/// (`ChordKeyArrangement`): the seven scale degrees, or the octave's twelve
/// roots. Visual only: each key is marked with `chordKey(_:)` and the
/// surface around it owns the touches, so the same keys are played in Play
/// mode (`ChordKeySurface`) and chosen from in the Sequencer
/// (`DegreeSelector`).
struct ChordKeysView: View {
    let arrangement: ChordKeyArrangement
    /// The key the keys are in, which decides each degree's numeral (e.g.
    /// "ii" vs "ii°") and each root's chord.
    let key: Key
    /// The keys drawn as down. A key is down with any that plays its chord,
    /// so a degree lights the octave's key for its root.
    let lit: [ChordKey]
    /// Whether the octave's keys for the notes outside the key are left
    /// out: drawn, but not keys. A chord chosen as a degree of its key has
    /// no use for them.
    var degreesOnly = false

    private static let color = Color.orange

    var body: some View {
        switch arrangement {
        case .grid:   grid
        case .circle: circle
        case .row:    row
        case .octave: octave
        }
    }

    private func isLit(_ chordKey: ChordKey) -> Bool {
        let chord = chordKey.chord(in: key)
        return lit.contains { $0.chord(in: key) == chord }
    }

    // MARK: – Grid: the staggered Nashville grid, four keys over three

    private var grid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([Degree.I, .ii, .iii, .IV]) { barKey($0, pressedScale: 0.95) }
            }
            HStack(spacing: 10) {
                ForEach([Degree.V, .vi, .viiDim]) { barKey($0, pressedScale: 0.95) }
                // The fourth place, so the rows' keys line up.
                Color.clear
            }
        }
    }

    // MARK: – Row: all seven in one line, as tall as there is room for

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(Degree.allCases) { barKey($0, pressedScale: 0.96) }
        }
    }

    private func barKey(_ degree: Degree, pressedScale: CGFloat) -> some View {
        let isPressed = isLit(.degree(degree))
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.color.opacity(isPressed ? 0.9 : 0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.color, lineWidth: 2))
            Text(degreeNumeral(key: key, degree: degree))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chordKey(.degree(degree))
        .scaleEffect(isPressed ? pressedScale : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }

    // MARK: – Circle: the root in the centre, the other six a ring around it

    /// The ring's keys, clockwise from the top, each a sixth of it:
    /// ii (upper-right), iii (right), IV (lower-right), V (lower-left),
    /// vi (left), vii° (upper-left).
    private static let ring: [Degree] = [.ii, .iii, .IV, .V, .vi, .viiDim]
    /// Where the ring begins, as a share of the way out from the centre.
    private static let ringInner: CGFloat = 0.58
    /// The space between two keys of the circle.
    private static let circleGap: CGFloat = 8

    private var circle: some View {
        GeometryReader { geo in
            let outer = min(geo.size.width, geo.size.height) / 2
            let inner = outer * Self.ringInner
            let sixth = 2 * CGFloat.pi / CGFloat(Self.ring.count)

            ZStack {
                ForEach(Array(Self.ring.enumerated()), id: \.element) { place, degree in
                    let from = sixth * CGFloat(place)
                    ringKey(degree, outline: .segment(angles: from...from + sixth, inner: Self.ringInner),
                            labelAt: CGPoint(x: geo.size.width / 2 + (inner + outer) / 2 * sin(from + sixth / 2),
                                             y: geo.size.height / 2 - (inner + outer) / 2 * cos(from + sixth / 2)),
                            fontSize: (outer - inner) * 0.3)
                }

                let center = max((inner - Self.circleGap) * 2, 0)
                circleKey(.I, size: center, fontSize: center * 0.2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Room for the outline, which is drawn half outside its key.
        .padding(1)
    }

    /// One key of the ring: the segment `outline` of the square it fills.
    private func ringKey(_ degree: Degree, outline: KeyOutline, labelAt: CGPoint, fontSize: CGFloat) -> some View {
        let isPressed = isLit(.degree(degree))
        let shape = RingSegmentShape(outline: outline, halfGap: Self.circleGap / 2)
        return ZStack {
            shape.fill(Self.color.opacity(isPressed ? 0.9 : 0.55))
                .overlay(shape.stroke(Self.color, lineWidth: 2))
            Text(degreeNumeral(key: key, degree: degree))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .position(labelAt)
        }
        // Towards the centre, so a pressed key draws in from the rim.
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
        .chordKey(.degree(degree), outline: outline)
    }

    private func circleKey(_ degree: Degree, size: CGFloat, fontSize: CGFloat) -> some View {
        let isPressed = isLit(.degree(degree))
        return ZStack {
            Circle()
                .fill(Self.color.opacity(isPressed ? 0.9 : 0.55))
                .overlay(Circle().stroke(Self.color, lineWidth: 2))
            Text(degreeNumeral(key: key, degree: degree))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
        .frame(width: size, height: size)
        .chordKey(.degree(degree), outline: .disc)
    }

    // MARK: – Octave: a piano's twelve keys from C to B, each the root of a chord

    private static let naturals: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
    /// The sharps, each with the place among the naturals of the one it
    /// lies after.
    private static let sharps: [(pitch: PitchClass, after: Int)] = [
        (.Cs, 0), (.Ds, 1), (.Fs, 3), (.Gs, 4), (.As, 5),
    ]
    private static let octaveGap: CGFloat = 4
    /// A black key's width and height, as shares of a white key's.
    private static let blackKey = CGSize(width: 0.62, height: 0.58)

    private var octave: some View {
        GeometryReader { geo in
            let pitch = (geo.size.width - Self.octaveGap * 6) / 7 + Self.octaveGap
            let white = CGSize(width: pitch - Self.octaveGap, height: geo.size.height)
            let black = CGSize(width: white.width * Self.blackKey.width,
                               height: white.height * Self.blackKey.height)
            ZStack {
                ForEach(Array(Self.naturals.enumerated()), id: \.element) { place, root in
                    octaveKey(root, size: white)
                        .position(x: pitch * CGFloat(place) + white.width / 2, y: white.height / 2)
                }
                // Over the white keys, each across the gap after its natural.
                ForEach(Self.sharps, id: \.pitch) { sharp in
                    octaveKey(sharp.pitch, size: black)
                        .position(x: pitch * CGFloat(sharp.after + 1) - Self.octaveGap / 2,
                                  y: black.height / 2)
                }
            }
        }
    }

    /// One key of the octave, named by the chord it plays. A note of the
    /// key is colored as the degrees' keys are and has its numeral; a note
    /// outside it is grey.
    private func octaveKey(_ root: PitchClass, size: CGSize) -> some View {
        let chordKey = ChordKey.root(root)
        let chord = chordKey.chord(in: key)
        let degree = key.degree(of: root)
        let isKey = degree != nil || !degreesOnly
        let isPressed = isLit(chordKey)
        let tint = degree != nil ? Self.color : Color(white: isKey ? 0.5 : 0.25)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 10,
                                           bottomTrailingRadius: 10, topTrailingRadius: 4)
        return ZStack(alignment: .bottom) {
            // Opaque, so a black key hides the white keys it lies over.
            shape.fill(Color.black)
            shape.fill(tint.opacity(isPressed ? 0.9 : degree != nil ? 0.6 : 0.35))
                .overlay(shape.stroke(tint, lineWidth: 2))
            VStack(spacing: 2) {
                Text(root.name + Self.triadSuffix(of: chord))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                if let degree {
                    Text(degreeNumeral(key: key, degree: degree))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isKey ? Color.white : Color(white: 0.4))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .padding(.bottom, 10)
        }
        .frame(width: size.width, height: size.height)
        .chordKey(isKey ? chordKey : nil)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }

    /// What is written after a root to say its triad: "m" for minor, "°"
    /// for diminished, nothing for major.
    private static func triadSuffix(of chord: KeyDegree) -> String {
        switch triadBase(key: chord.key, degree: chord.degree) {
        case .major: return ""
        case .minor: return "m"
        case .dim:   return "°"
        }
    }
}

/// A key of the ring as it is drawn: its segment (`KeyOutline.segment`, the
/// shape fingers are read against), less half the space between it and the
/// next at each side, with its corners rounded.
private struct RingSegmentShape: Shape {
    let outline: KeyOutline
    /// Half the space left between this segment and the one beside it.
    let halfGap: CGFloat
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        guard case .segment(let segment) = outline.shape(in: rect) else { return Path() }
        // Drawn smaller by the corners' radius and then grown by it all
        // round, which is what rounds them.
        let inner = segment.radii.lowerBound + cornerRadius
        let outer = segment.radii.upperBound - cornerRadius
        let side = halfGap + cornerRadius
        guard inner > side, outer > inner else { return Path() }
        // A side is a line beside the ring's radius, not along it, so the
        // space between two segments is as wide all the way out.
        let (innerTurn, outerTurn) = (asin(side / inner), asin(side / outer))
        let (from, to) = (segment.angles.lowerBound, segment.angles.upperBound)
        guard to - from > 2 * innerTurn else { return Path() }

        // An angle here is from the top, and a path's is from the right.
        func angle(_ fromTop: CGFloat) -> Angle { .radians(fromTop - .pi / 2) }
        var core = Path()
        core.addArc(center: segment.center, radius: outer, startAngle: angle(from + outerTurn),
                    endAngle: angle(to - outerTurn), clockwise: false)
        core.addArc(center: segment.center, radius: inner, startAngle: angle(to - innerTurn),
                    endAngle: angle(from + innerTurn), clockwise: true)
        core.closeSubpath()
        return core.union(core.strokedPath(StrokeStyle(lineWidth: cornerRadius * 2, lineJoin: .round)))
    }
}
