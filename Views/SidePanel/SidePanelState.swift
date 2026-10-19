import CoreGraphics
import Observation

/// The menu's pages, in the order its tabs show them.
enum SidePanelPage: String, CaseIterable, Identifiable {
    case key, sound, effects, setup

    var id: String { rawValue }

    /// The page's tab.
    var tabLabel: String {
        switch self {
        case .key:     return "KEY"
        case .sound:   return "SOUND"
        case .effects: return "FX"
        case .setup:   return "SETUP"
        }
    }

    /// The page's heading.
    var name: String {
        switch self {
        case .key:     return "Key"
        case .sound:   return "Sound"
        case .effects: return "Effects"
        case .setup:   return "Setup"
        }
    }
}

/// Whose effects the menu's Effects page sets: each loop and each pad has
/// its own, apart from the keys'.
enum EffectsTarget: Hashable {
    case keys
    case loop(Layer.ID)
    /// The pad being edited on the pads' screen.
    case pad
}

/// Whether the menu (the side panel) is open, and at which page.
/// `PerformanceView` owns one and draws the panel and its button.
@Observable
@MainActor
final class SidePanelState {
    private(set) var page: SidePanelPage?

    /// Where the menu opens: the page it last showed.
    private var lastPage: SidePanelPage = .key

    /// Whose effects the Effects page was last asked for. The page shows
    /// the keys' once that loop or pad is no longer there to edit.
    var effectsTarget = EffectsTarget.keys

    var isOpen: Bool { page != nil }

    func show(_ page: SidePanelPage) {
        self.page = page
        lastPage = page
    }

    /// Opens the Effects page at the effects of `target`.
    func showEffects(of target: EffectsTarget) {
        effectsTarget = target
        show(.effects)
    }

    /// The menu button's tap: opens the menu where it was left, or closes it.
    func toggle() {
        page = isOpen ? nil : lastPage
    }
}

/// How much of the screen the side panel takes, and where its button sits.
/// The panel never covers the screen: what stays visible beside it stays
/// playable, so a change made in the panel can be heard at once.
enum SidePanelLayout {
    static let maxWidth: CGFloat = 320
    /// The widest the panel gets as a share of the screen. In landscape the
    /// panel stays within the leading half, which leaves the chord keys clear.
    static let maxShare: CGFloat = 0.62

    /// The menu button, in the screen's top leading corner. It stays put, on
    /// top of the panel, so the same spot opens and closes the menu.
    static let buttonSize: CGFloat = 38
    static let buttonTop: CGFloat = 12
    static let buttonLeading: CGFloat = 16

    static func width(in containerWidth: CGFloat) -> CGFloat {
        min(maxWidth, (containerWidth * maxShare).rounded())
    }
}
