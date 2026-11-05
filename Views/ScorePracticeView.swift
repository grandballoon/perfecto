import SwiftUI
import UniformTypeIdentifiers

/// The piano with the whole screen: score practice around it, and the
/// piano itself in the middle of the screen, where the eye rests, not
/// along an edge.
///
/// Above the piano are the piece and the runs of the hand shown: the runs
/// of the run in focus, to choose and watch or to open and cut further,
/// and while cutting, that run's steps, each lit on the piano as it is
/// tapped. Below it is the recording, the runs laid along it with their
/// edges to drag, and what plays it.
///
/// The keys light in turn as the recording plays, each as it is struck,
/// with the hand's next keys marked: a run is seen as the hand plays it,
/// key by key, not as notes falling toward the keys.
struct ScorePracticeView: View {
    @Environment(PerformanceState.self) private var state

    private enum Importing {
        case score
        case recording
    }

    /// What the file picker is choosing. It is kept after the picker
    /// closes, because the picker closes before it hands over the file
    /// chosen, and the file is taken as what was asked for.
    @State private var importing = Importing.score
    @State private var isImporting = false

    /// The keys are never longer than this share of the screen's height.
    private static let pianoShare: CGFloat = 0.42
    private static let margin: CGFloat = 16

    static let scoreTypes: [UTType] = [
        UTType(importedAs: "com.recordare.musicxml.compressed", conformingTo: .zip),
        UTType(importedAs: "com.recordare.musicxml.uncompressed", conformingTo: .xml),
        .xml,
        .midi,
    ]

