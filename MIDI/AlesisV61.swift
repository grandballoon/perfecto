import CoreGraphics

extension ControllerLayout {
    /// The Alesis V61 (the first one, not the MKII, whose controls are
    /// others): 61 keys, two wheels, the octave buttons, 8 pads, 4 knobs, 4
    /// buttons and a sustain pedal's jack, measured in centimetres on its
    /// 112 by 24.4 panel.
    ///
    /// Its guide gives the wheels' messages, and the knobs are on CC 20 to
    /// 23 (as Spectrasonics' setup for it has them). The pads' and buttons'
    /// are nowhere written: notes 36 to 43 on channel 10 and CC 48 to 51
    /// are the usual ones and a guess, and a V61 that sends others is
    /// taught them by learning.
    static let alesisV61 = ControllerLayout(
        id: "alesis-v61",
        name: "Alesis V61",
        size: CGSize(width: 112, height: 24.4),
        nameplate: CGRect(x: 3, y: 1.4, width: 19, height: 3),
        keyboard: ControllerKeyboard(lowestNote: 36, count: 61,
                                     frame: CGRect(x: 24.5, y: 10.2, width: 85, height: 14.2)),
        controls: pads + knobs + buttons + [
            ControllerControl(id: "octaveDown", name: "Octave down", mark: "−", kind: .octaveDown,
                              frame: CGRect(x: 5.5, y: 7, width: 4, height: 1.8), address: nil),
            ControllerControl(id: "octaveUp", name: "Octave up", mark: "+", kind: .octaveUp,
                              frame: CGRect(x: 11.5, y: 7, width: 4, height: 1.8), address: nil),
            ControllerControl(id: "pitch", name: "Pitch wheel", mark: "", kind: .pitchWheel,
                              frame: CGRect(x: 6.2, y: 12.4, width: 2.6, height: 10),
                              address: .pitchBend()),
            ControllerControl(id: "mod", name: "Mod wheel", mark: "", kind: .modWheel,
                              frame: CGRect(x: 12.2, y: 12.4, width: 2.6, height: 10),
                              address: .controller(1)),
            ControllerControl(id: "sustain", name: "Sustain pedal", mark: "SUSTAIN", kind: .pedal,
                              frame: CGRect(x: 99.5, y: 1.6, width: 10, height: 1.9),
                              address: .controller(64)),
        ],
        captions: [
            ControllerCaption(text: "OCTAVE", frame: CGRect(x: 5.5, y: 5.2, width: 10, height: 1.4)),
            ControllerCaption(text: "PITCH", frame: CGRect(x: 4.5, y: 22.7, width: 6, height: 1.4)),
            ControllerCaption(text: "MOD", frame: CGRect(x: 10.5, y: 22.7, width: 6, height: 1.4)),
            ControllerCaption(text: "PADS", frame: CGRect(x: 26, y: 8.8, width: 15.4, height: 1.2)),
            ControllerCaption(text: "KNOBS", frame: CGRect(x: 45.5, y: 7.4, width: 18, height: 1.4)),
            ControllerCaption(text: "BUTTONS", frame: CGRect(x: 67.5, y: 8.4, width: 7.2, height: 1.4)),
        ],
        recognizes: { name in
            let name = name.uppercased()
            return name.contains("V61") && !["MKII", "MK2", "MK 2", "MK II"].contains { name.contains($0) }
        })

    /// Two rows of four, numbered from the bottom left as drum pads are.
    private static let pads: [ControllerControl] = (0..<8).map { index in
        let row = index < 4 ? 1 : 0, column = index % 4
        return ControllerControl(id: "pad\(index + 1)", name: "Pad \(index + 1)", mark: "\(index + 1)",
                                 kind: .pad,
                                 frame: CGRect(x: 26 + Double(column) * 4, y: 1.2 + Double(row) * 3.8,
                                               width: 3.4, height: 3.4),
                                 address: .note(36 + index, channel: 9))
    }

    private static let knobs: [ControllerControl] = (0..<4).map { index in
        ControllerControl(id: "knob\(index + 1)", name: "Knob \(index + 1)", mark: "\(index + 1)",
                          kind: .knob,
                          frame: CGRect(x: 45.5 + Double(index) * 5, y: 1.8, width: 3, height: 3),
                          address: .controller(20 + index))
    }

    /// Two rows of two.
    private static let buttons: [ControllerControl] = (0..<4).map { index in
        ControllerControl(id: "button\(index + 1)", name: "Button \(index + 1)", mark: "\(index + 1)",
                          kind: .button,
                          frame: CGRect(x: 67.5 + Double(index % 2) * 4, y: 2 + Double(index / 2) * 3.2,
                                        width: 3.2, height: 1.8),
                          address: .controller(48 + index))
    }
}
