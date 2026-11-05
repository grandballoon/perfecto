import SwiftUI
import UniformTypeIdentifiers

/// The piano with the whole screen: score practice around it, and the
/// piano itself in the middle of the screen, where the eye rests, not
/// along an edge.
///
/// Above the piano are the piece and the runs of the hands shown (one
/// hand, or both), to choose and watch, and while a run is being made or
/// edited, what takes it a note further at either end and keeps it. Below
/// the piano is the whole score as a bar, the runs laid along it (the run
/// being edited is dragged along it), and what plays it.
///
/// The keys light in turn as the score plays, each as it is struck,
/// with the hand's next keys marked: a run is seen as the hand plays it,
/// key by key, not as notes falling toward the keys.
///
/// Or the learner taps the run on the keys themselves, note by note
/// (`PracticeTapBar`): each tap is told right or wrong, and the next note
/// is marked or left to memory, switched at any moment.
struct ScorePracticeView: View {
    @Environment(PerformanceState.self) private var state

    @State private var isImporting = false

    /// The keys are never longer than this share of the screen's height.
    private static let pianoShare: CGFloat = 0.42
    private static let margin: CGFloat = 16

    static let scoreTypes: [UTType] = [
        .midi,
        UTType(importedAs: "com.recordare.musicxml.compressed", conformingTo: .zip),
        UTType(importedAs: "com.recordare.musicxml.uncompressed", conformingTo: .xml),
        .xml,
    ]

