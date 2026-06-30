import SwiftUI

struct LooperView: View {
    @Environment(PerformanceState.self) private var perfState
    @Environment(LooperState.self)      private var looperState

    private let topRow: [(Degree, String, Color)] = [
        (.I, "I", .orange), (.ii, "ii", .blue), (.iii, "iii", .indigo), (.IV, "IV", .orange),
    ]
    private let bottomRow: [(Degree, String, Color)] = [
        (.V, "V", .orange), (.vi, "vi", .blue), (.viiDim, "vii°", .purple),
    ]

    var body: some View {
        VStack(spacing: 12) {
            trackPanel
            chordButtons
            joystickRow
        }
        .padding(.horizontal, 16)
    }

    // MARK: – Track panel

    private var trackPanel: some View {
        VStack(spacing: 8) {
            trackRow(index: 0)
            Divider().background(Color(white: 0.15))
            trackRow(index: 1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.07)))
    }

    @ViewBuilder
    private func trackRow(index: Int) -> some View {
        let track = looperState.tracks[index]

        HStack(spacing: 8) {
            // Label + status
            VStack(alignment: .leading, spacing: 2) {
                Text("TRK \(index + 1)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                    .kerning(1)
                phaseLabel(track: track)
            }
            .frame(width: 60, alignment: .leading)

            // Volume
            Slider(
                value: Binding(
                    get: { Double(looperState.tracks[index].volume) },
                    set: {
                        looperState.tracks[index].volume = Float($0)
                        perfState.looper?.setVolume(index, Float($0))
                    }
                ),
                in: 0...1
            )
            .tint(track.phase == .playing ? .green : .orange)

            // Mute
            Button {
                looperState.tracks[index].isMuted.toggle()
                perfState.looper?.setMute(index, looperState.tracks[index].isMuted)
            } label: {
                Image(systemName: looperState.tracks[index].isMuted
                      ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(looperState.tracks[index].isMuted
                                     ? Color(white: 0.35) : Color(white: 0.65))
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
            }
            .buttonStyle(.plain)

            // Primary action
            primaryButton(for: track, index: index)

            // Clear (only when there's content to clear)
            if track.hasContent {
                Button {
                    looperState.pendingClear = index
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                        .frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func phaseLabel(track: LoopTrack) -> some View {
        switch track.phase {
        case .empty:
            Text("EMPTY")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.22))
        case .recording:
            Text("● REC")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
        case .playing:
            Text("▶ LOOP")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.green)
        case .stopped:
            Text("■ PAUSED")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
        }
    }

    @ViewBuilder
    private func primaryButton(for track: LoopTrack, index: Int) -> some View {
        let canRecord = index == 0 || looperState.loopLengthTicks > 0

        switch track.phase {
        case .empty:
            Button {
                guard canRecord else { return }
                looperState.pendingRecord = index
            } label: {
                Image(systemName: "record.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(canRecord ? .red : Color(white: 0.28))
                    .frame(width: 36, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)

        case .recording:
            Button { looperState.pendingStop = index } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.red)
                    .frame(width: 36, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
            }
            .buttonStyle(.plain)

        case .playing:
            Button { looperState.pendingStop = index } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .frame(width: 36, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
            }
            .buttonStyle(.plain)

        case .stopped:
            Button {
                perfState.looper?.startPlayback(index)
                looperState.tracks[index].phase = .playing
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .frame(width: 36, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: – Chord buttons

    private var chordButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(topRow, id: \.0) { degree, label, color in
                    ChordButton(degree: degree, label: label, color: color)
                }
            }
            HStack(spacing: 10) {
                ForEach(bottomRow, id: \.0) { degree, label, color in
                    ChordButton(degree: degree, label: label, color: color)
                }
                Spacer()
            }
        }
    }

    // MARK: – Joystick

    private var joystickRow: some View {
        HStack(alignment: .center, spacing: 0) {
            JoystickView()
                .padding(.leading, 12)
            Spacer()
        }
        .padding(.bottom, 40)
    }
}
