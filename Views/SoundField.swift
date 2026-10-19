import SwiftUI

/// The sound field: the keys' sound beside the note display, changed by
/// swiping along it (`SwipeField`) through the sounds in the order the Sound
/// page lists them. It is the Sound page's choice, within reach while
/// playing, and like it is heard on the next chord played. Its list has
/// the sounds under their categories, as the Sound page has them.
struct SoundField: View {
    @Environment(PerformanceState.self) private var state

    static let width: CGFloat = 124
    private static let sounds = SynthPreset.Category.allCases.flatMap(\.presets)
    private static let sections = soundSections()

    var body: some View {
        SwipeField(name: "SOUND", value: Self.sounds.firstIndex(of: state.synthPreset) ?? 0,
                   range: 0...(Self.sounds.count - 1), textSize: 12,
                   sections: Self.sections,
                   label: { Self.sounds[$0].name }) {
            state.setSynthPreset(Self.sounds[$0])
        }
        .frame(width: Self.width)
    }

    /// Each category that has sounds, over its run of `sounds`.
    private static func soundSections() -> [SwipeSection] {
        var first = 0
        return SynthPreset.Category.allCases.compactMap { category in
            let count = category.presets.count
            guard count > 0 else { return nil }
            defer { first += count }
            return SwipeSection(title: category.displayName, values: first...(first + count - 1))
        }
    }
}
