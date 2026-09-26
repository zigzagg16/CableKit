import AVFoundation
import CoreHaptics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - DefaultCableHaptics

/// The default haptics: CoreHaptics patterns, falling back to `UIFeedbackGenerator` on iOS and
/// `NSHapticFeedbackManager` on macOS.
///
/// Plug-in is a sharp transient followed by a softer body thump; unplug is a softer pop; hover is
/// a light tick; dropping scales with impact speed; stretching drives a continuous player whose
/// intensity and sharpness follow tension.
public final class DefaultCableHaptics: CableHapticsProvider {

    // MARK: Lifecycle

    /// Starts a Core Haptics engine when the hardware has one; otherwise every call goes to the fallback
    /// generators. The engine auto-shuts-down when idle and is restarted on demand.
    public init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        // Core Haptics calls this on its own thread (CHHapticEngine.h: "callbacks arrive on a non-main
        // thread"), so hop back before touching any state. The block type isn't `@Sendable`, which is why the
        // compiler can't enforce this for us.
        engine?.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? engine?.start()
                stretchPlayer = nil
                stretchRunning = false
            }
        }

        try? engine?.start()
        fallback.prepare()
    }

    // MARK: Public

    /// A firm "click" followed by a softer body thump — feels like a jack seating.
    public func plugIn() {
        play([
            transient(t: 0, intensity: 1.0, sharpness: 0.9),
            transient(t: 0.045, intensity: 0.55, sharpness: 0.25),
        ]) { self.fallback.impact(1.0) }
    }

    /// Softer pop.
    public func unplug() {
        play([
            transient(t: 0, intensity: 0.7, sharpness: 0.45),
            transient(t: 0.06, intensity: 0.3, sharpness: 0.2),
        ]) { self.fallback.impact(0.6) }
    }

    /// Light, sharp tick.
    public func hover() {
        play([transient(t: 0, intensity: 0.4, sharpness: 0.7)]) { self.fallback.tick() }
    }

    /// Two quick sharp taps that get stronger the closer the pin is.
    public func crackle(intensity: CGFloat) {
        let i = Float(0.25 + intensity * 0.5)
        play([transient(t: 0, intensity: i, sharpness: 1.0), transient(t: 0.03, intensity: i * 0.6, sharpness: 1.0)]) {
            self.fallback.impact(CGFloat(i))
        }
    }

    /// Rapid, sharp crackle.
    public func spark() {
        play([
            transient(t: 0, intensity: 0.8, sharpness: 1.0),
            transient(t: 0.035, intensity: 0.5, sharpness: 1.0),
            transient(t: 0.06, intensity: 0.65, sharpness: 0.9),
            transient(t: 0.11, intensity: 0.35, sharpness: 1.0),
            transient(t: 0.16, intensity: 0.2, sharpness: 0.8),
        ]) { self.fallback.impact(0.7) }
    }

    /// Soft, dull bump.
    public func grab() {
        play([transient(t: 0, intensity: 0.35, sharpness: 0.3)]) { self.fallback.impact(0.4) }
    }

    /// Dull thud scaled by impact speed (saturates around 40).
    public func drop(velocity: CGFloat) {
        let i = Float(min(max(velocity / 40, 0.15), 1))
        play([transient(t: 0, intensity: i, sharpness: 0.15)]) { self.fallback.impact(CGFloat(i)) }
    }

    /// Continuous rumble that follows tension (0...1). Call every frame while dragging.
    public func stretch(level: CGFloat) {
        guard level > 0.02 else { stopStretch()
            return
        }
        let now = CACurrentMediaTime()
        if let engine {
            if !stretchRunning {
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ], relativeTime: 0, duration: 30)
                if
                    let pattern = try? CHHapticPattern(events: [event], parameters: []),
                    let player = try? engine.makeAdvancedPlayer(with: pattern)
                {
                    stretchPlayer = player
                    try? player.start(atTime: CHHapticTimeImmediate)
                    stretchRunning = true
                }
            }
            // Intensity ramps hard near the limit; sharpness rises with it so it "creaks".
            let eased = Float(level * level)
            let params = [
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0.15 + eased * 0.85, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0.2 + Float(level) * 0.7, relativeTime: 0),
            ]
            try? stretchPlayer?.sendParameters(params, atTime: CHHapticTimeImmediate)
        } else if level > 0.6, level > lastStretchLevel, now - lastStretchTick > 0.07 {
            fallback.impact(level)
            lastStretchTick = now
        }
        lastStretchLevel = level
    }

    /// Stops the engine so it releases its hardware slot while the view is hidden.
    public func suspend() {
        stopStretch()
        engine?.stop(completionHandler: nil)
    }

    /// Restarts the engine after ``suspend()``.
    public func resume() {
        try? engine?.start()
    }

    /// Ends the continuous tension player; safe to call when none is running.
    public func stopStretch() {
        guard stretchRunning else { return }
        try? stretchPlayer?.stop(atTime: CHHapticTimeImmediate)
        stretchPlayer = nil
        stretchRunning = false
        lastStretchLevel = 0
    }

    // MARK: Private

    private var engine: CHHapticEngine?
    private var stretchPlayer: CHHapticAdvancedPatternPlayer?
    private var stretchRunning = false
    private let fallback = FallbackHaptics()
    private var lastStretchTick: CFTimeInterval = 0
    private var lastStretchLevel: CGFloat = 0

    private func transient(t: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private func play(_ events: [CHHapticEvent], fallback: () -> Void) {
        guard
            let engine,
            let pattern = try? CHHapticPattern(events: events, parameters: []),
            let player = try? engine.makePlayer(with: pattern)
        else { fallback()
            return
        }
        try? engine.start()
        try? player.start(atTime: CHHapticTimeImmediate)
    }

}

