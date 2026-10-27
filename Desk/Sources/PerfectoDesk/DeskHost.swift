import AppKit
import DeskCore
import Foundation
import Observation
import PerfectoSound
import os

/// The desk's shell: it holds the `Desk`, feeds it a frame from the
/// controllers on every tick, and performs the effects it returns on the
/// audio, MIDI and the controllers' motors. Everything it decides is the
/// core's; this only reads hardware and plays.
///
/// The desk is stepped many times a second, so the screen is shown a copy
/// of it at most at the display's rate, and only when it has changed.
@Observable
@MainActor
final class DeskHost {
    /// The desk as the screen shows it.
    private(set) var desk: Desk
    /// The frame the controllers last gave, as the screen shows it.
    private(set) var frame = GamepadFrame(time: 0)
    /// The notes each line is sounding, for the piano.
    private(set) var sounding: [Line: [Int]] = [:]
    /// What plays the desk now: a controller's name, or the keyboard.
    private(set) var inputName = "Keyboard"
    /// Whether a controller (not the keyboard) is connected.
    private(set) var hasController = false
    /// The last rumble, shown as well as felt.
    private(set) var rumble: (Rumble, Double)?
    /// A line about something just done (a file saved).
    private(set) var notice: String?

    @ObservationIgnored private var live: Desk
    @ObservationIgnored private let audio = DeskAudio()
    @ObservationIgnored private let midi = DeskMIDI()
    @ObservationIgnored private let gamepads = SystemGamepads()
    @ObservationIgnored private let xbox360 = Xbox360USB()
    @ObservationIgnored private let keyboard = KeyboardKeys()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastShown = 0.0
    @ObservationIgnored private var liveSounding: [Line: [Int]] = [:]
    @ObservationIgnored private var lastSaved: (DeskSettings, LayoutKind)?
    @ObservationIgnored private let log = Logger(subsystem: "com.perfecto.desk", category: "host")

    /// How often the controllers are read and the desk stepped.
    static let rate = 250.0
    /// How often the screen is shown the desk.
    static let screenRate = 60.0

    static let catalog = SoundCatalog(SynthPreset.Category.allCases.filter { $0 != .recorded }.map { category in
        SoundCatalog.Category(name: category.displayName,
                              sounds: category.presets.map { SoundCatalog.Sound(id: $0.rawValue, name: $0.name) })
    })

    init() {
        let saved = Saved.load()
        live = Desk(settings: saved?.settings ?? DeskSettings(), layout: saved?.layout ?? .twinRings,
                    catalog: Self.catalog)
        desk = live
        audio.setTempo(live.settings.tempo)
    }

    func start() {
        guard timer == nil else { return }
        keyboard.start()
        xbox360.start()
        let timer = Timer(timeInterval: 1 / Self.rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: – Choices made with the mouse

    func choose(_ layout: LayoutKind) {
        perform(live.choose(layout))
        show(force: true)
    }

    func arrange(_ ring: RingArrangement) {
        live.settings.ringArrangement = ring
        show(force: true)
    }

    func toggleMenu() {
        perform(live.toggleMenu())
        show(force: true)
    }

    // MARK: – The loop

    private func tick() {
        let time = ProcessInfo.processInfo.systemUptime
        let before = live.settings
        perform(live.step(frame(at: time)))
        settingsChanged(from: before)
        show(force: false)
    }

    /// One frame from every source: a controller's and the keyboard's together.
    private func frame(at time: Double) -> GamepadFrame {
        var frame = keyboard.frame(at: time)
        var name: String?
        if let pad = gamepads.frame(at: time) {
            frame = pad.merged(with: frame)
            name = gamepads.name
        }
        if var usb = xbox360.frame {
            usb.time = time
            frame = usb.merged(with: frame)
            name = name ?? "Xbox 360 Controller (USB)"
        }
        if hasController != (name != nil) { hasController = name != nil }
        if inputName != (name ?? "Keyboard") {
            inputName = name ?? "Keyboard"
            log.info("playing from \(self.inputName)")
        }
        return frame
    }

    private func perform(_ effects: [DeskEffect]) {
        let output = live.settings.output
        for effect in effects {
            switch effect {
            case let .sound(line, notes, sound, level, brightness, tie):
                if output.sounds { audio.sound(line, notes: notes, sound: sound, level: level, brightness: brightness, tie: tie) }
                if output.sendsMIDI { midi.sound(line, notes: notes, level: level, brightness: brightness, tie: tie) }
                liveSounding[line] = notes
            case let .shape(line, level, brightness, bend):
                if output.sounds { audio.shape(line, level: level, brightness: brightness, bend: bend) }
                if output.sendsMIDI { midi.shape(line, level: level, brightness: brightness, bend: bend) }
            case let .silence(line):
                audio.silence(line)
                midi.silence(line)
                liveSounding[line] = []
            case let .rumble(kind):
                gamepads.play(kind)
                xbox360.play(kind)
                rumble = (kind, ProcessInfo.processInfo.systemUptime)
            case let .preview(sound, notes):
                audio.preview(sound: sound, notes: notes)
            case let .saveMIDI(bytes, name):
                save(bytes, name: name)
            }
        }
    }

    /// What follows from a setting changed: a sink switched off falls
    /// silent, the delay follows the tempo, and the settings are kept.
    private func settingsChanged(from before: DeskSettings) {
        let after = live.settings
        if before.output.sounds, !after.output.sounds { audio.silenceAll() }
        if before.output.sendsMIDI, !after.output.sendsMIDI { midi.silenceAll() }
        if before.tempo != after.tempo { audio.setTempo(after.tempo) }
    }

    private func show(force: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        guard force || time - lastShown >= 1 / Self.screenRate else { return }
        lastShown = time
        if let latest = live.frame?.shown, latest != frame { frame = latest }
        if live != desk { desk = live }
        if liveSounding != sounding { sounding = liveSounding }
        if let rumble, time - rumble.1 > 0.4 { self.rumble = nil }
        if lastSaved.map({ $0.0 != live.settings || $0.1 != live.layout }) ?? true {
            lastSaved = (live.settings, live.layout)
            Saved(settings: live.settings, layout: live.layout).store()
        }
    }

    private func save(_ bytes: [UInt8], name: String) {
        let folder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perfecto Desk", isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("mid")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
            notice = "Saved \(url.lastPathComponent) in Music › Perfecto Desk"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            notice = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Everything off, as the app quits.
    func stop() {
        perform(live.letGo())
        audio.silenceAll()
        midi.silenceAll()
    }
}

/// The settings and the layout, kept between launches.
private struct Saved: Codable {
    var settings: DeskSettings
    var layout: LayoutKind

    private static let key = "desk.saved"

    static func load() -> Saved? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }

    func store() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
