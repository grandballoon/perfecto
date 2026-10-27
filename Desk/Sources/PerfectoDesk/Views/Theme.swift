import AppKit
import DeskCore
import SwiftUI

/// The desk's colors, each with a light and a dark form. The chords are the
/// phone's orange and the line its layers' blue.
enum Theme {
    static let background = dynamic(light: NSColor(white: 0.95, alpha: 1), dark: NSColor(white: 0.07, alpha: 1))
    static let panel = dynamic(light: .white, dark: NSColor(white: 0.115, alpha: 1))
    static let raised = dynamic(light: NSColor(white: 0.9, alpha: 1), dark: NSColor(white: 0.17, alpha: 1))
    static let rule = dynamic(light: NSColor(white: 0.8, alpha: 1), dark: NSColor(white: 0.24, alpha: 1))
    static let text = dynamic(light: NSColor(white: 0.1, alpha: 1), dark: NSColor(white: 0.93, alpha: 1))
    static let secondary = dynamic(light: NSColor(white: 0.42, alpha: 1), dark: NSColor(white: 0.58, alpha: 1))
    static let faint = dynamic(light: NSColor(white: 0.62, alpha: 1), dark: NSColor(white: 0.38, alpha: 1))

    static let chord = Color(red: 1, green: 0.62, blue: 0.1)
    static let melody = Color(red: 0.35, green: 0.68, blue: 1)
    /// One step from what sounds: the gentle moves.
    static let near = Color(red: 0.25, green: 0.78, blue: 0.6)
    /// A note from outside the key.
    static let borrowed = Color(red: 0.66, green: 0.5, blue: 1)

    /// The 360's face buttons.
    static func color(of button: PadButton) -> Color? {
        switch button {
        case .a: Color(red: 0.36, green: 0.76, blue: 0.24)
        case .b: Color(red: 0.92, green: 0.3, blue: 0.26)
        case .x: Color(red: 0.24, green: 0.52, blue: 0.96)
        case .y: Color(red: 0.98, green: 0.76, blue: 0.14)
        default: nil
        }
    }

    static func line(_ line: Line) -> Color {
        line == .chord ? chord : melody
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    /// A panel of the stage: raised a little from the background.
    func panel() -> some View {
        padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule.opacity(0.6)))
    }
}

/// A small heading over a part of the stage: what plays it and what it is.
struct Caption: View {
    let control: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(control.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

/// A bar showing how far a trigger is pulled.
struct TriggerBar: View {
    let name: String
    let value: Double
    var steps: Int = 0
    var tint: Color = Theme.chord

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .frame(width: 22, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule().fill(tint).frame(width: max(0, proxy.size.width * value))
                    if steps > 1 {
                        ForEach(1..<steps, id: \.self) { step in
                            Rectangle().fill(Theme.panel)
                                .frame(width: 2)
                                .offset(x: proxy.size.width * TriggerSteps.three.edges[step - 1] - 1)
                        }
                    }
                }
            }
            .frame(height: 6)
        }
    }
}