// MARK: - SynthesizedCableSounds

/// The default sounds: a tiny procedural synth. Every sound is rendered once into a PCM buffer on
/// first use, so the package ships no audio assets.
///
/// On iOS the shared `AVAudioSession` is app-wide. By default this sets it to `.ambient` (mixes with
/// whatever else is playing, obeys the silent switch), which is right for most apps. If your app
/// manages its own session — a music or podcast player on `.playback`, say — pass
/// `configuresAudioSession: false` and set the category yourself.
public final class SynthesizedCableSounds: CableSoundProvider {

    // MARK: Lifecycle

    /// - Parameter configuresAudioSession: Whether to set the shared audio session to `.ambient`
    ///   (iOS only). Pass `false` when the host app owns its audio session.
    public init(configuresAudioSession: Bool = true) {
        self.configuresAudioSession = configuresAudioSession
        #if os(iOS)
        // The category now, synchronously — before this engine (or the haptics engine beside it) can touch the
        // session. Setting it only in `startEngine`'s background block left a window where an activation ran
        // under iOS's default `.soloAmbient`, which stops the Music app; Music doesn't resume when the category
        // changes afterwards. Setting a category is cheap; activation (the slow part) stays off the main thread.
        if configuresAudioSession {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        }
        #endif
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.8
        startEngine()
    }

    // MARK: Public

    public func plugIn() {
        play(plugBuffer, volume: 1)
    }

    public func unplug() {
        play(unplugBuffer, volume: 0.9)
    }

    public func insert() {
        play(insertBuffer, volume: 0.7)
    }

    public func eject() {
        play(ejectBuffer, volume: 0.9)
    }

    public func hover() {
        play(hoverBuffer, volume: 0.6)
    }

    public func creak(level: CGFloat) {
        play(creakBuffer, volume: Float(0.3 + level * 0.7))
    }

    public func drop(velocity: CGFloat) {
        play(dropBuffer, volume: Float(min(max(velocity / 40, 0.2), 1)))
    }

    public func spark() {
        play(sparkBuffer, volume: 0.8)
    }