    var body: some View {
        let practice = state.practice
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    header
                    if practice.piece != nil {
                        PracticeRunsBar()
                        if practice.isEditing { PracticeRunEditor() }
                        if practice.isTapping { PracticeTapBar() }
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)

                TimelineView(.animation(paused: !practice.isPlaying)) { _ in
                    PianoView(isExpanded: true, practice: practice.lights(at: practice.currentTime),
                              onKeyDown: practice.isTapping ? { practice.press($0) } : nil,
                              onKeyUp: { practice.release($0) },
                              tap: practice.isTapping ? practice.lastTap : nil)
                        .animation(.easeOut(duration: 0.12), value: practice.lastTap)
                }
                .frame(height: PianoKeys.length(
                    forWidth: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                    span: state.piano.span, longest: geo.size.height * Self.pianoShare))
                .ignoresSafeArea(edges: .horizontal)
                .padding(.vertical, 12)

                VStack(spacing: 10) {
                    if practice.piece == nil {
                        emptyMessage
                    } else {
                        PracticeOverview()
                        PracticeTransport()
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, 8)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await practice.appear() }
        // Shrunk by a double tap on the keys, too: nothing plays unseen.
        .onDisappear { practice.stop() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.scoreTypes) { result in
            guard case let .success(url) = result else { return }
            practice.importScore(from: url)
        }
        .alert(practice.failure ?? "", isPresented: Binding(
            get: { practice.failure != nil }, set: { if !$0 { practice.failure = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: – Header

    private var header: some View {
        let practice = state.practice
        return HStack(spacing: 10) {
            Button {
                practice.stop()
                withAnimation(.easeOut(duration: 0.25)) { state.piano.isExpanded = false }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shrink the piano")
            .help("Shrink the piano back to a strip along the bottom of the play screen")

            pieceMenu

            Spacer(minLength: 0)

            if practice.piece != nil {
                undoButtons
            }
            if practice.handsShown.count > 1 {
                HStack(spacing: 4) {
                    ForEach(practice.handsShown, id: \.self) { hands in
                        Button { practice.show(hands) } label: {
                            Text(hands.short)
                                .practiceChit(fill: practice.hands == hands ? hands.color : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hands.name)
                        .accessibilityAddTraits(practice.hands == hands ? .isSelected : [])
                        .help(hands == .both
                              ? "Show the runs of both hands together and light both hands' keys"
                              : "Show the \(hands.name.lowercased())'s runs and light its keys alone")
                    }
                }
                .disabled(practice.isEditing)
                .opacity(practice.isEditing ? 0.4 : 1)
            }
            if practice.piece != nil {
                Button { withAnimation(.easeOut(duration: 0.2)) { practice.fitPiano() } } label: {
                    Image(systemName: "arrow.left.and.right").practiceChit()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fit the piano to the runs")
                .help("Bring the piano to the keys of the runs being watched")
            }
        }
    }

    private var undoButtons: some View {
        let practice = state.practice
        return HStack(spacing: 4) {
            Button { practice.undo() } label: {
                Image(systemName: "arrow.uturn.backward").practiceChit()
            }
            .buttonStyle(.plain)
            .disabled(!practice.canUndo || practice.isEditing)
            .opacity(practice.canUndo && !practice.isEditing ? 1 : 0.4)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo")
            .help("Undo the last change to the runs (⌘Z)")

            Button { practice.redo() } label: {
                Image(systemName: "arrow.uturn.forward").practiceChit()
            }
            .buttonStyle(.plain)
            .disabled(!practice.canRedo || practice.isEditing)
            .opacity(practice.canRedo && !practice.isEditing ? 1 : 0.4)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityLabel("Redo")
            .help("Redo the change undone (⇧⌘Z)")
        }
    }

    private var pieceMenu: some View {
        let practice = state.practice
        return Menu {
            ForEach(practice.pieces) { piece in
                Button { Task { await practice.open(piece) } } label: {
                    if piece.id == practice.piece?.id {
                        Label(piece.title, systemImage: "checkmark")
                    } else {
                        Text(piece.title)
                    }
                }
            }
            Divider()
            Button("Open a score…", systemImage: "doc.badge.plus") { isImporting = true }
            if practice.piece != nil {
                Divider()
                Button("Close", systemImage: "xmark") { practice.closePiece() }
                if let piece = practice.piece {
                    Button("Delete “\(piece.title)”", systemImage: "trash", role: .destructive) {
                        practice.delete(piece)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(practice.piece?.title ?? "Score practice")
                    .lineLimit(1)
                if practice.isInCloud {
                    // The pieces are shared with the other device.
                    Image(systemName: "icloud")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.5))
                        .accessibilityLabel("Kept in iCloud")
                        .help("Kept in iCloud, shared with your other devices")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(white: 0.9))
        }
        .help("Pieces: open another, open a score, close the piece, or delete it")
    }

    // MARK: – No piece yet

    private var emptyMessage: some View {
        VStack(spacing: 12) {
            Text(state.practice.pieces.isEmpty
                 ? "Open a MIDI file (.mid) or a MusicXML score (.mxl or .musicxml), then keep runs of it, of one hand or both, and watch them on the keys as the score plays."
                 : "Choose a piece from the menu above, or open another score.")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            importButton("Open a score", systemImage: "doc.badge.plus") { isImporting = true }
        }
    }

    private func importButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.orange))
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Runs

/// The runs of the hands shown: the whole piece, and a chit for each run
/// kept, tapped to watch it (several are watched in turn), and pressed
/// and held or right-clicked to edit, name or delete it. Beside them, every
/// run of every view, editing the one run chosen, and a new run.
///
/// A run is changed only in editing, which is asked for and then saved,
/// so a touch meant for watching never moves one. While a run is edited,
/// the others wait.
struct PracticeRunsBar: View {
    @Environment(PerformanceState.self) private var state
    @State private var isShowingAll = false
    @State private var renaming: RunID?

    var body: some View {
        let practice = state.practice
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    wholePiece
                    ForEach(practice.shownRuns) { run in
                        chit(run)
                    }
                }
            }
            .disabled(practice.isEditing)
            .opacity(practice.isEditing ? 0.4 : 1)
            Button { isShowingAll = true } label: {
                Image(systemName: "list.bullet").practiceChit()
            }
            .buttonStyle(.plain)
            .disabled(practice.isEditing)
            .opacity(practice.isEditing ? 0.4 : 1)
            .accessibilityLabel("All runs")
            .help("See every run of every hand, edit, name or delete them, and go to one")
            .popover(isPresented: $isShowingAll) {
                PracticeAllRuns(isShown: $isShowingAll)
                    .environment(state)
            }
            if !practice.isEditing {
                let chosen = practice.selection.count == 1 ? practice.selection.first : nil
                Button { if let chosen { practice.edit(chosen) } } label: {
                    Image(systemName: "slider.horizontal.below.rectangle").practiceChit()
                }
                .buttonStyle(.plain)
                .disabled(chosen == nil)
                .opacity(chosen == nil ? 0.4 : 1)
                .accessibilityLabel("Edit the run")
                .help(chosen == nil ? "Choose one run to edit it" : "Edit the run chosen: move it, take in more notes, then save")
                Button { practice.startNewRun() } label: {
                    Label("Run", systemImage: "plus").practiceChit()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New run")
                .help("Make a new run of the \(practice.hands.name.lowercased()), from the bar at the playhead")
            }
        }
        .renamingRun($renaming, in: practice)
    }

    private var wholePiece: some View {
        let practice = state.practice
        let isWatched = practice.selection.isEmpty
        return Button { practice.clearSelection() } label: {
            Text("Whole piece")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .runChit(isChosen: isWatched, color: practice.hands.color)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isWatched ? .isSelected : [])
        .help("Watch the whole piece of the \(practice.hands.name.lowercased()), choosing no run")
    }

    private func chit(_ run: PracticeRun) -> some View {
        let practice = state.practice
        let isChosen = practice.selection.contains(run.id)
        return Button { practice.toggle(run.id) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(practice.title(of: run))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                let place = run.name == nil ? nil : practice.bars(of: run)
                let time = practice.span(of: run).map { PracticeTime.text($0.lowerBound) }
                Text([place, time].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.7)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .runChit(isChosen: isChosen, color: run.passage.hands.color)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .help(isChosen ? "Stop watching this run" : "Watch this run (choose several to watch them in turn)")
        .contextMenu { RunActions(run: run, renaming: $renaming) }
    }
}

/// The run being made or edited: where it is, a note more before it or
/// after it, and keeping it or leaving it as it was. It is moved by
/// dragging it along the score's bar.
struct PracticeRunEditor: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let practice = state.practice
        let color = practice.hands.color
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.9))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            let draft = practice.draft
            let count = practice.score.map { $0.steps(practice.hands).count } ?? 0
            let canShrink = draft.map { $0.first < $0.last } ?? false
            edge("Start",
                 fewer: (practice.shrinkDraftStart, canShrink, "One note fewer at the start"),
                 more: (practice.extendDraftStart, (draft?.first ?? 0) > 0, "One more note before the run"))
            edge("End",
                 fewer: (practice.shrinkDraftEnd, canShrink, "One note fewer at the end"),
                 more: (practice.extendDraftEnd, (draft?.last ?? count) < count - 1, "One more note after the run"))
            Button("Cancel") { practice.cancelDraft() }
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.7))
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, 4)
                .help(practice.editing == nil ? "Make no run" : "Leave the run as it was")
            Button { practice.saveDraft() } label: {
                Text("Save").practiceChit(fill: color)
            }
            .buttonStyle(.plain)
            .help(practice.editing == nil ? "Keep this run and watch it" : "Keep the run as it is now")
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
    }

