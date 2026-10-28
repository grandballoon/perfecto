import MusicTheoryCore

/// The sounds there are to choose from, by category, in the order the
/// library lists them. The shell gives it from the presets
/// (`SynthPreset`), so the core knows sounds only by id and name.
public struct SoundCatalog: Equatable, Sendable {
    public struct Sound: Equatable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Category: Equatable, Sendable {
        public let name: String
        public let sounds: [Sound]

        public init(name: String, sounds: [Sound]) {
            self.name = name
            self.sounds = sounds
        }
    }

    public let categories: [Category]

    public init(_ categories: [Category]) {
        self.categories = categories.filter { !$0.sounds.isEmpty }
    }

    /// Where the sound `id` is: its category and its place in it.
    public func place(of id: String) -> (category: Int, index: Int)? {
        for (c, category) in categories.enumerated() {
            if let i = category.sounds.firstIndex(where: { $0.id == id }) { return (c, i) }
        }
        return nil
    }

    public func name(of id: String) -> String {
        place(of: id).map { categories[$0.category].sounds[$0.index].name } ?? id
    }

    /// The sound `steps` from `id` through every category in order.
    public func sound(_ steps: Int, from id: String) -> String {
        let all = categories.flatMap(\.sounds)
        guard let at = all.firstIndex(where: { $0.id == id }) else { return all.first?.id ?? id }
        return all[((at + steps) % all.count + all.count) % all.count].id
    }
}

/// The menu, driven by the d-pad and A: every setting a layout shares, and
/// the sound library.
public struct DeskMenu: Equatable, Sendable {
    public enum Row: CaseIterable, Sendable {
        case layout, consonance, guardInKey, forgetRun, ring, ringOrder, ringFilter, lbLayer, chordSound, lineSound, key, scale, octave, tempo, grid, voiceLeading, ranking, output, saveMIDI

        public var name: String {
            switch self {
            case .layout: "Layout"
            case .consonance: "Consonance guard"
            case .guardInKey: "Guard: key's notes only"
            case .forgetRun: "Forget the run"
            case .ring: "Color ring"
            case .ringOrder: "Ring order"
            case .ringFilter: "Ring filter"
            case .lbLayer: "LB layer"
            case .chordSound: "Chord sound"
            case .lineSound: "Line sound"
            case .key: "Key"
            case .scale: "Scale"
            case .octave: "Octave"
            case .tempo: "Tempo"
            case .grid: "Arranger grid"
            case .voiceLeading: "Voice leading"
            case .ranking: "Compass order"
            case .output: "Output"
            case .saveMIDI: "Save the arrangement"
            }
        }
    }

    /// The library open over the menu: a sound for `line`, browsed by
    /// category (left and right) and sound (up and down).
    public struct Library: Equatable, Sendable {
        public let line: Line
        public var category: Int
        public var index: Int
    }

    public var row = Row.layout
    public var library: Library?

    public init() {}
}

/// Perfecto at a desk: the settings, a state for each layout, the menu, and
/// the frame before. One `step` a frame: the controller in, what to sound
/// out.
public struct Desk: Equatable, Sendable {
    public var settings: DeskSettings
    public private(set) var layout: LayoutKind
    public private(set) var twinRings = TwinRings()
    public private(set) var petals = Petals()
    public private(set) var neighbourhood = Neighbourhood()
    public private(set) var twoVoices = TwoVoices()
    public private(set) var arranger = Arranger()
    public private(set) var menu: DeskMenu?
    public let catalog: SoundCatalog
    /// What the last frame said, if any has come.
    public private(set) var frame: GamepadFrame?

    /// Two desks are the same if they are in the same state: when the last
    /// frame came is not part of it.
    public static func == (a: Desk, b: Desk) -> Bool {
        a.settings == b.settings && a.layout == b.layout && a.twinRings == b.twinRings && a.petals == b.petals
            && a.neighbourhood == b.neighbourhood && a.twoVoices == b.twoVoices && a.arranger == b.arranger
            && a.menu == b.menu && a.catalog == b.catalog && a.frame?.untimed == b.frame?.untimed
    }

    public init(settings: DeskSettings = DeskSettings(), layout: LayoutKind = .twinRings, catalog: SoundCatalog) {
        self.settings = settings
        self.layout = layout
        self.catalog = catalog
    }