    /// Stops playback and the audio engine so a hidden view holds no audio resources.
    public func suspend() {
        for player in players { player.stop() }
        engine.stop()
        engineState = .stopped
    }

    /// Brings the engine back, off the main thread, so it is ready by the time the next sound plays.
    public func resume() {
        startEngine()
    }

    public func crackle(intensity: CGFloat) {
        play(crackleBuffer, volume: Float(0.15 + intensity * 0.35))
    }

    // MARK: Private

    private enum EngineState {
        case stopped
        case starting
        case running
    }

    private let engine = AVAudioEngine()
    private let configuresAudioSession: Bool
    private var engineState = EngineState.stopped
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players = [AVAudioPlayerNode]()
    private var nextPlayer = 0

    private lazy var plugBuffer = render(duration: 0.14) { t, rnd in
        // Bright click (noise burst) + falling sweep + low body thump 40ms later.
        let click: Double = t < 0.006 ? rnd * exp(-t / 0.0015) * 0.9 : 0
        let sweepF: Double = 1600 * exp(-t / 0.02) + 260
        let sweep: Double = sin(2 * Double.pi * sweepF * t) * exp(-t / 0.018) * 0.8
        let t2: Double = t - 0.04
        let thump: Double = t2 > 0 ? sin(2 * Double.pi * 110 * t2) * exp(-t2 / 0.03) * 0.9 : 0
        return click + sweep + thump
    }

    private lazy var unplugBuffer = render(duration: 0.12) { t, rnd in
        let sweepF: Double = 320 + 900 * (1 - exp(-t / 0.02))
        let pop: Double = sin(2 * Double.pi * sweepF * t) * exp(-t / 0.025) * 0.7
        let noise: Double = rnd * exp(-t / 0.004) * 0.35
        return pop + noise
    }

    private lazy var hoverBuffer = render(duration: 0.03) { t, _ in
        let tone: Double = sin(2 * Double.pi * 2600 * t)
        return tone * exp(-t / 0.004) * 0.25
    }

    private lazy var creakBuffer = render(duration: 0.16) { t, rnd in
        // Amplitude-modulated noise, filtered later — reads as a cable straining.
        let mod = 0.5 + 0.5 * sin(2 * Double.pi * 38 * t)
        return rnd * mod * exp(-t / 0.08) * 0.5
    }

    private lazy var insertBuffer = render(duration: 0.13) { t, rnd in
        // Metal-on-metal slide: noise with a rising resonance as the pin goes deeper.
        let env: Double = min(1, t / 0.01) * exp(-t / 0.09)
        let f: Double = 700 + 1400 * (t / 0.13)
        let ring: Double = sin(2 * Double.pi * f * t) * 0.35
        return (rnd * 0.55 + ring) * env
    }

    private lazy var ejectBuffer = render(duration: 0.17) { t, rnd in
        // Reverse slide (falling resonance) that ends in a hollow pop.
        let slideEnv: Double = t < 0.1 ? min(1, t / 0.008) * (1 - t / 0.1) : 0
        let f: Double = 2000 - 1300 * (t / 0.1)
        let slide: Double = (rnd * 0.5 + sin(2 * Double.pi * f * t) * 0.3) * slideEnv
        let t2: Double = t - 0.09
        let popF: Double = 260 + 700 * (1 - exp(-max(t2, 0) / 0.015))
        let pop: Double = t2 > 0 ? sin(2 * Double.pi * popF * t2) * exp(-t2 / 0.03) * 0.8 : 0
        return slide + pop
    }

    private lazy var sparkBuffer = render(duration: 0.26, lowpass: 0.9) { t, rnd in
        // Bursty, bright crackle: white noise gated by a random-ish envelope of short pops.
        let gate: Double = (sin(2 * Double.pi * 47 * t) > 0.2 ? 1 : 0.15) * (sin(2 * Double.pi * 131 * t + 1) > 0.4 ? 1 : 0.4)
        let env: Double = exp(-t / 0.09) * min(1, t / 0.003)
        let hiss: Double = rnd * 0.9
        let zap: Double = sin(2 * Double.pi * (3200 - 1800 * t) * t) * 0.25 * exp(-t / 0.05)
        return (hiss * gate + zap) * env
    }

