import SwiftUI

/// Flags on the score: moments marked while listening or stepping through
/// it, each with a note if one was written, seen in every view.
///
/// A flag is put on at the playhead by the transport's Flag button, which
/// asks for a note (or none); the flags the playhead stands on are shown
/// over the score's bar (`PracticeFlagLine`), every flag is listed by the
/// Flags button (`PracticeFlagsList`), and the bar marks each where it is.

extension Color {
    /// What a flag is drawn in, apart from the hands' colors the runs have.
    static let practiceFlag = Color(red: 1, green: 0.8, blue: 0.25)
}

/// The note of a flag being written: of a flag to put on at a moment, or of
/// one already on.
enum FlagNoting: Equatable {
    case new(time: Double)
    case existing(FlagID)
}

extension View {
    /// An alert that writes the note of the flag `noting` holds, while it
    /// holds one: a new flag is put on only when it is added.
    func notingFlag(_ noting: Binding<FlagNoting?>, in practice: ScorePracticeState) -> some View {
        modifier(FlagNoteAlert(noting: noting, practice: practice))
    }
}

private struct FlagNoteAlert: ViewModifier {
    @Binding var noting: FlagNoting?
    let practice: ScorePracticeState
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { noting != nil }, set: { if !$0 { noting = nil } })) {
                TextField("Note (optional)", text: $draft)
                switch noting {
                case let .new(time):
                    Button("Add") { practice.addFlag(at: time, note: draft) }
                        .keyboardShortcut(.defaultAction)
                case let .existing(id):
                    Button("Save") { practice.note(id, draft) }
                        .keyboardShortcut(.defaultAction)
                    Button("Delete flag", role: .destructive) { practice.deleteFlag(id) }
                case nil:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isNew ? "What is here? Leave it empty to flag the moment alone."
                           : "Leave it empty to keep the flag with no note.")
            }
            .onChange(of: noting) { _, noting in
                if case let .existing(id) = noting { draft = practice.flag(id)?.note ?? "" } else { draft = "" }
            }
    }

    private var isNew: Bool {
        if case .new = noting { return true }
        return false
    }

    private var title: String {
        switch noting {
        case let .new(time):
            return "Flag \(practice.score.map { "bar \($0.bar(at: time)), " } ?? "")\(PracticeTime.text(time))"
        case let .existing(id):
            guard let flag = practice.flag(id) else { return "Flag" }
            return "Flag \(practice.bar(of: flag).lowercased()), \(PracticeTime.text(flag.time))"
        case nil:
            return ""
        }
    }
}

/// What the transport's Flag button does with the playhead at `time`: puts
/// a flag on there, or notes again the one the hands shown already have
/// there.
extension ScorePracticeState {
    func flagNoting(at time: Double) -> FlagNoting {
        ownFlag(at: time).map { .existing($0.id) } ?? .new(time: time)
    }
}

/// The flags at the step the playhead stands on, over the score's bar:
/// each with its note and where it was put on, to note again or take away.
/// As the score plays, each flag's note is seen as its step is heard.
struct PracticeFlagLine: View {
    @Environment(PerformanceState.self) private var state
    @State private var noting: FlagNoting?

    var body: some View {
        let practice = state.practice
        TimelineView(.animation(paused: !practice.isPlaying)) { _ in
            let here = practice.flags(at: practice.currentTime)
            if !here.isEmpty {
                VStack(spacing: 4) {
                    ForEach(here) { row($0) }
                }
            }
        }
        .notingFlag($noting, in: practice)
    }

    private func row(_ flag: ScoreFlag) -> some View {
        let practice = state.practice
        return HStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.practiceFlag)
                .accessibilityHidden(true)
            Text(flag.note ?? "No note")
                .font(.system(size: 13, weight: flag.note == nil ? .regular : .semibold))
                .foregroundStyle(flag.note == nil ? Color(white: 0.5) : Color(white: 0.9))
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("\(flag.hands.short) · \(practice.bar(of: flag))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .fixedSize()
            Button { noting = .existing(flag.id) } label: {
                Image(systemName: "pencil").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Note on this flag")
            .help("Write, change or take away this flag's note")
            Button { practice.deleteFlag(flag.id) } label: {
                Image(systemName: "trash").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete this flag")
            .help("Take this flag off the score (Undo brings it back)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.practiceFlag.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.practiceFlag.opacity(0.35), lineWidth: 1))
    }
}

/// Every flag on the score, in its order: its note, its bar, the view it
/// was put on in and its moment. A row brings the playhead to its flag; its
/// pencil notes it, and its trash, a swipe or its menu takes it away.
struct PracticeFlagsList: View {
    @Environment(PerformanceState.self) private var state
    @Binding var isShown: Bool
    @State private var noting: FlagNoting?

    var body: some View {
        let practice = state.practice
        NavigationStack {
            List {
                if practice.flags.isEmpty {
                    Text("No flags yet. Flag a moment with the Flag button, as the score plays or as you step through it a note at a time.")
                        .foregroundStyle(.secondary)
                }
                ForEach(practice.flags) { flag in
                    row(flag)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                practice.deleteFlag(flag.id)
                            }
                        }
                        .contextMenu {
                            Button("Note…", systemImage: "pencil") { noting = .existing(flag.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { practice.deleteFlag(flag.id) }
                        }
                }
            }
            .navigationTitle("Flags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShown = false }
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 380, minHeight: 420, idealHeight: 560)
        .presentationDetents([.medium, .large])
        .notingFlag($noting, in: practice)
    }

    private func row(_ flag: ScoreFlag) -> some View {
        let practice = state.practice
        return HStack(spacing: 8) {
            Button {
                practice.goTo(flag: flag.id)
                isShown = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Color.practiceFlag)
                        .accessibilityHidden(true)
                    Text(flag.note ?? "No note")
                        .foregroundStyle(flag.note == nil ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(practice.bar(of: flag)) · \(flag.hands.short)")
                        Text(PracticeTime.text(flag.time))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bring the playhead to this flag")
            Button { noting = .existing(flag.id) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Write, change or take away this flag's note")
            .accessibilityLabel("Note on the flag at \(PracticeTime.text(flag.time))")
            Button(role: .destructive) { practice.deleteFlag(flag.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Take this flag off the score (Undo brings it back)")
            .accessibilityLabel("Delete the flag at \(PracticeTime.text(flag.time))")
        }
    }
}