    public mutating func step(_ frame: GamepadFrame) -> [DeskEffect] {
        let previous = self.frame ?? GamepadFrame(time: frame.time)
        self.frame = frame
        let input = PadInput(frame: frame, previous: previous)
        if menu != nil { return stepMenu(input) }
        if input.pressed(.start) {
            menu = DeskMenu()
            return releaseLayout()
        }
        if input.pressed(.back) {
            let all = LayoutKind.allCases
            return choose(all[(all.firstIndex(of: layout)! + 1) % all.count])
        }
        let key = settings.key
        let out: [DeskEffect]
        switch layout {
        case .twinRings: out = twinRings.step(input, settings: &settings)
        case .petals: out = petals.step(input, settings: &settings)
        case .neighbourhood: out = neighbourhood.step(input, settings: &settings)
        case .twoVoices: out = twoVoices.step(input, settings: &settings)
        case .arranger: out = arranger.step(input, settings: &settings)
        }
        if settings.key != key { settings.favorites.keyChanged(to: settings.key) }
        settings.consonance.hear(out)
        return out
    }

    /// The chord to pin: what the layout is sounding, or else what the
    /// hands are on.
    public var pinnable: DeskChord? {
        switch layout {
        case .twinRings: twinRings.line.isSounding ? twinRings.line.chord : twinRings.chord(settings)
        case .petals: petals.line.isSounding ? petals.line.chord : nil
        case .neighbourhood: neighbourhood.line.isSounding ? neighbourhood.line.chord : neighbourhood.centre
        case .twoVoices: twoVoices.chords.isSounding ? twoVoices.chords.chord : twoVoices.chord(settings)
        case .arranger: arranger.line.isSounding ? arranger.line.chord : arranger.aimed(settings)
        }
    }

    /// Plays `layout` from now: the one left lets go of everything.
    public mutating func choose(_ layout: LayoutKind) -> [DeskEffect] {
        guard layout != self.layout else { return [] }
        let out = releaseLayout()
        self.layout = layout
        return out + [.rumble(.bump)]
    }

    /// Opens or closes the menu, as Start does.
    public mutating func toggleMenu() -> [DeskEffect] {
        if menu == nil {
            menu = DeskMenu()
            return releaseLayout()
        }
        menu = nil
        return []
    }

    /// Lets go of everything the layout holds: the app is quitting.
    public mutating func letGo() -> [DeskEffect] {
        releaseLayout()
    }

    private mutating func releaseLayout() -> [DeskEffect] {
        let out: [DeskEffect]
        switch layout {
        case .twinRings: out = twinRings.releaseAll()
        case .petals: out = petals.releaseAll()
        case .neighbourhood: out = neighbourhood.releaseAll()
        case .twoVoices: out = twoVoices.releaseAll()
        case .arranger: out = arranger.releaseAll()
        }
        settings.consonance.hear(out)
        return out
    }

    /// What every control does now.
    public var legend: Legend {
        guard menu == nil else {
            if menu?.library != nil {
                return [.button(.left): "Category before", .button(.right): "Next category",
                        .button(.up): "Sound before", .button(.down): "Next sound",
                        .button(.a): "Choose", .button(.b): "Back"]
            }
            return [.button(.up): "Row up", .button(.down): "Row down", .button(.left): "Less",
                    .button(.right): "More", .button(.a): "Open", .button(.b): "Close", .button(.start): "Close"]
        }
        switch layout {
        case .twinRings: return twinRings.legend(settings)
        case .petals: return petals.legend(settings)
        case .neighbourhood: return neighbourhood.legend(settings)
        case .twoVoices: return twoVoices.legend(settings)
        case .arranger: return arranger.legend(settings)
        }
    }

    // MARK: – The menu

    private mutating func stepMenu(_ input: PadInput) -> [DeskEffect] {
        guard var menu else { return [] }
        var out: [DeskEffect] = []
        var closes = input.pressed(.start)
        if var library = menu.library {
            let category = catalog.categories[library.category]
            if input.pressed(.up) { library.index = max(0, library.index - 1) }
            if input.pressed(.down) { library.index = min(category.sounds.count - 1, library.index + 1) }
            if input.pressed(.left) || input.pressed(.right) {
                let count = catalog.categories.count
                library.category = (library.category + (input.pressed(.left) ? count - 1 : 1)) % count
                library.index = min(library.index, catalog.categories[library.category].sounds.count - 1)
            }
            // A sound is chosen as it is reached, and heard.
            let chosen = catalog.categories[library.category].sounds[library.index].id
            if chosen != sound(of: library.line) {
                setSound(chosen, for: library.line)
                out.append(preview(library.line))
            }
            menu.library = input.pressed(.a) || input.pressed(.b) ? nil : library
        } else {
            closes = closes || input.pressed(.b)
            let rows = DeskMenu.Row.allCases
            let at = rows.firstIndex(of: menu.row)!
            if input.pressed(.up) { menu.row = rows[max(0, at - 1)] }
            if input.pressed(.down) { menu.row = rows[min(rows.count - 1, at + 1)] }
            if input.pressed(.left) { out += change(menu.row, by: -1) }
            if input.pressed(.right) { out += change(menu.row, by: 1) }
            if input.pressed(.a) {
                switch menu.row {
                case .chordSound, .lineSound:
                    let line: Line = menu.row == .chordSound ? .chord : .melody
                    let place = catalog.place(of: sound(of: line)) ?? (0, 0)
                    menu.library = DeskMenu.Library(line: line, category: place.category, index: place.index)
                case .saveMIDI:
                    if let file = arranger.midiFile(settings) {
                        out.append(.saveMIDI(bytes: file.encoded(), name: "Perfecto Desk \(settings.summary)"))
                    }
                case .layout:
                    closes = true
                default:
                    out += change(menu.row, by: 1)
                }
            }
        }
        self.menu = closes ? nil : menu
        return out
    }