    private lazy var crackleBuffer = render(duration: 0.07, lowpass: 0.9) { t, rnd in
        let gate: Double = sin(2 * Double.pi * 90 * t) > 0 ? 1 : 0.2
        let env: Double = exp(-t / 0.025) * min(1, t / 0.002)
        return rnd * gate * env * 0.9
    }

    private lazy var dropBuffer = render(duration: 0.09) { t, rnd in
        let thud: Double = sin(2 * Double.pi * 85 * t) * exp(-t / 0.035) * 0.8
        let tick: Double = rnd * exp(-t / 0.002) * 0.3
        return thud + tick
    }

    /// Round-robins six player nodes so rapid sounds (crackles during an approach) overlap instead of cutting
    /// each other off.
    /// Activates the session and starts the engine on a utility queue. Both can block for milliseconds
    /// (AVAudioSession logs a hang-risk fault when activated on the main thread), so the main thread never
    /// waits; a sound requested while this is in flight is dropped rather than stalling the UI.
    private func startEngine() {
        guard engineState == .stopped else { return }
        engineState = .starting
        let engine = UncheckedSendable(engine)
        let configuresAudioSession = configuresAudioSession
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            #if os(iOS)

            if configuresAudioSession {
                let session = AVAudioSession.sharedInstance()
                // Again here as well as in `init`: something else in the app may have changed it since.
                try? session.setCategory(.ambient, options: [.mixWithOthers])
                try? session.setActive(true)
            }
            #endif
            engine.value.prepare()
            let started = (try? engine.value.start()) != nil
            Task { @MainActor [weak self] in
                self?.engineState = started ? .running : .stopped
            }
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard engineState == .running, engine.isRunning else {
            startEngine() // e.g. the session was interrupted; be ready for the next one
            return
        }
        let p = players[nextPlayer]

        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = volume
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        p.play()
    }

    /// Renders a sound into a mono buffer by sampling `f(time, whiteNoise)`, running it through a one-pole
    /// low-pass, clamping, and fading the last 10 ms so there is never a click at the end.
    private func render(duration: Double, lowpass: Double = 0.35, _ f: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        var lp: Double = 0
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let rnd = Double.random(in: -1...1)
            let s: Double = f(t, rnd)
            lp += (s - lp) * lowpass // one-pole low-pass takes the digital edge off
            let fadeOut: Double = min(1, (duration - t) / 0.01)
            let clamped: Double = max(-1, min(1, lp))
            out[i] = Float(clamped * fadeOut)
        }
        return buf
    }

}

// MARK: - FallbackHaptics

/// What plays when CoreHaptics isn't available: the system feedback generators on iOS, the
/// trackpad on macOS.
@MainActor
private struct FallbackHaptics {

    // MARK: Internal

    func prepare() {
        #if canImport(UIKit)
        impactGenerator.prepare()
        #endif
    }

    func impact(_ intensity: CGFloat) {
        #if canImport(UIKit)
        impactGenerator.impactOccurred(intensity: intensity)
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(intensity > 0.6 ? .levelChange : .generic, performanceTime: .now)
        #endif
    }

    func tick() {
        #if canImport(UIKit)
        selectionGenerator.selectionChanged()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    // MARK: Private

    #if canImport(UIKit)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

}

// MARK: - UncheckedSendable

/// Carries a non-`Sendable` framework object (an `AVAudioEngine`) across a queue hop. The engine's own
/// start/stop API is thread-safe; the wrapper only exists to satisfy the compiler.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    init(_ value: Value) {
        self.value = value
    }

    let value: Value
}
