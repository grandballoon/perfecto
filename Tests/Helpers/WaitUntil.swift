/// Waits for `condition` to hold, checking every few milliseconds, and
/// returns whether it did before `timeout`. For work that finishes on its
/// own schedule (a strum, a tap's last buffer): a fixed sleep is either too
/// short when the machine is busy or slow when it is not. The timeout is
/// long, since it is only reached by a failure: a simulator just booted,
/// running the whole suite at once, can hold the main thread for seconds.
@MainActor
func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(5))
    }
    return true
}
