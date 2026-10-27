import AppKit
import SwiftUI

/// Perfecto at a desk: a Mac app played from a game controller.
@main
struct PerfectoDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var host = DeskHost()

    var body: some Scene {
        Window("Perfecto Desk", id: "desk") {
            DeskView()
                .environment(host)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    host.start()
                    delegate.host = host
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var host: DeskHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from the command line, the app is not a bundle and is not
        // made a regular app with a window in front unless it asks.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        host?.stop()
    }
}
