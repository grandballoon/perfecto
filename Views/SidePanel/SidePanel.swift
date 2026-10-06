import SwiftUI

/// The menu: a panel that slides in over the leading edge of the screen and
/// holds every setting, a page each for Key, Sound, Effects and Setup. It covers only its own width and takes only the
/// touches that land on it, so the chord keys still showing beside it play as
/// usual while a setting is being tried out.
///
/// Place it in a full-screen layer; it draws nothing while closed.
struct SidePanel: View {
    @Environment(SidePanelState.self) private var panel

    /// The width of the screen the panel slides over.
    let containerWidth: CGFloat

    private static let background = Color(white: 0.07)
    private static let padding: CGFloat = SidePanelLayout.buttonLeading

    var body: some View {
        ZStack(alignment: .leading) {
            if let page = panel.page {
                content(page)
                    .frame(width: SidePanelLayout.width(in: containerWidth))
                    .frame(maxHeight: .infinity)
                    .background(backdrop)
                    .environment(\.colorScheme, .dark)
                    .transition(.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.22), value: panel.isOpen)
    }

    private func content(_ page: SidePanelPage) -> some View {
        VStack(spacing: 0) {
            header(page)
                .padding(.horizontal, Self.padding)
                .padding(.top, SidePanelLayout.buttonTop)
                .padding(.bottom, 12)
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 1)
            ScrollView {
                Group {
                    switch page {
                    case .key:     KeyPanel()
                    case .sound:   SoundPanel()
                    case .effects: EffectsPanel()
                    case .setup:   SetupPanel()
                    }
                }
                .padding(Self.padding)
                // Clears the home indicator: the performance screen runs to
                // the bottom edge.
                .padding(.bottom, 40)
            }
        }
    }

    /// Opaque, so nothing shows or plays through the panel, and run out to
    /// the screen edges past the safe area.
    private var backdrop: some View {
        Self.background
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(white: 0.25))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 12, x: 4)
            .ignoresSafeArea()
    }

    // MARK: – Header

    /// The heading sits beside the menu button, which stays on top of the
    /// panel in the corner; the tabs run under both.
    private func header(_ page: SidePanelPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(page.name)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(height: SidePanelLayout.buttonSize)
                .padding(.leading, SidePanelLayout.buttonSize + 12)
            tabs(page)
        }
    }

    private func tabs(_ current: SidePanelPage) -> some View {
        HStack(spacing: 3) {
            ForEach(SidePanelPage.allCases) { page in
                Button { panel.show(page) } label: {
                    Text(page.tabLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(page == current ? Color.black : Color(white: 0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(page == current ? Color.orange : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 1))
        )
    }
}

/// The menu button: opens the side panel where it was left, and closes it.
/// It is the one way into the menu.
struct SidePanelButton: View {
    @Environment(SidePanelState.self) private var panel

    var body: some View {
        Button { panel.toggle() } label: {
            Image(systemName: panel.isOpen ? "xmark" : "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(white: panel.isOpen ? 0.8 : 0.6))
                .frame(width: SidePanelLayout.buttonSize, height: SidePanelLayout.buttonSize)
                .background(
                    Circle()
                        .fill(Color(white: 0.13))
                        .overlay(Circle().stroke(Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.isOpen ? "Close menu" : "Menu")
    }
}

/// A choice among several in the panel: lit while it is the selected one.
struct SidePanelChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.orange : Color(white: 0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

/// The small spaced-out caption above each group of controls in the panel.
struct SidePanelSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }
}
