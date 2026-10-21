import SwiftUI
import UIKit

/// A cell of a pad field's pad: a column, counted from the leading edge,
/// and a row, counted from the bottom.
struct PadFieldCell: Equatable {
    var column: Int
    var row: Int
}

/// Where a pad's cells are: a column to each place along and a row to each
/// place across with the highest at the top, inside room for names along
/// the top and down the leading edge. A pad field's finger is read by the
/// same cells (`PadSwipe`), so the place lit moves as far as the finger
/// does.
struct PadSpan {
    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>
    /// One place's cell, which is also a step of a finger's travel.
    let cell: CGSize
    /// The room over the cells and before them, for their names.
    let top: CGFloat
    let leading: CGFloat

    /// The room round the cells at the trailing edge and the bottom.
    static let edge: CGFloat = 6
    /// How near the screen's edge a pad may come.
    static let margin: CGFloat = 8

    var size: CGSize {
        CGSize(width: leading + CGFloat(columns.count) * cell.width + Self.edge,
               height: top + CGFloat(rows.count) * cell.height + Self.edge)
    }

    /// The frame of `place`, in the pad's own space. A place past the span
    /// has the nearest cell.
    func frame(of place: PadFieldCell) -> CGRect {
        let column = place.column.clamped(to: columns) - columns.lowerBound
        let row = rows.upperBound - place.row.clamped(to: rows)
        return CGRect(origin: CGPoint(x: leading + CGFloat(column) * cell.width,
                                      y: top + CGFloat(row) * cell.height),
                      size: cell)
    }

    /// Where the pad goes on a screen of `screen`, for a field at `field`
    /// whose place was `pressed` when the finger came down: with that
    /// place's cell on the middle of the field, so the finger is on the
    /// place it moves, as near as the screen's edges let it be.
    func frame(pressedAt pressed: PadFieldCell, on field: CGRect, in screen: CGSize) -> CGRect {
        let cell = frame(of: pressed)
        let x = field.midX - cell.midX
        let y = field.midY - cell.midY
        return CGRect(
            origin: CGPoint(x: max(Self.margin, min(x, screen.width - size.width - Self.margin)),
                            y: max(Self.margin, min(y, screen.height - size.height - Self.margin))),
            size: size)
    }
}

/// A setting of two parts laid out as a pad: which cell each of its values
/// has, and the value of each cell.
protocol PadMap {
    associatedtype Value: Equatable
    static var span: PadSpan { get }
    static func cell(of value: Value) -> PadFieldCell
    static func value(at cell: PadFieldCell) -> Value
}

/// A finger's travel from where it came down on a pad field, read as a
/// value: along through the pad's columns and across through its rows, up
/// being higher. A step is a cell of the pad (`PadSpan`), so the place lit
/// there moves as the finger does, and each way is read as any swipe is
/// (`SwipeSteps`): a finger that only goes up or down changes only the row.
struct PadSwipe<Map: PadMap>: Equatable {
    private var along: SwipeSteps
    private var across: SwipeSteps

    init(from value: Map.Value) {
        let cell = Map.cell(of: value)
        along = SwipeSteps(from: cell.column, in: Map.span.columns, step: Map.span.cell.width)
        across = SwipeSteps(from: cell.row, in: Map.span.rows, step: Map.span.cell.height)
    }

    var value: Map.Value {
        Map.value(at: PadFieldCell(column: along.value, row: across.value))
    }

    /// The finger is `translation` from where it came down.
    mutating func moved(to translation: CGSize) {
        along.moved(to: translation.width)
        across.moved(to: -translation.height)
    }
}

/// A setting of two parts changed by one finger: a chit that shows it and
/// is changed by pressing it. While a finger is on it, every value there is
/// is laid out around it (`pad`, drawn by the screen with `value` lit), at
/// the place the value has now, and the finger moves that place
/// (`PadSwipe`). The field is one element to accessibility, and its caller
/// says what it is and how it is stepped.
///
/// `onBegin` is called when a finger comes down, `set` with each value the
/// finger reaches, and `onEnd` when the finger has gone, however it went.
struct PadField<Map: PadMap, Pad: View>: View {
    let name: String
    let value: Map.Value
    let text: String
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    @ViewBuilder let pad: (Map.Value) -> Pad
    let set: (Map.Value) -> Void

    @State private var swipe: PadSwipe<Map>?
    /// The value when the finger came down, which the pad is laid out
    /// around for as long as the finger is on it.
    @State private var pressed: Map.Value?
    /// False once the finger is gone, whether it lifted or was taken away.
    @GestureState private var isDown = false
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(isActive ? Color.orange : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.orange : Color(white: 0.25), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isDown) { _, isDown, _ in isDown = true }
                .onChanged { drag in
                    if swipe == nil {
                        haptic.prepare()
                        pressed = value
                        onBegin()
                    }
                    var swipe = swipe ?? PadSwipe<Map>(from: value)
                    swipe.moved(to: drag.translation)
                    self.swipe = swipe
                    let new = swipe.value
                    guard new != value else { return }
                    set(new)
                    haptic.impactOccurred()
                }
        )
        .onChange(of: isDown) {
            guard !isDown else { return }
            (swipe, pressed) = (nil, nil)
            onEnd()
        }
        .anchorPreference(key: PadFieldKey.self, value: .bounds) { bounds in
            pressed.map {
                PadFieldPlace(span: Map.span, pressed: Map.cell(of: $0), field: bounds, pad: AnyView(pad(value)))
            }
        }
        .animation(.snappy(duration: 0.18), value: text)
        .accessibilityElement()
    }

    /// A finger is on the field.
    private var isActive: Bool { pressed != nil }
}

/// A pad field with a finger on it: what the screen needs to draw its pad.
struct PadFieldPlace {
    let span: PadSpan
    /// The cell of the value when the finger came down.
    let pressed: PadFieldCell
    /// Where the field is.
    let field: Anchor<CGRect>
    /// The pad's cells and names, with the value now lit.
    let pad: AnyView
}

struct PadFieldKey: PreferenceKey {
    static var defaultValue: PadFieldPlace? { nil }

    static func reduce(value: inout PadFieldPlace?, nextValue: () -> PadFieldPlace?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Draws the pad of whichever pad field inside this view has a finger
    /// on it (`PadField`). It goes on the screen as a whole, so the pad
    /// lies over everything and no neighbour or clipped edge hides it. The
    /// pad takes no touches: the finger is still the field's.
    func showingFieldPad() -> some View {
        overlayPreferenceValue(PadFieldKey.self) { place in
            GeometryReader { geo in
                if let place {
                    let frame = place.span.frame(pressedAt: place.pressed, on: geo[place.field], in: geo.size)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.4), lineWidth: 1))
                        place.pad
                    }
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: place != nil)
            .allowsHitTesting(false)
        }
    }
}
