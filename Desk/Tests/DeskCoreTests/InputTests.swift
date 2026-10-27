import Testing
@testable import DeskCore

@Suite("Inputs")
struct InputTests {

    private func report(buttons: (UInt8, UInt8) = (0, 0), lt: UInt8 = 0, rt: UInt8 = 0,
                        lx: Int16 = 0, ly: Int16 = 0, rx: Int16 = 0, ry: Int16 = 0) -> [UInt8] {
        func bytes(_ v: Int16) -> [UInt8] { [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)] }
        return [0x00, 0x14, buttons.0, buttons.1, lt, rt] + bytes(lx) + bytes(ly) + bytes(rx) + bytes(ry) + [0, 0, 0, 0, 0, 0]
    }

    @Test func aReportsButtonsAreRead() {
        let frame = Xbox360.frame(report(buttons: (0x11, 0x92)), at: 1)
        #expect(frame?.buttons == [.up, .start, .rb, .a, .y])
        #expect(frame?.time == 1)
    }

    @Test func aReportsSticksAndTriggersAreRead() {
        let frame = Xbox360.frame(report(lt: 255, rt: 0, lx: 32767, ly: 0, rx: 0, ry: -32768), at: 0)!
        #expect(frame.leftTrigger == 1)
        #expect(frame.rightTrigger == 0)
        #expect(abs(frame.left.x - 1) < 0.001)
        #expect(abs(frame.right.y + 1) < 0.001)
    }

    @Test func aSticksLooseMiddleIsRest() {
        let frame = Xbox360.frame(report(lx: 6000, ly: -5000), at: 0)!
        #expect(frame.left == .rest)
    }

    @Test func otherReportsAreNotFrames() {
        #expect(Xbox360.frame([0x01, 0x03, 0x06], at: 0) == nil)
        #expect(Xbox360.frame([0x08, 0x03, 0x00] + Array(repeating: 0, count: 17), at: 0) == nil)
    }

    @Test func theKeyboardIsAController() {
        let frame = KeyboardPad.frame(holding: ["w", "d", "l", " ", "c", "up"], shift: true, at: 2)
        #expect(frame.buttons == [.a, .up])
        #expect(frame.rightTrigger == 1)
        #expect(abs(frame.left.bearing - 45) < 0.001)
        #expect(abs(frame.right.radius - 0.62) < 0.001)
        #expect(KeyboardPad.key(for: .button(.a)) == "Space")
    }
}