    var body: some View {
        let practice = state.practice
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    header
                    if practice.piece != nil {
                        PracticeRunsBar()
                        if practice.isCutting { PracticeStepsStrip() }
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)

                TimelineView(.animation(paused: practice.listening == nil)) { _ in
                    PianoView(isExpanded: true, practice: practice.lights(at: practice.currentTime))
                }
                .frame(height: PianoKeys.length(
                    forWidth: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                    span: state.piano.span, longest: geo.size.height * Self.pianoShare))
                .ignoresSafeArea(edges: .horizontal)
                .padding(.vertical, 12)

                VStack(spacing: 10) {
                    if practice.piece == nil {
                        emptyMessage
                    } else if practice.hasRecording {
                        PracticeTimelines()
                        PracticeOverview()
                        PracticeNotesRow()
                        PracticeTransport()
                    } else {
                        importButton("Add a recording of it", systemImage: "waveform") { pick(.recording) }
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
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: importing == .recording ? [.audio] : Self.scoreTypes) { result in
            guard case let .success(url) = result else { return }
            switch importing {
            case .score:     practice.importScore(from: url)
            case .recording: practice.importRecording(from: url)
            }
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

            if practice.hands.count > 1 {
                HStack(spacing: 4) {
                    ForEach(practice.hands, id: \.self) { hand in
                        Button { practice.show(hand) } label: {
                            Text(hand == .right ? "RH" : "LH")
                                .practiceChit(fill: practice.hand == hand ? hand.color : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hand.name)
                        .help("Show the \(hand.name.lowercased())'s runs and light its keys")
                    }
                }
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
            Button("Open a score…", systemImage: "doc.badge.plus") { pick(.score) }
            if practice.piece != nil {
                Button(practice.hasRecording ? "Replace the recording…" : "Add a recording…",
                       systemImage: "waveform") { pick(.recording) }
                if practice.hasRecording {
                    Button("Match again", systemImage: "wand.and.stars") { practice.matchAgain() }
                    if !(practice.practice?.anchors.isEmpty ?? true) {
                        Button("Clear pins and match again", systemImage: "pin.slash") {
                            practice.clearPinsAndMatch()
                        }
                    }
                }
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
                if practice.isMatching {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color(white: 0.6))
                        .accessibilityLabel("Matching the recording")
                        .help("Matching the recording to the score…")
                }
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
        .help("Pieces: open another, open a score, add or replace the recording, match it again, close the piece, or delete it")
    }

    // MARK: – No piece yet

    private var emptyMessage: some View {
        VStack(spacing: 12) {
            Text(state.practice.pieces.isEmpty
                 ? "Open a score in MusicXML (.mxl or .musicxml) or MIDI (.mid) and add a recording of it, then dice each hand into runs and watch them on the keys as the recording plays."
                 : "Choose a piece from the menu above, or open another score.")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            importButton("Open a score", systemImage: "doc.badge.plus") { pick(.score) }
        }
    }

    private func pick(_ kind: Importing) {
        importing = kind
        isImporting = true
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

/// The runs of the run in focus, for the hand shown: the way down to it,
/// to go back up, and a chit for each of its runs, tapped to watch it or
/// opened to show its own runs and cut it further.
struct PracticeRunsBar: View {
    @Environment(PerformanceState.self) private var state
    @State private var isShowingAll = false
    @State private var renaming: RunID?

    var body: some View {
        let practice = state.practice
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(practice.focusPath.enumerated()), id: \.element.id) { depth, run in
                    if depth > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(white: 0.4))
                    }
                    Button { practice.focus(on: run.id) } label: {
                        Text(practice.title(of: run.id))
                            .font(.system(size: 12, weight: depth == practice.focusPath.count - 1 ? .semibold : .regular))
                            .foregroundStyle(depth == practice.focusPath.count - 1 ? Color(white: 0.9) : Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Go back to run \(practice.label(of: run.id)) and its runs")
                    .contextMenu { renameButton(run.id) }
                }
                Spacer(minLength: 0)
                if !practice.selection.isEmpty {
                    Button("Clear") { practice.clearSelection() }
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.6))
                        .buttonStyle(.plain)
                        .help("Unchoose every run, so the whole run in focus is watched")
                }
                Button { isShowingAll = true } label: {
                    Label("All runs", systemImage: "list.bullet.indent")
                        .font(.system(size: 12, weight: .semibold))
                        .practiceChit()
                }
                .buttonStyle(.plain)
                .help("See every run of both hands, name them, and go to one")
                .popover(isPresented: $isShowingAll) {
                    PracticeAllRuns(isShown: $isShowingAll)
                        .environment(state)
                }
                Button { practice.isCutting.toggle() } label: {
                    Label("Cut", systemImage: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                        .practiceChit(fill: practice.isCutting ? Color.orange : nil)
                }
                .buttonStyle(.plain)
                .help(practice.isCutting ? "Hide the steps" : "Show the steps of the run in focus, to cut it into runs")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(practice.shownRuns) { run in
                        chit(run)
                    }
                }
            }
        }
        .renamingRun($renaming, in: practice)
    }

    private func chit(_ run: Run) -> some View {
        let practice = state.practice
        let isChosen = practice.selection.contains(run.id)
        let isFocus = run.id == practice.focus
        let color = practice.hand.color
        return HStack(spacing: 0) {
            Button { practice.toggle(run.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isFocus ? (run.name ?? "Whole run") : practice.title(of: run.id))
                        .font(.system(size: 13, weight: .semibold, design: run.name == nil ? .monospaced : .default))
                        .lineLimit(1)
                    let place = run.name != nil && !isFocus ? practice.label(of: run.id) : nil
                    let time = practice.hasRecording ? practice.span(of: run.id).map { PracticeTime.text($0.lowerBound) } : nil
                    if place != nil || time != nil {
                        Text([place, time].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .opacity(0.7)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, isFocus ? 10 : 4)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help(isChosen ? "Stop watching this run" : "Watch this run (choose several to watch them in turn)")
            if !isFocus {
                Button { practice.focus(on: run.id) } label: {
                    Image(systemName: "chevron.right.circle")
                        .font(.system(size: 13))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open run \(practice.label(of: run.id))")
                .help("Open run \(practice.label(of: run.id)) to see and cut its own runs")
            }
        }
        .foregroundStyle(isChosen ? Color.black : Color(white: 0.85))
        .background(RoundedRectangle(cornerRadius: 8).fill(isChosen ? color : Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isChosen ? color : Color(white: 0.25), lineWidth: 1))
        .contextMenu { renameButton(run.id) }
    }

    private func renameButton(_ id: RunID) -> some View {
        Button("Name…", systemImage: "pencil") { renaming = id }
    }
}

extension View {
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
        content
            .alert("Name run \(renaming.map(practice.label(of:)) ?? "")",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $draft)
                Button("Save") {
                    if let renaming { practice.rename(renaming, to: draft) }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Leave it empty to go by its number.")
            }
            .onChange(of: renaming) { _, id in
                draft = id.flatMap { practice.practice?.find($0)?.run.name } ?? ""
            }
    }
}

/// Every run of both hands as an outline, each under the run it is cut
/// from: its place, its name, how many steps it has and where it is heard.
/// A row goes to its run (`goTo`); its pencil names it.
struct PracticeAllRuns: View {
    @Environment(PerformanceState.self) private var state
    @Binding var isShown: Bool
    @State private var renaming: RunID?

    var body: some View {
        let practice = state.practice
        NavigationStack {
            List {
                ForEach(practice.allRuns, id: \.hand) { hand, runs in
                    Section(hand.name) {
                        ForEach(runs, id: \.run.id) { run, depth in
                            row(run, depth: depth, hand: hand)
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
        .renamingRun($renaming, in: practice)
    }

    private func row(_ run: Run, depth: Int, hand: Hand) -> some View {
        let practice = state.practice
        let isWatched = practice.watched.contains(run.id)
        return HStack(spacing: 8) {
            Button {
                practice.goTo(run.id)
                isShown = false
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isWatched ? hand.color : Color.clear)
                        .frame(width: 6, height: 6)
                    Text(depth == 0 ? "Whole" : practice.label(of: run.id))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let name = run.name {
                        Text(name).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(run.steps.count) step\(run.steps.count == 1 ? "" : "s")")
                        if practice.hasRecording, let span = practice.span(of: run.id) {
                            Text("\(PracticeTime.text(span.lowerBound))–\(PracticeTime.text(span.upperBound))")
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(depth) * 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to \(practice.title(of: run.id)) and watch it")
            Button { renaming = run.id } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Name this run")
            .accessibilityLabel("Name \(practice.title(of: run.id))")
        }
    }
}

/// The steps of the run in focus, in order, to cut it by: a tap between
/// two steps cuts the run there or joins it again, and a tap on a step
/// lights it on the piano and stands the recording at it.
struct PracticeStepsStrip: View {
    @Environment(PerformanceState.self) private var state

    private static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    var body: some View {
        let practice = state.practice
        let steps = practice.focusSteps
        let cuts = practice.focusCuts
        let color = practice.hand.color
        // Which of the run's runs each step is in, to shade them apart.
        let pieceOf = Dictionary(uniqueKeysWithValues: steps.map { item in
            (item.index, cuts.filter { $0 <= item.index }.count)
        })
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(steps, id: \.index) { item in
                    if item.index != steps.first?.index {
                        Button { practice.toggleCut(before: item.index) } label: {
                            ZStack {
                                Color.clear
                                if cuts.contains(item.index) {
                                    Capsule().fill(color).frame(width: 3)
                                } else {
                                    Capsule().fill(Color(white: 0.25)).frame(width: 1)
                                }
                            }
                            .frame(width: 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cuts.contains(item.index) ? "Join here" : "Cut here")
                        .help(cuts.contains(item.index) ? "Join the runs either side here" : "Cut the run here")
                    }
                    Button { practice.select(item.index) } label: {
                        VStack(spacing: 1) {
                            let pitches = item.step.notes.map(\.pitch).reversed() as [Int]
                            ForEach(pitches.indices, id: \.self) { i in
                                Text(Self.name(pitches[i]))
                            }
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(practice.selectedStep == item.index ? Color.black : Color(white: 0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .frame(minWidth: 34, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 5).fill(
                            practice.selectedStep == item.index ? color
                                : Color(white: (pieceOf[item.index] ?? 0).isMultiple(of: 2) ? 0.13 : 0.2)))
                    }
                    .buttonStyle(.plain)
                    .help("Light this step on the piano and stand the recording at it")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 76)
    }

    static func name(_ pitch: Int) -> String {
        names[pitch % 12] + String(pitch / 12 - 1)
    }
}

// MARK: – Playing

/// What plays the recording: skip back or on, play the runs watched from
/// where the recording stands, once or over again, listen on from where
/// the recording stands, and tag a nudge point where it stands and go from
/// one to the next.
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

            Button {
                if practice.listening == .runs { practice.stop() } else { practice.play() }
            } label: {
                Image(systemName: practice.listening == .runs ? "stop.fill" : "play.fill")
                    .practiceChit(fill: practice.listening == .runs ? Color.orange : nil, width: 44)
            }
            .buttonStyle(.plain)
            .hotkeyTip(.playStop)
            .accessibilityLabel(practice.listening == .runs ? "Stop" : "Play the runs")
            .help(practice.listening == .runs ? "Stop" : "Play the runs watched from the playhead (or from the next of them)")

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

            Button {
                if practice.listening == .free { practice.stop() } else { practice.listen() }
            } label: {
                Image(systemName: practice.listening == .free ? "stop.fill" : "ear")
                    .practiceChit(fill: practice.listening == .free ? Color.orange : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(practice.listening == .free ? "Stop" : "Listen from here")
            .help(practice.listening == .free ? "Stop listening" : "Listen to the whole recording from the playhead, with all of the hand lit")

            Spacer(minLength: 4)

            Button { practice.goToNudge(forward: false) } label: {
                Image(systemName: "chevron.left").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous nudge point")
            .help("Go to the previous nudge point (a flag you tagged or a doubt of the match)")
            Button { practice.toggleTag() } label: {
                Image(systemName: practice.isAtTag ? "flag.slash.fill" : "flag.fill")
                    .practiceChit(fill: practice.isAtTag ? PracticeTimelines.tagColor : nil)
            }
            .buttonStyle(.plain)
            .hotkeyTip(.tag)
            .accessibilityLabel(practice.isAtTag ? "Remove the nudge point" : "Tag a nudge point")
            .help(practice.isAtTag ? "Remove the nudge point here" : "Tag a nudge point here, to come back to and fix")
            Button { practice.goToNudge(forward: true) } label: {
                Image(systemName: "chevron.right").practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next nudge point")
            .help("Go to the next nudge point (a flag you tagged or a doubt of the match)")
        }
    }
}

/// The chosen note, set where it is heard: the note before and after,
/// nudged earlier or later by a tenth or a hundredth of a second, where it
/// is heard to the millisecond, heard in the seconds around it, and its
/// pin taken away.
struct PracticeNotesRow: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let practice = state.practice
        let chosen = practice.selectedTime
        HStack(spacing: 6) {
            button("backward.end", "Previous note", "Choose the note before", key: .previousNote) {
                practice.selectNext(forward: false)
            }
            nudge(-ScorePracticeState.coarseNudge, "-100", key: nil)
            nudge(-ScorePracticeState.fineNudge, "-10", key: .nudgeEarlier)
            Text(chosen.map(PracticeTime.precise) ?? "–:––.–––")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(chosen == nil ? Color(white: 0.4) : Color(white: 0.9))
                .frame(minWidth: 76)
                .accessibilityLabel("Chosen note")
                .accessibilityValue(chosen.map(PracticeTime.precise) ?? "none")
                .help("Where the chosen note is heard in the recording")
            nudge(ScorePracticeState.fineNudge, "+10", key: .nudgeLater)
            nudge(ScorePracticeState.coarseNudge, "+100", key: nil)
            button("forward.end", "Next note", "Choose the note after", key: .nextNote) {
                practice.selectNext(forward: true)
            }
            Spacer(minLength: 4)
            button("ear", "Hear the note", "Hear the seconds around the chosen note, then stand at it again", key: nil) {
                practice.hearSelected()
            }
            .disabled(chosen == nil)
            .opacity(chosen == nil ? 0.4 : 1)
            button("pin.slash", "Unpin the note", "Take the chosen note's pin away, leaving it to the match", key: nil) {
                practice.unpinSelected()
            }
            .disabled(!practice.isSelectedPinned)
            .opacity(practice.isSelectedPinned ? 1 : 0.4)
        }
    }

    private func nudge(_ seconds: Double, _ title: String, key: KeyboardButton?) -> some View {
        let isChosen = state.practice.selectedTime != nil
        let ms = Int((abs(seconds) * 1000).rounded())
        return Button { state.practice.nudge(by: seconds) } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .practiceChit()
        }
        .buttonStyle(.plain)
        .hotkeyTip(key)
        .disabled(!isChosen)
        .opacity(isChosen ? 1 : 0.4)
        .accessibilityLabel("\(seconds < 0 ? "Earlier" : "Later") by \(ms) milliseconds")
        .help("Pin the chosen note \(ms) ms \(seconds < 0 ? "earlier" : "later")")
    }

    private func button(_ symbol: String, _ label: String, _ help: String, key: KeyboardButton?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).practiceChit()
        }
        .buttonStyle(.plain)
        .hotkeyTip(key)
        .accessibilityLabel(label)
        .help(help)
    }
}

enum PracticeTime {
    /// "1:23.4".
    static func text(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }

    /// "1:23.456".
    static func precise(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%d:%02d.%03d", ms / 60_000, ms / 1000 % 60, ms % 1000)
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
