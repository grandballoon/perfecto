import SwiftUI

private struct ModeEntry: Identifiable {
    let id: String
    let description: String
    let makeMode: ((PerformanceState) -> any PerformanceMode)?
}

@MainActor
private let modeEntries: [ModeEntry] = [
    ModeEntry(id: "Play",       description: "Chord sustains while held",           makeMode: { _ in PlayMode() }),
    ModeEntry(id: "Strum",      description: "Notes arpeggiate on button press",    makeMode: { _ in StrumMode() }),
    ModeEntry(id: "Lead",       description: "Single melody note per button",       makeMode: { _ in LeadMode() }),
    ModeEntry(id: "Drone",      description: "Press to latch; press again to stop", makeMode: { _ in DroneMode() }),
    ModeEntry(id: "Arpeggio",   description: "Sequential notes at tempo",           makeMode: { _ in ArpeggioMode() }),
    ModeEntry(id: "Repeat",     description: "Chord retriggers at tempo",           makeMode: { _ in RepeatMode() }),
    ModeEntry(id: "Sequencer",  description: "16-step chord sequence",              makeMode: { SequencerMode($0.sequencerState) }),
    ModeEntry(id: "Looper",     description: "2-track audio looper",               makeMode: { LooperMode($0.looperState) }),
    ModeEntry(id: "Mic Sample", description: "Record a clip; play it via buttons", makeMode: { $0.makeMicSampleMode() }),
]

struct ModeSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(modeEntries) { entry in
                        modeRow(entry)
                    }
                }

                Section {
                    bpmRow
                } header: {
                    sectionLabel("TEMPO")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.07), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: – Mode row

    @ViewBuilder
    private func modeRow(_ entry: ModeEntry) -> some View {
        let isActive    = state.mode.name == entry.id
        let isAvailable = entry.makeMode != nil

        Button {
            guard let make = entry.makeMode else { return }
            state.setMode(make(state))
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.id)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(isAvailable ? .white : Color(white: 0.35))
                    Text(entry.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isAvailable ? Color(white: 0.45) : Color(white: 0.22))
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                } else if !isAvailable {
                    Image(systemName: "clock")
                        .foregroundStyle(Color(white: 0.28))
                        .font(.system(size: 13))
                }
            }
        }
        .disabled(!isAvailable)
        .listRowBackground(Color(white: isAvailable ? 0.10 : 0.07))
    }

    // MARK: – BPM row

    private var bpmRow: some View {
        HStack(spacing: 20) {
            Button {
                state.setBPM(state.bpm - 5)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(state.bpm > 20 ? Color.orange : Color(white: 0.25))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(Int(state.bpm)) BPM")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Button {
                state.setBPM(state.bpm + 5)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(state.bpm < 300 ? Color.orange : Color(white: 0.25))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color(white: 0.10))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }
}