    /// One end of the run: a note fewer there, or a note more.
    private func edge(_ name: String,
                      fewer: (action: () -> Void, isAble: Bool, help: String),
                      more: (action: () -> Void, isAble: Bool, help: String)) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.55))
            ForEach([(fewer, "minus"), (more, "plus")], id: \.1) { button, symbol in
                Button(action: button.action) {
                    Image(systemName: symbol).practiceChit()
                }
                .buttonStyle(.plain)
                .disabled(!button.isAble)
                .opacity(button.isAble ? 1 : 0.4)
                .accessibilityLabel(button.help)
                .help(button.help)
            }
        }
    }

    private var title: String {
        let practice = state.practice
        guard let id = practice.editing, let run = practice.practice?.run(id) else {
            return "New run · \(practice.hands.name)"
        }
        return "Editing \(practice.title(of: run))"
    }

    private var detail: String {
        let practice = state.practice
        guard let draft = practice.draft, let score = practice.score else { return "" }
        let count = draft.steps.count
        return "\(score.bars(of: draft.span(in: score))) · \(count) note\(count == 1 ? "" : "s") · drag it along the bar below"
    }
}

/// What can be done to a run from its menu: edit it, name it, or delete it.
private struct RunActions: View {
    @Environment(PerformanceState.self) private var state
    let run: PracticeRun
    @Binding var renaming: RunID?

    var body: some View {
        Button("Edit", systemImage: "slider.horizontal.below.rectangle") { state.practice.edit(run.id) }
        Button("Name…", systemImage: "pencil") { renaming = run.id }
        Button("Delete", systemImage: "trash", role: .destructive) { state.practice.delete(run.id) }
    }
}

