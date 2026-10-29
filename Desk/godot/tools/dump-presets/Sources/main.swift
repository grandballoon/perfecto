import Foundation
import PerfectoKernel
import PerfectoSound

// Usage: dump-presets <out.json>
// Every preset's `PerfectoPatch`, field for field, in the kernel's own names.

func sweep(_ s: PerfectoSweep) -> [String: Any] {
    ["from": s.from, "to": s.to, "time": s.time]
}

func op(_ o: PerfectoOperator) -> [String: Any] {
    let partials = withUnsafeBytes(of: o.partials) { Array($0.bindMemory(to: Float.self)) }
    return ["wave": Int(o.wave.rawValue), "pulse_width": o.pulse_width, "partials": partials,
            "ratio": o.ratio, "level": o.level]
}

func patch(_ p: PerfectoPatch) -> [String: Any] {
    [
        "operators": [op(p.operators.0), op(p.operators.1)],
        "modulates": p.modulates, "index": sweep(p.index),
        "unison": Int(p.unison), "spread": p.spread, "drift": p.drift,
        "noise": sweep(p.noise), "glide": p.glide,
        "filtered": p.filtered, "cutoff": sweep(p.cutoff), "resonance": p.resonance, "steep": p.steep,
        "drive": p.drive,
        "lfo": ["rate": p.lfo.rate, "rise": p.lfo.rise, "pitch": p.lfo.pitch,
                "pulse_width": p.lfo.pulse_width, "cutoff": p.lfo.cutoff],
        "attack": p.attack, "decay": p.decay, "sustain": p.sustain, "release": p.release,
        "level": p.level,
        "sampled": p.sampled, "capture": Int(p.capture), "root": p.root,
        "additive": p.additive,
    ]
}

let presets: [[String: Any]] = SynthPreset.allCases.map {
    ["id": $0.rawValue, "name": $0.name, "category": $0.category.displayName, "patch": patch($0.patch.kernelPatch)]
}
let data = try JSONSerialization.data(withJSONObject: presets, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(presets.count) presets")
