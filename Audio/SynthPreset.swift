import AudioKit
import SoundpipeAudioKit

enum SynthPreset: Int, CaseIterable, Identifiable, Sendable {
    case sawLead, squareBass, sinePad, triangleBell, fmBell, fmBass, pluck, brass

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .sawLead:      return "Saw Lead"
        case .squareBass:   return "Square Bass"
        case .sinePad:      return "Sine Pad"
        case .triangleBell: return "Triangle Bell"
        case .fmBell:       return "FM Bell"
        case .fmBass:       return "FM Bass"
        case .pluck:        return "Pluck"
        case .brass:        return "Brass"
        }
    }

    var table: Table {
        switch self {
        case .sawLead:      return Table(.sawtooth)
        case .squareBass:   return Table(.square)
        case .sinePad:      return Table(.sine)
        case .triangleBell: return Table(.triangle)
        case .fmBell:       return Table(.sine)
        case .fmBass:       return Table(.square)
        case .pluck:        return Table(.sawtooth)
        case .brass:        return Table(.square)
        }
    }

    var attack: AUValue {
        switch self {
        case .sawLead:      return 0.01
        case .squareBass:   return 0.01
        case .sinePad:      return 0.08
        case .triangleBell: return 0.005
        case .fmBell:       return 0.005
        case .fmBass:       return 0.01
        case .pluck:        return 0.005
        case .brass:        return 0.05
        }
    }

    var decay: AUValue {
        switch self {
        case .sawLead:      return 0.10
        case .squareBass:   return 0.05
        case .sinePad:      return 0.08
        case .triangleBell: return 0.30
        case .fmBell:       return 0.40
        case .fmBass:       return 0.15
        case .pluck:        return 0.20
        case .brass:        return 0.10
        }
    }

    var sustain: AUValue {
        switch self {
        case .sawLead:      return 0.80
        case .squareBass:   return 0.90
        case .sinePad:      return 0.75
        case .triangleBell: return 0.20
        case .fmBell:       return 0.15
        case .fmBass:       return 0.70
        case .pluck:        return 0.00
        case .brass:        return 0.85
        }
    }

    var release: AUValue {
        switch self {
        case .sawLead:      return 0.30
        case .squareBass:   return 0.20
        case .sinePad:      return 0.35
        case .triangleBell: return 1.20
        case .fmBell:       return 2.00
        case .fmBass:       return 0.20
        case .pluck:        return 0.50
        case .brass:        return 0.15
        }
    }

    var amplitude: AUValue {
        switch self {
        case .sawLead:      return 0.20
        case .squareBass:   return 0.20
        case .sinePad:      return 0.25
        case .triangleBell: return 0.30
        case .fmBell:       return 0.25
        case .fmBass:       return 0.22
        case .pluck:        return 0.35
        case .brass:        return 0.22
        }
    }
}