    private mutating func change(_ row: DeskMenu.Row, by steps: Int) -> [DeskEffect] {
        switch row {
        case .layout:
            let all = LayoutKind.allCases
            layout = all[((all.firstIndex(of: layout)! + steps) % all.count + all.count) % all.count]
        case .consonance:
            settings.moveGuard(by: steps)
        case .guardInKey:
            settings.consonance.inKey.toggle()
        case .forgetRun:
            settings.consonance.forgetRun()
        case .ring:
            settings.moveRingArrangement(by: steps)
        case .ringOrder:
            settings.moveRingOrder(by: steps)
        case .ringFilter:
            settings.moveRingFilter(by: steps)
        case .lbLayer:
            settings.lbLayer = settings.lbLayer == .compass ? .voices : .compass
        case .chordSound, .lineSound:
            let line: Line = row == .chordSound ? .chord : .melody
            setSound(catalog.sound(steps, from: sound(of: line)), for: line)
            return [preview(line)]
        case .key:
            let root = (settings.key.root.rawValue + steps + 12) % 12
            settings.key = Key(root: PitchClass(rawValue: root)!, scale: settings.key.scale)
            settings.favorites.keyChanged(to: settings.key)
            return [preview(.chord)]
        case .scale:
            settings.moveScale(by: steps)
            settings.favorites.keyChanged(to: settings.key)
            return [preview(.chord)]
        case .octave:
            settings.moveOctave(by: steps)
            return [preview(.chord)]
        case .tempo:
            settings.tempo = min(DeskSettings.tempos.upperBound, max(DeskSettings.tempos.lowerBound, settings.tempo + 2 * Double(steps)))
        case .grid:
            settings.moveGrid(by: steps)
        case .voiceLeading:
            settings.voiceLeading.toggle()
        case .ranking:
            settings.ranking = settings.ranking == .theory ? .common : .theory
        case .output:
            let all = DeskOutput.allCases
            settings.output = all[((all.firstIndex(of: settings.output)! + steps) % all.count + all.count) % all.count]
        case .saveMIDI:
            break
        }
        return []
    }

    private func sound(of line: Line) -> String {
        line == .chord ? settings.chordSound : settings.lineSound
    }

    private mutating func setSound(_ id: String, for line: Line) {
        if line == .chord { settings.chordSound = id } else { settings.lineSound = id }
    }

    /// A short sound of `line`'s: the tonic's chord, or its note an octave up.
    private func preview(_ line: Line) -> DeskEffect {
        let chord = DeskChord(key: settings.key, degree: .I)
        let notes = chord.notes(settings)
        return .preview(sound: sound(of: line), notes: line == .chord ? notes : [notes[0] + 12])
    }

    /// The value a menu row shows.
    public func value(of row: DeskMenu.Row) -> String {
        switch row {
        case .layout: layout.name
        case .consonance: settings.consonance.mode.name
        case .guardInKey: settings.consonance.inKey ? "On" : "Off"
        case .forgetRun: settings.consonance.recent.isEmpty ? "Nothing heard" : "A to forget"
        case .ring: settings.ringArrangement.name
        case .ringOrder: settings.ringOrder.name
        case .ringFilter: settings.ringFilter.name
        case .lbLayer: settings.lbLayer.name
        case .chordSound: catalog.name(of: settings.chordSound)
        case .lineSound: catalog.name(of: settings.lineSound)
        case .key: settings.key.root.name
        case .scale: settings.key.scale.displayName
        case .octave: "\(settings.octave)"
        case .tempo: "\(Int(settings.tempo)) bpm"
        case .grid: settings.grid.name
        case .voiceLeading: settings.voiceLeading ? "On" : "Off"
        case .ranking: settings.ranking == .theory ? "Theory" : "Common first"
        case .output: settings.output.name
        case .saveMIDI: !arranger.arrangement.isEmpty ? "A to save" : "Nothing written yet"
        }
    }
}
