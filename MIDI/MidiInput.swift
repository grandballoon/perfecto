import CoreMIDI
import Foundation

/// Hears every MIDI source there is, as it comes and goes, and hands what
/// they send to `ControllerState`.
///
/// The app's own sources ("Perfecto", "Perfecto Link") are not heard, or
/// on a Mac its notes would come back to it. CoreMIDI hands messages over
/// on a thread of its own; they are parsed there and passed to the main
/// thread in the order they came.
@MainActor
final class MidiInput {
    private weak var controller: ControllerState?
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var connected: [MIDIEndpointRef] = []

    /// Starts handing `controller` what every source sends: the sources
    /// there are now and any that come.
    func play(_ controller: ControllerState) {
        guard self.controller == nil else { return }
        self.controller = controller
        let status = MIDIClientCreateWithBlock("Perfecto In" as CFString, &client,
                                               Self.onSetupChange { [weak self] in self?.follow() })
        guard status == noErr else {
            controller.inputFailed(status: status)
            return
        }
        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "Perfecto In" as CFString, ._1_0, &port,
            Self.onReceive { [weak self] messages in
                messages.forEach { self?.controller?.hear($0) }
            })
        guard portStatus == noErr else {
            controller.inputFailed(status: portStatus)
            return
        }
        follow()
    }

    /// Hears the sources there are now, and no longer any that have gone.
    private func follow() {
        connected.forEach { MIDIPortDisconnectSource(port, $0) }
        connected = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { !Self.isOwn($0) }
        connected.forEach { MIDIPortConnectSource(port, $0, nil) }
        controller?.connected(to: connected.map(Self.name))
    }

    // MARK: – CoreMIDI's threads

    /// A block for the client that calls `follow` on the main thread when
    /// the sources change. It is made outside the main actor, since it is
    /// called outside it.
    nonisolated private static func onSetupChange(
        _ follow: @escaping @MainActor @Sendable () -> Void) -> MIDINotifyBlock {
        { notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { follow() }
        }
    }

    /// A block for the port that parses what comes in and hands it to
    /// `hear` on the main thread.
    nonisolated private static func onReceive(
        _ hear: @escaping @MainActor @Sendable ([MidiMessage]) -> Void) -> MIDIReceiveBlock {
        { eventList, _ in
            var messages: [MidiMessage] = []
            for packet in eventList.unsafeSequence() {
                let count = Int(packet.pointee.wordCount)
                withUnsafeBytes(of: packet.pointee.words) { raw in
                    messages += MidiMessage.messages(in: raw.bindMemory(to: UInt32.self).prefix(count))
                }
            }
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async { hear(messages) }
        }
    }

    // MARK: – Sources

    private static func name(of source: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
        return name?.takeRetainedValue() as String? ?? "MIDI source"
    }

    /// Whether `source` is one of the app's own: a virtual source, with no
    /// device under it, of the app's name.
    private static func isOwn(_ source: MIDIEndpointRef) -> Bool {
        var entity: MIDIEntityRef = 0
        let isVirtual = MIDIEndpointGetEntity(source, &entity) != noErr || entity == 0
        return isVirtual && name(of: source).hasPrefix("Perfecto")
    }
}
