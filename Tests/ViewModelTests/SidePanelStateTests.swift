import CoreGraphics
import Testing
@testable import Perfecto

@MainActor
@Suite struct SidePanelStateTests {

    @Test func startsClosed() {
        #expect(SidePanelState().page == nil)
    }

    @Test func theButtonOpensTheMenuAtItsFirstPage() {
        let panel = SidePanelState()
        panel.toggle()
        #expect(panel.page == SidePanelPage.allCases.first)
        #expect(panel.isOpen)
    }

    @Test func theButtonClosesTheOpenMenu() {
        let panel = SidePanelState()
        panel.toggle()
        panel.toggle()
        #expect(panel.page == nil)
        #expect(!panel.isOpen)
    }

    @Test func aTabSwitchesPagesWithoutClosing() {
        let panel = SidePanelState()
        panel.toggle()
        panel.show(.effects)
        #expect(panel.page == .effects)
    }

    @Test(arguments: SidePanelPage.allCases)
    func theMenuReopensAtThePageItWasLeftOn(page: SidePanelPage) {
        let panel = SidePanelState()
        panel.show(page)
        panel.toggle()
        panel.toggle()
        #expect(panel.page == page)
    }
}

@Suite struct SidePanelLayoutTests {

    /// Portrait and landscape widths of the phones the app runs on, inside
    /// the safe area.
    private static let screenWidths: [CGFloat] = [320, 375, 393, 440, 568, 667, 734, 852, 956]

    @Test(arguments: screenWidths)
    func alwaysLeavesPartOfTheScreenPlayable(width: CGFloat) {
        let panel = SidePanelLayout.width(in: width)
        #expect(panel > 0)
        #expect(width - panel >= 120)
    }

    /// In landscape the chord keys are in the trailing half of the screen.
    @Test(arguments: screenWidths.filter { $0 >= 667 })
    func staysWithinTheLeadingHalfInLandscape(width: CGFloat) {
        #expect(SidePanelLayout.width(in: width) <= width / 2)
    }
}
