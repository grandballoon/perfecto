import SwiftUI
import Testing
import UIKit
@testable import Perfecto

/// Draws the UI spec: every screen in `SpecScreen`'s lists as a PDF of
/// shapes and text, made from the app's own views on screen in a window, so
/// the spec is the app as it is and cannot drift from it.
/// `scripts/export-ui-spec.sh` runs this and turns the PDFs into SVG files
/// for a design tool; run with the other tests, it checks that every screen
/// still draws and leaves its drawings in a temporary folder.
@Suite("UI spec")
@MainActor
struct UISpecExportTests {

    /// Where the drawings go: `UI_SPEC_DIR`, which the script sets.
    private let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UI_SPEC_DIR"]
                             ?? NSTemporaryDirectory() + "perfecto-ui-spec")

    @Test func everyScreenIsDrawnAsShapesAndText() async throws {
        let pdfs = folder.appendingPathComponent("pdf")
        try? FileManager.default.removeItem(at: pdfs)
        try FileManager.default.createDirectory(at: pdfs, withIntermediateDirectories: true)
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)

        var drawn: [Drawn] = []
        for turn in Turn.allCases {
            try await self.turn(scene, to: turn)
            for screen in SpecScreen.screens {
                drawn.append(try draw(screen, named: "\(turn.rawValue)-\(screen.name)", into: pdfs))
            }
        }
        try await self.turn(scene, to: .portrait)
        for page in SpecScreen.menuPages {
            drawn.append(try draw(page, wholeMenuPage: true, named: page.name, into: pdfs))
        }

        try index(of: drawn).write(to: folder.appendingPathComponent("index.md"),
                                   atomically: true, encoding: .utf8)
        print("UI spec: \(drawn.count) drawings in \(folder.path)")
    }

    // MARK: – Drawing

    /// A drawing that was made, for the index.
    private struct Drawn {
        var name: String
        var size: CGSize
        var omissions: Set<LayerDrawing.Omission>
        var bitmaps: Int
    }

    /// Shows `screen` in a window and draws the window to a PDF. A whole
    /// menu page is drawn in a window made tall enough to hold all of it,
    /// and only the panel's width of that window is kept.
    private func draw(_ screen: SpecScreen, wholeMenuPage: Bool = false,
                      named name: String, into pdfs: URL) throws -> Drawn {
        let state = PerformanceState(sink: RecordingSink(),
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     clock: ManualClock())
        screen.arrange(state)
        let menu = SidePanelState()
        if let page = screen.menu { menu.show(page) }

        let window = try show(PerformanceView(sidePanel: menu)
            .environment(state)
            .environment(state.sequencerState))
        defer { window.isHidden = true }

        var page = window.bounds
        if wholeMenuPage {
            let scroll = try #require(window.firstSubview(UIScrollView.self))
            let insets = scroll.adjustedContentInset
            window.frame.size.height += max(0, scroll.contentSize.height + insets.top + insets.bottom
                                            - scroll.bounds.height)
            redraw(window)
            page = CGRect(x: 0, y: 0, width: SidePanelLayout.width(in: window.bounds.width),
                          height: window.bounds.height)
        }

        var drawing = LayerDrawing()
        let pdf = UIGraphicsPDFRenderer(bounds: page).pdfData { renderer in
            renderer.beginPage()
            drawing.draw(window.layer, in: renderer.cgContext)
        }
        // Text drawn as text names its font in the file; a picture of text
        // does not.
        #expect(pdf.range(of: Data("/BaseFont".utf8)) != nil, "\(name) has no text in it")
        try pdf.write(to: pdfs.appendingPathComponent("\(name).pdf"))
        return Drawn(name: name, size: page.size, omissions: drawing.omissions, bitmaps: drawing.bitmaps)
    }

    // MARK: – Turning the phone

    private enum Turn: String, CaseIterable {
        case portrait, landscape

        var orientations: UIInterfaceOrientationMask { self == .portrait ? .portrait : .landscapeRight }
    }

    /// Turns the test host's scene, and waits until it has turned.
    private func turn(_ scene: UIWindowScene, to turn: Turn) async throws {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: turn.orientations))
        let turned = try await waitUntil {
            let size = scene.coordinateSpace.bounds.size
            return (size.width > size.height) == (turn == .landscape)
        }
        try #require(turned, "the scene did not turn to \(turn.rawValue)")
    }

    // MARK: – Index

    /// What was drawn, and what each drawing leaves out.
    private func index(of drawn: [Drawn]) -> String {
        var lines = [
            "# Perfecto UI spec",
            "",
            "Drawn from the app's own views on \(UIDevice.current.name), by `scripts/export-ui-spec.sh`.",
            "Sizes are in points.",
            "A drawing leaves out what is listed beside it, and system controls (switches, sliders) are drawn only roughly.",
            "",
            "| Drawing | Size | Left out | Bitmaps |",
            "| --- | --- | --- | --- |",
        ]
        for drawing in drawn {
            let omissions = drawing.omissions.sorted().map(\.rawValue).joined(separator: ", ")
            lines.append("| \(drawing.name) | \(Int(drawing.size.width)) × \(Int(drawing.size.height)) "
                         + "| \(omissions) | \(drawing.bitmaps) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private extension UIView {
    /// The first view of `type` in this one, searched depth first.
    func firstSubview<V: UIView>(_ type: V.Type) -> V? {
        for subview in subviews {
            if let found = subview as? V ?? subview.firstSubview(type) { return found }
        }
        return nil
    }
}
