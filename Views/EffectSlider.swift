import SwiftUI

/// The effect slider, wired to the live effects: a lane for each effect
/// that is on, running along `axis`. A finger's place along a lane plays
/// that effect's played control (`SlidePlayed`), as a slide on a chord key
/// would, but one effect at a time and over the lane's whole length.
/// Lifting returns the effect to what the keys play.
///
/// It is drawn like the chord-color surfaces whose place it takes
/// (`PlaySurfaceView`). With no effect on there is nothing to play, so it
/// says so and opens the menu's Effects page.
struct EffectSliderView: View {

    let axis: Axis

    @Environment(PerformanceState.self) private var state
    @Environment(SidePanelState.self) private var sidePanel

    private let lineWidth: CGFloat = 1

    var body: some View {
        let effects = state.effects
        let lanes = effects.slidable
        Group {
            if lanes.isEmpty {
                noEffects
            } else {
                // Lanes lie across the axis they are played along.
                let stack = axis == .horizontal
                    ? AnyLayout(VStackLayout(spacing: lineWidth))
                    : AnyLayout(HStackLayout(spacing: lineWidth))
                stack {
                    ForEach(lanes, id: \.self) { effect in
                        let place = effects.place(of: effect)
                        EffectSliderLane(
                            axis: axis,
                            name: axis == .horizontal ? effect.label.uppercased() : effect.abbreviation,
                            control: effect.playedControl,
                            reading: effect.reading(at: place),
                            place: place,
                            isHeld: effects.slider[effect] != nil,
                            onChange: { effects.sliderMoved(effect, to: $0) },
                            onEnd: { effects.sliderMoved(effect, to: nil) }
                        )
                    }
                }
                .background(Color(white: 0.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
    }

    private var noEffects: some View {
        Button { sidePanel.show(.effects) } label: {
            VStack(spacing: 2) {
                Text("NO EFFECTS ON")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
                Text("Tap to choose")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One lane of the effect slider: a control played by where a finger is
/// along it, from 0 at the leading end (the bottom, when it stands upright)
/// to 1 at the other. It is filled as far as `place`.
///
/// The lane keeps no state. The caller says where the control is and whether
/// a finger holds it, and is told each place the finger moves to and when it
/// lifts, also if the lane goes away under the finger.
struct EffectSliderLane: View {

    let axis: Axis
    let name: String
    /// What of the effect the lane plays; shown where there is room.
    let control: String
    /// The value at `place`, as the user reads it.
    let reading: String
    /// Where the control is, 0...1.
    let place: Float
    let isHeld: Bool
    let onChange: (Float) -> Void
    let onEnd: () -> Void

    /// The mark at the end of the fill, which also shows a control at 0.
    private let markWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                Color(white: 0.08)
                fill(in: geo.size)
                labels
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { onChange(self.place(at: $0.location, in: geo.size)) }
                    .onEnded { _ in onEnd() }
            )
        }
        .onDisappear(perform: onEnd)
    }

    private func fill(in size: CGSize) -> some View {
        let length = (axis == .horizontal ? size.width : size.height) * CGFloat(place)
        return Color.orange.opacity(isHeld ? 0.6 : 0.25)
            .overlay(alignment: axis == .horizontal ? .trailing : .top) {
                Color.orange.frame(width: axis == .horizontal ? markWidth : nil,
                                   height: axis == .vertical ? markWidth : nil)
            }
            .frame(width: axis == .horizontal ? max(length, markWidth) : nil,
                   height: axis == .vertical ? max(length, markWidth) : nil)
    }

    @ViewBuilder
    private var labels: some View {
        let nameText = Text(name)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(isHeld ? .white : Color(white: 0.6))
        let readingText = Text(reading)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(isHeld ? .white : Color(white: 0.6))
        Group {
            if axis == .horizontal {
                HStack(spacing: 6) {
                    nameText
                    Text(control)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(isHeld ? Color.white.opacity(0.7) : Color(white: 0.4))
                    Spacer(minLength: 4)
                    readingText
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 0) {
                    readingText
                    Spacer(minLength: 4)
                    nameText
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func place(at point: CGPoint, in size: CGSize) -> Float {
        let share = axis == .horizontal ? point.x / size.width : 1 - point.y / size.height
        return Float(max(0, min(1, share)))
    }
}
