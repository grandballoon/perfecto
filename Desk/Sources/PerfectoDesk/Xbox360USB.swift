import DeskCore
import Foundation
import IOKit
import IOUSBHost
import os

/// A wired Xbox 360 controller, read straight from USB.
///
/// macOS has no driver for the 360 (GameController sees the Xbox One and
/// Series controllers, which the desk reads through `SystemGamepads`), so
/// nothing else claims it: this opens the device, configures it, and reads
/// its 20-byte reports from the interrupt pipe, which `Xbox360.frame` turns
/// into frames. Its motors are driven by output reports.
///
/// Everything happens on its own queue; the main thread reads the latest
/// frame under a lock.
final class Xbox360USB: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.perfecto.desk.xbox360")
    private let lock = OSAllocatedUnfairLock<GamepadFrame?>(initialState: nil)
    private var port: IONotificationPortRef?
    private var arrivals: io_iterator_t = 0
    private var device: IOUSBHostDevice?
    private var interface: IOUSBHostInterface?
    private var input: IOUSBHostPipe?
    private var output: IOUSBHostPipe?
    private var rumbleEnd: DispatchWorkItem?
    private let log = Logger(subsystem: "com.perfecto.desk", category: "xbox360")
    /// IOKit's message that a service has gone (`kIOMessageServiceIsTerminated`,
    /// a macro Swift does not see).
    private static let terminated: UInt32 = 0xE000_0010

    /// The frame last read, at the time it was read; nil with no controller.
    var frame: GamepadFrame? { lock.withLock { $0 } }

    /// Starts watching for the controller: the one plugged in now, and any
    /// plugged in later.
    func start() {
        queue.async { self.watch() }
    }

    /// Spins the motors for a moment.
    func play(_ rumble: Rumble) {
        queue.async {
            let (low, high, time) = rumble == .tick ? (0.0, 0.5, 0.04) : (0.7, 0.2, 0.08)
            self.send(Xbox360.rumble(low: low, high: high))
            self.rumbleEnd?.cancel()
            let end = DispatchWorkItem { self.send(Xbox360.rumble(low: 0, high: 0)) }
            self.rumbleEnd = end
            self.queue.asyncAfter(deadline: .now() + time, execute: end)
        }
    }

    // MARK: – On the queue

    private func watch() {
        port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port else { return }
        IONotificationPortSetDispatchQueue(port, queue)
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = Xbox360.vendor
        matching["idProduct"] = Xbox360.product
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, { context, iterator in
            let reader = Unmanaged<Xbox360USB>.fromOpaque(context!).takeUnretainedValue()
            reader.arrived(iterator)
        }, context, &arrivals)
        arrived(arrivals)
    }

    private func arrived(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard device == nil else { continue }
            open(service)
        }
    }

    private func open(_ service: io_service_t) {
        do {
            let device = try IOUSBHostDevice(__ioService: service, options: [], queue: queue) { [weak self] _, type, _ in
                if type == Self.terminated { self?.close() }
            }
            self.device = device
            try device.__configure(withValue: 1, matchInterfaces: true)
            log.info("Xbox 360 controller opened")
            findInterface(tries: 20)
        } catch {
            log.error("could not open the Xbox 360 controller: \(error.localizedDescription)")
        }
    }

    /// The interfaces are made after the device is configured, so they are
    /// looked for a few times.
    private func findInterface(tries: Int) {
        let matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
        matching["idVendor"] = Xbox360.vendor
        matching["idProduct"] = Xbox360.product
        matching["bInterfaceNumber"] = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            if tries > 0 { queue.asyncAfter(deadline: .now() + 0.1) { self.findInterface(tries: tries - 1) } }
            return
        }
        defer { IOObjectRelease(service) }
        do {
            let interface = try IOUSBHostInterface(__ioService: service, options: [], queue: queue, interestHandler: nil)
            self.interface = interface
            input = try interface.copyPipe(withAddress: 0x81)
            output = (try? interface.copyPipe(withAddress: 0x01)) ?? (try? interface.copyPipe(withAddress: 0x02))
            send(Xbox360.playerOne)
            read()
        } catch {
            log.error("could not read the Xbox 360 controller: \(error.localizedDescription)")
        }
    }

    private func read() {
        guard let interface, let input, let data = try? interface.ioData(withCapacity: 32) else { return }
        do {
            nonisolated(unsafe) let buffer = data
            try input.enqueueIORequest(with: data, completionTimeout: 0) { [weak self] status, length in
                guard let self else { return }
                if status == kIOReturnSuccess {
                    let bytes = [UInt8](buffer.prefix(length))
                    if let frame = Xbox360.frame(bytes, at: ProcessInfo.processInfo.systemUptime) {
                        self.lock.withLock { $0 = frame }
                    }
                    self.read()
                } else if status != kIOReturnAborted {
                    self.queue.asyncAfter(deadline: .now() + 0.05) { self.read() }
                }
            }
        } catch {
            log.error("reading stopped: \(error.localizedDescription)")
        }
    }

    private func send(_ report: [UInt8]) {
        guard let interface, let output, let data = try? interface.ioData(withCapacity: report.count) else { return }
        data.length = report.count
        data.replaceBytes(in: NSRange(location: 0, length: report.count), withBytes: report)
        try? output.enqueueIORequest(with: data, completionTimeout: 0, completionHandler: nil)
    }

    private func close() {
        try? input?.__abort(with: .asynchronous)
        interface?.destroy()
        device?.destroy()
        input = nil
        output = nil
        interface = nil
        device = nil
        lock.withLock { $0 = nil }
        log.info("Xbox 360 controller gone")
    }
}
