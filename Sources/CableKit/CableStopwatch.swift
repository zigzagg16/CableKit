import Foundation

// MARK: - CableStopwatch

/// A stopwatch for one attempt at a board: idle until started, running until stopped, remembers nothing about
/// *why* it stopped — a caller decides what a stop means (solved, abandoned, reset).
///
/// Driven by wall-clock `Date` rather than a polling `Timer`, so a view samples `elapsed(at:)` from a
/// `TimelineView` and nothing ticks while idle or stopped.
@Observable
@MainActor
public final class CableStopwatch {

    // MARK: Lifecycle

    public init() { }

    // MARK: Public

    /// Whether the clock is currently running.
    public private(set) var isRunning = false

    /// Starts from zero. No-op if already running — call `reset()` first to restart mid-attempt.
    public func start(at date: Date = .now) {
        guard !isRunning else { return }
        isRunning = true
        startedAt = date
    }

    /// Freezes the clock at its current value and returns it. Zero if never started.
    @discardableResult
    public func stop(at date: Date = .now) -> TimeInterval {
        let value = elapsed(at: date)
        isRunning = false
        startedAt = nil
        frozen = value
        return value
    }

    /// Back to idle: not running, zero elapsed.
    public func reset() {
        isRunning = false
        startedAt = nil
        frozen = 0
    }

    /// Seconds since `start()` while running, the value `stop()` froze, or zero before either has happened.
    public func elapsed(at date: Date = .now) -> TimeInterval {
        guard let startedAt else { return frozen }
        return date.timeIntervalSince(startedAt)
    }

    // MARK: Private

    private var startedAt: Date?
    private var frozen: TimeInterval = 0

}
