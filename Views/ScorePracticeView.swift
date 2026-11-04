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
                        PracticeRecordingStrip()
                        PracticeScrubber()
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
                    }
                }
            }
            if practice.piece != nil {
                Button { withAnimation(.easeOut(duration: 0.2)) { practice.fitPiano() } } label: {
                    Image(systemName: "arrow.left.and.right").practiceChit()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fit the piano to the runs")
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
                Divider()
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
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(white: 0.9))
        }
    }

    // MARK: – No piece yet

    private var emptyMessage: some View {
        VStack(spacing: 12) {
            Text("Open a score in MusicXML (.mxl or .musicxml) or MIDI (.mid) and add a recording of it, then dice each hand into runs and watch them on the keys as the recording plays.")
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
                        Text(practice.label(of: run.id))
                            .font(.system(size: 12, weight: depth == practice.focusPath.count - 1 ? .semibold : .regular))
                            .foregroundStyle(depth == practice.focusPath.count - 1 ? Color(white: 0.9) : Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if !practice.selection.isEmpty {
                    Button("Clear") { practice.clearSelection() }
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.6))
                        .buttonStyle(.plain)
                }
                Button { practice.isCutting.toggle() } label: {
                    Label("Cut", systemImage: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                        .practiceChit(fill: practice.isCutting ? Color.orange : nil)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(practice.shownRuns) { run in
                        chit(run)
                    }
                }
            }
        }
    }

    private func chit(_ run: Run) -> some View {
        let practice = state.practice
        let isChosen = practice.selection.contains(run.id)
        let isFocus = run.id == practice.focus
        let color = practice.hand.color
        return HStack(spacing: 0) {
            Button { practice.toggle(run.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isFocus ? "Whole run" : practice.label(of: run.id))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if let span = practice.span(of: run.id), practice.hasRecording {
                        Text(PracticeTime.text(span.lowerBound))
                            .font(.system(size: 10, design: .monospaced))
                            .opacity(0.7)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, isFocus ? 10 : 4)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            if !isFocus {
                Button { practice.focus(on: run.id) } label: {
                    Image(systemName: "chevron.right.circle")
                        .font(.system(size: 13))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open run \(practice.label(of: run.id))")
            }
        }
        .foregroundStyle(isChosen ? Color.black : Color(white: 0.85))
        .background(RoundedRectangle(cornerRadius: 8).fill(isChosen ? color : Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isChosen ? color : Color(white: 0.25), lineWidth: 1))
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
                    }
                    Button { practice.preview(item.index) } label: {
                        VStack(spacing: 1) {
                            let pitches = item.step.notes.map(\.pitch).reversed() as [Int]
                            ForEach(pitches.indices, id: \.self) { i in
                                Text(Self.name(pitches[i]))
                            }
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(practice.previewStep == item.index ? Color.black : Color(white: 0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .frame(minWidth: 34, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 5).fill(
                            practice.previewStep == item.index ? color
                                : Color(white: (pieceOf[item.index] ?? 0).isMultiple(of: 2) ? 0.13 : 0.2)))
                    }
                    .buttonStyle(.plain)
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

/// What plays the recording, and what matches it to a run: play the runs
/// watched, once or over again, listen on from where the recording stands,
/// and set where the matched run begins and ends to the moment heard.
struct PracticeTransport: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var practice = state.practice
        HStack(spacing: 8) {
            Button {
                if practice.listening == .runs { practice.stop() } else { practice.play() }
            } label: {
                Image(systemName: practice.listening == .runs ? "stop.fill" : "play.fill")
                    .practiceChit(fill: practice.listening == .runs ? Color.orange : nil, width: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(practice.listening == .runs ? "Stop" : "Play the runs")

            Button { practice.repeats.toggle() } label: {
                Image(systemName: "repeat")
                    .practiceChit(fill: practice.repeats ? Color(white: 0.85) : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .accessibilityAddTraits(practice.repeats ? .isSelected : [])

            Button {
                if practice.listening == .free { practice.stop() } else { practice.listen() }
            } label: {
                Image(systemName: practice.listening == .free ? "stop.fill" : "ear")
                    .practiceChit(fill: practice.listening == .free ? Color.orange : nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(practice.listening == .free ? "Stop" : "Listen from here")

            Spacer(minLength: 4)

            Button { practice.markStart() } label: {
                Label("Start", systemImage: "arrow.right.to.line")
                    .font(.system(size: 12, weight: .semibold))
                    .practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run starts here")
            Button { practice.markEnd() } label: {
                Label("End", systemImage: "arrow.left.to.line")
                    .font(.system(size: 12, weight: .semibold))
                    .practiceChit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run ends here")
        }
    }
}

enum PracticeTime {
    /// "1:23.4".
    static func text(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

private extension View {
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