extension View {
    /// A run's chit: filled in its hands' color while it is chosen.
    fileprivate func runChit(isChosen: Bool, color: Color) -> some View {
        self
            .foregroundStyle(isChosen ? Color.black : Color(white: 0.85))
            .background(RoundedRectangle(cornerRadius: 8).fill(isChosen ? color : Color(white: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isChosen ? color : Color(white: 0.25), lineWidth: 1))
    }

    /// An alert that names the run `renaming` holds, while it holds one.
    func renamingRun(_ renaming: Binding<RunID?>, in practice: ScorePracticeState) -> some View {
        modifier(RenameRunAlert(renaming: renaming, practice: practice))
    }
}

private struct RenameRunAlert: ViewModifier {
    @Binding var renaming: RunID?
    let practice: ScorePracticeState
    @State private var draft = ""

    func body(content: Content) -> some View {
        let run = renaming.flatMap { practice.practice?.run($0) }
        content
            .alert("Name \(run.map(practice.bars(of:)) ?? "the run")",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $draft)
                Button("Save") {
                    if let renaming { practice.rename(renaming, to: draft) }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Leave it empty to go by its bars.")
            }
            .onChange(of: renaming) { _, id in
                draft = id.flatMap { practice.practice?.run($0)?.name } ?? ""
            }
    }
}

/// Every run, under each view of the score (each hand alone, both
/// together): its name, its bars, how many steps it has and where it is
/// heard. A row goes to its run (`goTo`); its pencil names it, and a swipe
/// or its menu deletes it.
struct PracticeAllRuns: View {
    @Environment(PerformanceState.self) private var state
    @Binding var isShown: Bool
    @State private var renaming: RunID?

    var body: some View {
        let practice = state.practice
        NavigationStack {
            List {
                ForEach(practice.allRuns, id: \.hands) { hands, runs in
                    Section(hands.name) {
                        if runs.isEmpty {
                            Text("No runs yet")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(runs) { run in
                            row(run)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        practice.delete(run.id)
                                    }
                                }
                                .contextMenu { RunActions(run: run, renaming: $renaming) }
                        }
                    }
                }
            }
            .navigationTitle("All runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShown = false }
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 380, minHeight: 420, idealHeight: 560)
        .presentationDetents([.medium, .large])
        // A run put into editing is edited on the bar: the list makes way.
        .onChange(of: practice.isEditing) { _, isEditing in if isEditing { isShown = false } }
        .renamingRun($renaming, in: practice)
    }

