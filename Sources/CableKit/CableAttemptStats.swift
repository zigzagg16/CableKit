import Foundation

// MARK: - CableAttemptStats

/// Simple counts of what happened during one attempt at a board: how many times a plug went in, came back
/// out, or was let go mid-air. Every cable game gets the same three numbers for free from `CableEvent` —
/// what (if anything) counts as a good or bad attempt is a game's own call, not this package's.
public struct CableAttemptStats: Equatable, Sendable {

    // MARK: Lifecycle

    public init() { }

    // MARK: Public

    public private(set) var plugs = 0
    public private(set) var unplugs = 0
    public private(set) var drops = 0

    /// Feed every event a board fires — from `CableBoard`'s own `onEvent`, or a game's handler that already
    /// receives them. Only the three that mark a plug's fate move a counter; the rest (`grabbed`, `hover`,
    /// `stretched`) pass through unrecorded.
    public mutating func record(_ event: CableEvent<some Hashable>) {
        switch event {
        case .plugged: plugs += 1
        case .unplugged: unplugs += 1
        case .dropped: drops += 1
        case .grabbed,
             .hover,
             .stretched: break
        }
    }

    public mutating func reset() {
        self = CableAttemptStats()
    }

}
