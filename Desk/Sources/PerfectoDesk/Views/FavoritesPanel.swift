import DeskCore
import MusicTheoryCore
import SwiftUI

/// The column beside the stage: what each control does, or the favorites.
struct SideColumn: View {
    @Environment(DeskHost.self) private var host
    @State private var tab = Tab.controls

    enum Tab: String, CaseIterable {
        case controls = "Controls"
        case favorites = "Favorites"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .controls:
                HandView(legend: host.desk.legend, frame: host.frame, isKeyboard: !host.hasController)
            case .favorites:
                FavoritesPanel()
            }
        }
    }
}

/// Favorite colorations: the tables, which one is played and which is the
/// key's own, and the colors pinned to each chord of the key in it.
struct FavoritesPanel: View {
    @Environment(DeskHost.self) private var host
    @State private var editingName = ""
    @State private var editing: Int?

    var body: some View {
        let desk = host.desk
        let favorites = desk.settings.favorites
        let key = desk.settings.key
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Caption(control: "Tables", title: "The one played is lit")
                VStack(spacing: 4) {
                    ForEach(Array(favorites.tables.enumerated()), id: \.offset) { index, table in
                        tableRow(index, table, isActive: index == favorites.active,
                                 isDefault: favorites.defaultTable(for: key) == table.name)
                    }
                }
                HStack {
                    Button("New table") { host.addTable() }
                    Spacer()
                    Button("Remove") { host.removeTable(favorites.active) }
                        .disabled(favorites.tables.count < 2)
                }
                .controlSize(.small)
                Toggle("Play \(favorites.table.name) whenever the key is \(desk.settings.summary)",
                       isOn: Binding(get: { favorites.defaultTable(for: key) == favorites.table.name },
                                     set: { host.setKeyDefault($0) }))
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                Divider()
                Caption(control: desk.settings.summary, title: "Pinned in \(favorites.table.name)")
                Button {
                    host.pinPlayed()
                } label: {
                    Label(desk.pinnable.map { "Pin \($0.name)" } ?? "Strike a chord to pin it", systemImage: "pin")
                        .frame(maxWidth: .infinity)
                }
                .disabled(desk.pinnable == nil)
                ForEach(Degree.allCases, id: \.self) { degree in
                    degreeRow(degree, colors: favorites.colors(key, degree), key: key)
                }
                Text("In Twin Rings, hold Y: the right stick plays the chord's favorites (flick keeps, hold plays), Y + A pins the chord you're on, Y + X unpins the one aimed at.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tableRow(_ index: Int, _ table: FavoriteTable, isActive: Bool, isDefault: Bool) -> some View {
        HStack(spacing: 8) {
            if editing == index {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        host.renameTable(index, to: editingName)
                        editing = nil
                    }
            } else {
                Text(table.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black : Theme.text)
                if isDefault {
                    Text("key's own").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isActive ? Color.black.opacity(0.6) : Theme.chord)
                }
                Spacer()
                Text("\(table.pins.reduce(0) { $0 + $1.colors.count })")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? Color.black.opacity(0.6) : Theme.faint)
                Button {
                    editingName = table.name
                    editing = index
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.black.opacity(0.7) : Theme.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isActive ? Theme.chord : Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { host.playTable(index) }
    }

    private func degreeRow(_ degree: Degree, colors: [ChordColor], key: Key) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(numeral(degree, in: key))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, alignment: .leading)
            if colors.isEmpty {
                Text("—").foregroundStyle(Theme.faint).font(.system(size: 12))
            } else {
                FlowChips(names: colors.map { DeskChord(key: key, degree: degree, color: $0).name }) { index in
                    host.unpin(degree, at: index)
                }
            }
        }
    }
}

/// Pinned chords as chips that wrap, each with a button to unpin it.
struct FlowChips: View {
    let names: [String]
    let remove: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button {
                        remove(index)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
