import SwiftUI
import UIKit

/// A swipe along a field, read as steps through a range of values: every
/// `step` of travel to the right is the next value up, and to the left the
/// next one down, so one long swipe crosses several. Travel past the last
/// value is not owed back: a finger that turns round there moves the value
/// after one step. A range that `wraps` has no last value: the step past
/// one end is the other end.
struct SwipeSteps: Equatable {
    /// How far a finger travels for each value, unless a swipe has a step
    /// of its own.
    static let step: CGFloat = 24

    private(set) var value: Int
    private let range: ClosedRange<Int>
    private let wraps: Bool
    /// How far this swipe's finger travels for each value.
    private let step: CGFloat
    /// Where along the swipe the value was reached.
    private var anchor: CGFloat = 0

    init(from value: Int, in range: ClosedRange<Int>, wraps: Bool = false, step: CGFloat = SwipeSteps.step) {
        self.value = value
        self.range = range
        self.wraps = wraps
        self.step = step
    }

    /// The value `steps` on from `value`: round the range if it wraps, and
    /// nil past its end if it does not.
    static func value(_ steps: Int, from value: Int, in range: ClosedRange<Int>, wraps: Bool) -> Int? {
        let wanted = value + steps
        if range.contains(wanted) { return wanted }
        guard wraps else { return nil }
        let place = (wanted - range.lowerBound) % range.count
        return range.lowerBound + (place < 0 ? place + range.count : place)
    }

    /// The finger is `translation` from where it came down.
    mutating func moved(to translation: CGFloat) {
        let steps = Int(((translation - anchor) / step).rounded(.towardZero))
        guard steps != 0 else { return }
        if let reached = Self.value(steps, from: value, in: range, wraps: wraps) {
            value = reached
            anchor += CGFloat(steps) * step
        } else {
            value = steps > 0 ? range.upperBound : range.lowerBound
            anchor = translation
        }
    }
}

/// A run of a swipe field's values under a heading, in its list.
struct SwipeSection: Equatable {
    let title: String
    let values: ClosedRange<Int>
}

/// A setting of the play screen that is changed by swiping along it
/// (`SwipeSteps`): its name over what it is set to, between two arrows that
/// are dim where there is nothing further that way. The setting is a place
/// in a range, and `label` is what is shown of each place. A range that
/// `wraps` goes round, so there is always something further.
///
/// A tap on the field, or a finger that rests on it without swiping, opens
/// every value as a list (`SwipeList`), to choose one by a tap; what a
/// finger that has rested does afterwards is not a swipe. The list is in
/// `sections` if the field has them, which must cover the range in order.
///
/// `onEnd` is called when a change is over: the finger of a swipe has
/// lifted, or the list has closed.
struct SwipeField: View {
    let name: String
    let value: Int
    let range: ClosedRange<Int>
    var textSize: CGFloat = 15
    var wraps = false
    var sections: [SwipeSection] = []
    var onEnd: () -> Void = {}
    let label: (Int) -> String
    let set: (Int) -> Void

    /// How long a finger rests before it is a hold, and how far it may
    /// stray and still hold or tap.
    private static let holdTime = 0.4
    private static let holdReach = SwipeSteps.step / 3

    @State private var swipe: SwipeSteps?
    /// The finger on the field has held it, so it no longer swipes.
    @State private var held = false
    /// The finger on the field has moved too far to be a tap.
    @State private var strayed = false
    @State private var showsList = false
    /// False once the finger is gone, however it went: the list may take
    /// the touch away without ending it.
    @GestureState private var isDown = false
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    private var text: String { label(value) }

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", leads: next(-1) != nil)
            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
                Text(text)
                    .font(.system(size: textSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(isActive ? Color.orange : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            arrow("chevron.right", leads: next(1) != nil)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
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
                    guard !held else { return }
                    if max(abs(drag.translation.width), abs(drag.translation.height)) > Self.holdReach {
                        strayed = true
                    }
                    if swipe == nil { haptic.prepare() }
                    var swipe = swipe ?? SwipeSteps(from: value, in: range, wraps: wraps)
                    swipe.moved(to: drag.translation.width)
                    self.swipe = swipe
                    change(to: swipe.value)
                }
                .onEnded { _ in
                    swipe = nil
                    if !held, !strayed { showsList = true }
                    // A change the list is open for is over when it closes.
                    if !showsList { onEnd() }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.holdTime, maximumDistance: Self.holdReach)
                .onEnded { _ in
                    held = true
                    swipe = nil
                    haptic.impactOccurred()
                    showsList = true
                }
        )
        .onChange(of: isDown) {
            if !isDown { (held, strayed) = (false, false) }
        }
        .onChange(of: showsList) {
            if !showsList { onEnd() }
        }
        .popover(isPresented: $showsList) {
            SwipeList(chosen: value, sections: sections.isEmpty ? [SwipeSection(title: "", values: range)] : sections,
                      label: label) {
                change(to: $0)
                showsList = false
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Color(white: 0.1))
        }
        .animation(.snappy(duration: 0.18), value: value)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(to: next(1) ?? value)
            case .decrement: change(to: next(-1) ?? value)
            @unknown default: break
            }
            onEnd()
        }
        .accessibilityAction(named: "Show all") { showsList = true }
    }

    /// A finger is swiping the field, or its list is open.
    private var isActive: Bool { swipe != nil || showsList }

    /// The value a step up (1) or down (-1), if there is one.
    private func next(_ step: Int) -> Int? {
        SwipeSteps.value(step, from: value, in: range, wraps: wraps)
    }

    /// An arrow at one end of the field, dim where there is nothing that way.
    private func arrow(_ name: String, leads: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(leads ? Color.orange : Color(white: 0.25))
    }

    private func change(to new: Int) {
        guard new != value else { return }
        set(new)
        haptic.impactOccurred()
    }
}

/// Every value of a swipe field in one column, under its sections'
/// headings, opened at the one chosen. A tap chooses.
private struct SwipeList: View {
    let chosen: Int
    let sections: [SwipeSection]
    let label: (Int) -> String
    let choose: (Int) -> Void

    private static let rowHeight: CGFloat = 40
    private static let headingHeight: CGFloat = 28
    private static let bottom: CGFloat = 8
    private static let maxHeight: CGFloat = 460

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.values.lowerBound) { section in
                        if !section.title.isEmpty {
                            Text(section.title.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(white: 0.5))
                                .padding(.horizontal, 14)
                                .padding(.bottom, 4)
                                .frame(height: Self.headingHeight, alignment: .bottomLeading)
                        }
                        ForEach(Array(section.values), id: \.self) { value in
                            row(value).id(value)
                        }
                    }
                }
                .padding(.bottom, Self.bottom)
            }
            .onAppear { scroll.scrollTo(chosen, anchor: .center) }
        }
        .frame(idealWidth: 210, idealHeight: min(height, Self.maxHeight))
    }

    /// The height of every row and heading: the list is no taller.
    private var height: CGFloat {
        sections.reduce(Self.bottom) {
            $0 + CGFloat($1.values.count) * Self.rowHeight + ($1.title.isEmpty ? 0 : Self.headingHeight)
        }
    }

    private func row(_ value: Int) -> some View {
        let isChosen = value == chosen
        return Button { choose(value) } label: {
            HStack(spacing: 8) {
                Text(label(value))
                    .font(.system(size: 15, weight: isChosen ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(isChosen ? Color.orange : Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
