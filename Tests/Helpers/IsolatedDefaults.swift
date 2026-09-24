import Foundation

/// A fresh, empty UserDefaults suite, so a test never reads or writes the
/// app's real saved state (e.g. the user's sequencer pattern).
func isolatedDefaults() -> UserDefaults {
    let name = "PerfectoTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
