import SwiftUI
import Testing
import UIKit
@testable import Perfecto

/// A window with room for it shows the keys and the sequencer side by side.
@Suite("Desk layout", .serialized)
@MainActor
struct DeskLayoutTests {

    @Test func onlyAWindowWiderThanAPhoneIsLaidOutForTheDesk() {
        #expect(DeskLayout.fits(CGSize(width: 1500, height: 950)))
        #expect(!DeskLayout.fits(CGSize(width: 393, height: 852)))
        // The largest phone, on its side.
        #expect(!DeskLayout.fits(CGSize(width: 956, height: 440)))
    }

    /// The play screen in a window of `size`, with the sequencer's mode on.
    private func screen(_ size: CGSize) throws -> (state: PerformanceState, window: UIWindow) {
        let state = PerformanceState(sink: RecordingSink(),
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: isolatedDefaults()),
                                     clock: ManualClock())
        state.selectMode(.sequencer)
        let window = try show(PerformanceView()
            .environment(state)
            .environment(state.sequencerState), size: size)
        return (state, window)
    }

    @Test func theKeysAreAlwaysPlayedBesideTheSequencer() throws {
        let (state, window) = try screen(CGSize(width: 1500, height: 950))
        defer { window.isHidden = true }
        #expect(state.mode.kind == .play)
        state.press(degree: .I)
        #expect(state.activeDegree == .I)
    }

    @Test func aPhonesScreenKeepsTheSequencersMode() throws {
        let (state, window) = try screen(CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        #expect(state.mode.kind == .sequencer)
    }

    @Test func theTonnetzTakesTheSequencersPlaceAndIsSilentOnceGone() throws {
        let (state, window) = try screen(CGSize(width: 1500, height: 950))
        defer { window.isHidden = true }
        state.deskPane = .tonnetz
        redraw(window)
        state.tonnetz.press(.home)
        #expect(state.tonnetz.isSounding)

        state.deskPane = .sequencer
        redraw(window)

        #expect(!state.tonnetz.isSounding)
    }
}
