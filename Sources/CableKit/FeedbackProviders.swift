import CoreGraphics

// MARK: - CableHapticsProvider

/// Haptic feedback hooks. Implement to replace the default CoreHaptics patterns.
///
/// All methods are called on the main actor. ``stretch(level:)`` is called every frame while the
/// plug is dragged (including with level 0 when slack), so keep it cheap.
@MainActor
public protocol CableHapticsProvider: AnyObject {
    /// Plug fully seated in a socket.
    func plugIn()
    /// Plug pulled out of a socket.
    func unplug()
    /// Plug entered a socket's snap range.
    func hover()
    /// Plug picked up.
    func grab()
    /// Plug hit the floor after being dropped; `velocity` is roughly points per frame ×6.
    func drop(velocity: CGFloat)
    /// Continuous tension while dragging, 0…1 past rest length.
    func stretch(level: CGFloat)
    /// Drag ended — stop any continuous stretch feedback.
    func stopStretch()
    /// Big electric arc (unplug, or the zap as the pin slides in). Optional; default does nothing.
    func spark()
    /// Small arc while approaching a socket; intensity 0…1 grows with closeness. Optional; default does nothing.
    func crackle(intensity: CGFloat)
    /// The view went away or the app left the foreground: stop everything, release the engine. Optional.
    func suspend()
    /// The view is back. Optional.
    func resume()
}

extension CableHapticsProvider {
    public func spark() { }
    public func crackle(intensity _: CGFloat) { }
    public func suspend() { }
    public func resume() { }
}

// MARK: - CableSoundProvider

/// Sound hooks. Implement to replace the synthesized sounds with your own samples.
///
/// All methods are called on the main actor and are only invoked when
/// `CableConfiguration.soundEnabled` is true.
@MainActor
public protocol CableSoundProvider: AnyObject {

    /// Pin bottoms out — the click.
    func plugIn()
    /// Pop when the plug leaves the socket (used by tap-to-disconnect).
    func unplug()
    /// Pin starts sliding in.
    func insert()
    /// Pin sliding out.
    func eject()
    /// Plug entered a socket's snap range.
    func hover()
    /// Cable straining; level is 0…1.
    func creak(level: CGFloat)
    /// Plug hit the floor.
    func drop(velocity: CGFloat)
    /// Big electric crackle (unplug, or the zap as the pin slides in). Optional; default does nothing.
    func spark()
    /// Small crackle while approaching a socket; intensity 0…1. Optional; default does nothing.
    func crackle(intensity: CGFloat)
    /// The view went away or the app left the foreground: stop playback, release the audio engine. Optional.
    func suspend()
    /// The view is back. Optional.
    func resume()

}

extension CableSoundProvider {
    public func spark() { }
    public func crackle(intensity _: CGFloat) { }
    public func suspend() { }
    public func resume() { }
}

// MARK: - SilentCableFeedback

/// A provider that does nothing — use it to silence one channel while keeping the other.
public final class SilentCableFeedback: CableHapticsProvider, CableSoundProvider {

    // MARK: Lifecycle

    public init() { }

    // MARK: Public

    public func plugIn() { }
    public func unplug() { }
    public func hover() { }
    public func grab() { }
    public func drop(velocity _: CGFloat) { }
    public func stretch(level _: CGFloat) { }
    public func stopStretch() { }
    public func insert() { }
    public func eject() { }
    public func creak(level _: CGFloat) { }
    public func spark() { }
    public func crackle(intensity _: CGFloat) { }
    public func suspend() { }
    public func resume() { }

}
