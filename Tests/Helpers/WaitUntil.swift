/// Waits for `condition` to hold, checking every few milliseconds, and
/// returns whether it did before `timeout`. For work that finishes on its
/// own schedule (a strum, a tap's last buffer): a fixed sleep is either too
/// short when the machine is busy or slow when it is not.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(5))
    }
    return true
}
