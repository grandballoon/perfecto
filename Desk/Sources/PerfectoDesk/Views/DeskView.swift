import DeskCore
import MusicTheoryCore
import SwiftUI

/// The desk's window: the layouts along the top, the layout's stage, the
/// hand beside it, and the piano along the bottom.
struct DeskView: View {
    @Environment(DeskHost.self) private var host

    var body: some View {
        let desk = host.desk
        VStack(spacing: 14) {
            TopBar()
            HStack(alignment: .top, spacing: 16) {
                stage(desk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SideColumn()
                    .frame(width: 330)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .panel()
            }
            StatusLine()
            PianoView(sounding: host.sounding)
                .frame(height: 64)
        }
        .padding(18)
        .background(Theme.background)
        .overlay {
            if let menu = desk.menu {
                MenuView(menu: menu)
            }
        }
    }

    @ViewBuilder
    private func stage(_ desk: Desk) -> some View {
        switch desk.layout {
        case .twinRings:
            TwinRingsView(layout: desk.twinRings, settings: desk.settings, frame: host.frame) { host.arrange($0) }
        case .petals: PetalsView(layout: desk.petals, settings: desk.settings, frame: host.frame)
        case .neighbourhood: NeighbourhoodView(layout: desk.neighbourhood, settings: desk.settings, frame: host.frame)
        case .twoVoices: TwoVoicesView(layout: desk.twoVoices, settings: desk.settings, frame: host.frame)
        case .arranger: ArrangerView(layout: desk.arranger, settings: desk.settings, frame: host.frame)
        }
    }
}

/// The layouts, chosen by Back or a click, and what the desk is set to.
struct TopBar: View {
    @Environment(DeskHost.self) private var host

    var body: some View {
        let desk = host.desk
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(LayoutKind.allCases, id: \.self) { layout in
                    Button {
                        host.choose(layout)
                    } label: {
                        Text(layout.name)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundStyle(layout == desk.layout ? Color.black : Theme.text)
                            .background(layout == desk.layout ? Theme.chord : Theme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Text("Back ▸").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.faint)
                Spacer()
                Button {
                    host.toggleMenu()
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
            }
            HStack(spacing: 16) {
                Text(desk.layout.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if desk.settings.consonance.mode != .off {
                    GuardChip(consonance: desk.settings.consonance)
                }
                Fact(name: "Key", value: desk.settings.summary)
                Fact(name: "Voicing", value: desk.settings.voicingName + (desk.settings.voiceLeading ? " · led" : ""))
                Fact(name: "Chords", value: desk.catalog.name(of: desk.settings.chordSound))
                Fact(name: "Line", value: desk.catalog.name(of: desk.settings.lineSound))
                Fact(name: "Out", value: desk.settings.output.name)
            }
        }
    }
}

struct Fact: View {
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

/// What plays, what was felt, and anything just done.
struct StatusLine: View {
    @Environment(DeskHost.self) private var host

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: host.hasController ? "gamecontroller.fill" : "keyboard")
                .foregroundStyle(host.hasController ? Theme.near : Theme.secondary)
            Text(host.inputName)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            if !host.hasController {
                Text("No controller: the keyboard plays. Connect an Xbox controller to play from it.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if let (rumble, _) = host.rumble {
                Text(rumble == .tick ? "· tick" : rumble == .bump ? "· bump" : "· no")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.near)
            }
            Spacer()
            if let notice = host.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Legend()
        }
    }

    /// What the targets' marks mean.
    private struct Legend: View {
        var body: some View {
            HStack(spacing: 10) {
                swatch(Theme.near.opacity(0.4), "one step away")
                swatch(Theme.borrowed.opacity(0.5), "borrowed", dashed: true)
                swatch(Theme.chord, "aimed")
            }
        }

        private func swatch(_ color: Color, _ name: String, dashed: Bool = false) -> some View {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                    .background(color.opacity(dashed ? 0 : 0.6), in: RoundedRectangle(cornerRadius: 3))
                    .frame(width: 12, height: 10)
                Text(name).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// The menu, over the stage: a row for each setting, and the sound library.
struct MenuView: View {
    @Environment(DeskHost.self) private var host
    let menu: DeskMenu

    var body: some View {
        let desk = host.desk
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { host.toggleMenu() }
            if let library = menu.library {
                LibraryView(library: library, catalog: desk.catalog,
                            chosen: library.line == .chord ? desk.settings.chordSound : desk.settings.lineSound)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Caption(control: "Start", title: "Menu")
                        .padding(.bottom, 8)
                    ForEach(DeskMenu.Row.allCases, id: \.self) { row in
                        HStack {
                            Text(row.name)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            if row == menu.row, ![.saveMIDI].contains(row) { Text("◀").foregroundStyle(Theme.faint) }
                            Text(desk.value(of: row))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            if row == menu.row, ![.saveMIDI].contains(row) { Text("▶").foregroundStyle(Theme.faint) }
                        }
                        .foregroundStyle(row == menu.row ? Color.black : Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(row == menu.row ? Theme.chord : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text("↑ ↓ choose · ← → change · A open · B close")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .padding(.top, 10)
                }
                .frame(width: 420)
                .panel()
            }
        }
    }
}

/// The sound library: a column for each category, its sounds down it. A
/// sound is heard as it is reached.
struct LibraryView: View {
    let library: DeskMenu.Library
    let catalog: SoundCatalog
    let chosen: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption(control: library.line == .chord ? "Chords" : "Line", title: "Sound library")
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(catalog.categories.enumerated()), id: \.offset) { index, category in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6)
                            .foregroundStyle(index == library.category ? Theme.chord : Theme.faint)
                            .padding(.bottom, 4)
                        ForEach(category.sounds, id: \.id) { sound in
                            Text(sound.name)
                                .font(.system(size: 13, weight: sound.id == chosen ? .semibold : .regular))
                                .foregroundStyle(sound.id == chosen ? Color.black : Theme.text)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(minWidth: 120, alignment: .leading)
                                .background(sound.id == chosen ? Theme.chord : Theme.raised.opacity(index == library.category ? 0.9 : 0.4),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
            Text("← → category · ↑ ↓ sound, heard as you go · A or B back")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
        .panel()
    }
}

/// The consonance guard while it is on: its mode, and in the run the notes
/// it has heard.
struct GuardChip: View {
    let consonance: ConsonanceGuard

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 10))
            Text(consonance.mode.name + (consonance.inKey ? " · in key" : ""))
                .font(.system(size: 11, weight: .semibold))
            if consonance.mode == .run {
                Text(pool).font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.75)
            }
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.near, in: Capsule())
    }

    private var pool: String {
        let notes = consonance.pool.sorted().map { PitchClass(rawValue: $0)!.name }
        return notes.isEmpty ? "nothing heard yet" : notes.joined(separator: " ")
    }
}