    private func row(_ run: PracticeRun) -> some View {
        let practice = state.practice
        let isWatched = practice.selection.contains(run.id)
        let steps = run.passage.steps.count
        return HStack(spacing: 8) {
            Button {
                practice.goTo(run.id)
                isShown = false
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isWatched ? run.passage.hands.color : Color.clear)
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(practice.title(of: run)).lineLimit(1)
                        if run.name != nil {
                            Text(practice.bars(of: run))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(steps) step\(steps == 1 ? "" : "s")")
                        if let span = practice.span(of: run) {
                            Text("\(PracticeTime.text(span.lowerBound))–\(PracticeTime.text(span.upperBound))")
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to \(practice.title(of: run)) and watch it")
            Button { renaming = run.id } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Name this run")
            .accessibilityLabel("Name \(practice.title(of: run))")
            Button(role: .destructive) { practice.delete(run.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this run (Undo brings it back)")
            .accessibilityLabel("Delete \(practice.title(of: run))")
        }
    }
}

// MARK: – Playing

/// What plays the score: skip back or on, and play the runs watched from
/// where the playhead stands, once or over again.
struct PracticeTransport: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var practice = state.practice
        HStack(spacing: 8) {
            Button { practice.skip(by: -ScorePracticeState.skipSeconds) } label: {
                Image(systemName: "gobackward.5").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back 5 seconds")
            .help("Back 5 seconds, playing on if it was playing")

            Button { practice.playOrStop() } label: {
                Image(systemName: practice.isPlaying ? "stop.fill" : "play.fill")
                    .practiceChit(fill: practice.isPlaying ? Color.orange : nil, width: 44)
            }
            .buttonStyle(.plain)
            .hotkeyTip(.playStop)
            .accessibilityLabel(practice.isPlaying ? "Stop" : "Play the runs")
            .help(practice.isPlaying ? "Stop" : "Play the runs watched from the playhead (or from the next of them)")

            Button { practice.skip(by: ScorePracticeState.skipSeconds) } label: {
                Image(systemName: "goforward.5").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forward 5 seconds")
            .help("Forward 5 seconds, playing on if it was playing")

            Button { practice.repeats.toggle() } label: {
                Image(systemName: "repeat")
                    .practiceChit(fill: practice.repeats ? Color(white: 0.85) : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .help(practice.repeats ? "Repeat is on: the runs play over and over" : "Repeat is off: the runs play once")
            .accessibilityAddTraits(practice.repeats ? .isSelected : [])

            Button { practice.toggleTapping() } label: {
                Label("Tap", systemImage: "hand.tap")
                    .practiceChit(fill: practice.isTapping ? Color(white: 0.85) : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tap the run")
            .accessibilityAddTraits(practice.isTapping ? .isSelected : [])
            .help(practice.isTapping ? "Stop tapping and go back to watching"
                                     : "Tap the runs watched on the keys yourself, note by note, told right or wrong")

            Spacer(minLength: 0)
        }
    }
}

// MARK: – Tapping

/// Tapping a run on the keys: what the last tap was, how far the learner
/// has got, whether the next note is marked, and beginning again.
///
/// Every tap is said here in words as well as marked on its key, and a
/// wrong one is felt as well, so it is noticed without looking away from
/// the keys.
struct PracticeTapBar: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var practice = state.practice
        let color = message.isWrong ? PianoView.wrongColor
                  : practice.lastTap == nil ? Color(white: 0.9) : PianoView.rightColor
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(2)
                Text(progress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)

            Button { practice.showsNextNote.toggle() } label: {
                Label("Next note", systemImage: practice.showsNextNote ? "eye" : "eye.slash")
                    .practiceChit(fill: practice.showsNextNote ? Color(white: 0.85) : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the next note")
            .accessibilityAddTraits(practice.showsNextNote ? .isSelected : [])
            .help(practice.showsNextNote ? "The next note is marked on its key: tap to play from memory instead"
                                         : "Playing from memory: tap to mark the next note on its key")

            Button { practice.restartTapping() } label: {
                Image(systemName: "arrow.counterclockwise").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Begin again")
            .help("Begin the run again from its first note")

            Button { practice.stopTapping() } label: {
                Text("Done").practiceChit()
            }
            .buttonStyle(.plain)
            .help("Stop tapping and go back to watching")
        }
        .sensoryFeedback(trigger: practice.lastTap) { _, tap in
            guard let tap else { return nil }
            switch tap.outcome {
            case .wrong:   return .error
            case .passed:  return .success
            default:       return .impact(weight: .light)
            }
        }
        .onChange(of: practice.lastTap) { _, tap in
            guard tap != nil else { return }
            AccessibilityNotification.Announcement(message.text).post()
        }
    }

    private var message: (text: String, symbol: String, isWrong: Bool) {
        let practice = state.practice
        guard let tap = practice.lastTap else {
            return (practice.showsNextNote ? "Tap the marked key" : "Tap the run from memory",
                    "hand.tap", false)
        }
        let name = pitchName(tap.pitch)
        switch tap.outcome {
        case .right:
            let more = practice.drill?.remaining.count ?? 0
            return ("Right, \(name): \(more) more of this chord", "checkmark.circle.fill", false)
        case .stepDone:
            return ("Right, \(name)", "checkmark.circle.fill", false)
        case let .passed(mistakes):
            let how = mistakes == 0 ? "with no wrong notes" : "with \(mistakes) wrong note\(mistakes == 1 ? "" : "s")"
            return ("Run done \(how). Again from the start", "star.circle.fill", false)
        case .wrong:
            return ("Wrong note, \(name): try again", "xmark.circle.fill", true)
        }
    }

    private var progress: String {
        guard let drill = state.practice.drill else { return "" }
        var text = "Step \(drill.index + 1) of \(drill.steps.count)"
        if drill.mistakes > 0 { text += " · \(drill.mistakes) wrong" }
        if drill.passes > 0 { text += " · \(drill.passes) run\(drill.passes == 1 ? "" : "s") done" }
        return text
    }
}

enum PracticeTime {
    /// "1:23.4".
    static func text(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

extension View {
    /// A small button's face, as the practice screen draws them.
    func practiceChit(fill: Color? = nil, width: CGFloat? = nil) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(fill == nil ? Color(white: 0.85) : Color.black)
            .frame(minWidth: width ?? 32, minHeight: 30)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill ?? Color(white: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fill ?? Color(white: 0.25), lineWidth: 1))
    }
}
