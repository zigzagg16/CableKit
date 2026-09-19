import QuartzCore
import SwiftUI
#if os(iOS)
import CoreMotion
#endif

// MARK: - CableController

/// Owns the rope, the interaction state machine, the display link and feedback for one cable.
///
/// The view layer is thin on purpose: ``CableBoard`` feeds this object layout (`updateLayout`), gestures
/// (`dragChanged` / `dragEnded` / `tapSocket`) and lifecycle (`start` / `stop`), and ``CableCanvas`` draws
/// whatever `publish()` last wrote to the rendering properties. Everything in between — the display link,
/// the rope simulation, the take-up reel, hover hysteresis, sparks, haptics and sound — lives here.
///
/// ## Phases
///
/// ```
///                    grab                 release near socket
///   hanging ───────────────▶ dragging ─────────────────────────▶ snapping(id)
///      ▲                        │  ▲                                   │ tip reaches the mouth
///      │ release elsewhere      │  │ pin is out                         ▼
///      └────────────────────────┘  │                             inserting(id)
///                                  │                                   │ pin bottoms out
///   ejecting(id) ◀──────────────────┘                                   ▼
///      ▲     pulled past `unplugDistance`                          plugged(id)
///      │                                                               │ grab
///      └───────────────────── tugging(id) ◀─────────────────────────────┘
///                          (tap: release + eject)
/// ```
///
/// `setConnection` and `tapSocket` enter this graph from the outside (binding changes, taps on socket
/// views); `stop()` collapses any gesture-bound phase back to `hanging` or `plugged`.
///
/// ## Threading
///
/// Main actor only. The display link, Core Motion (delivered to `.main`) and SwiftUI all call in on it,
/// and the feedback providers are `@MainActor` protocols.
@Observable
@MainActor
final class CableController<ID: Hashable> {

    // MARK: Lifecycle

    init(config: CableConfiguration) {
        self.config = config
        sim = RopeSimulation(
            count: config.segmentCount,
            segmentLength: 10,
            anchor: .zero,
            gravity: config.gravity,
            damping: config.damping,
        )
        sim.headLength = config.plugStyle.length
    }

    deinit {
        // `stop()` normally runs from `onDisappear`; this covers a controller that is dropped without it.
        // The controller is owned by SwiftUI `@State`, so it is released on the main actor; `isolated deinit`
        // would say so in the signature but needs iOS 18.
        MainActor.assumeIsolated {
            link?.invalidate()
            #if os(iOS)
            motion?.stopDeviceMotionUpdates()
            #endif
        }
    }

    // MARK: Internal

    enum Phase: Equatable {
        case hanging
        case dragging
        case tugging(ID) // plugged in and being pulled, hasn't popped out yet
        case snapping(ID) // released near a socket, spring-settling in front of it
        case inserting(ID) // pin sliding into the socket
        case ejecting(ID) // pin sliding back out, then continues as a drag
        case plugged(ID)
    }

    struct Spark: Equatable {
        var from: CGPoint // socket face
        var progress: CGFloat // 0 → 1
        var seed: Int // changes a few times per arc so it flickers
        var intensity: CGFloat // 1 = full unplug arc, smaller = approach flicker
        var duration: TimeInterval
    }

    // Rendering state (observed by the Canvas)
    private(set) var points = [CGPoint]()
    private(set) var headAngle: CGFloat = 0
    private(set) var stretch: CGFloat = 0 // 0...1 tension past rest length
    private(set) var hovered: ID?
    private(set) var phase = Phase.hanging
    private(set) var socketPulse = [ID: CGFloat]() // 1 → 0 decay after plug-in
    /// 0 = pin fully out, 1 = pin fully inside the socket.
    private(set) var insertion: CGFloat = 0
    /// Local x (plug space) past which the pin is hidden inside the socket, when seated.
    private(set) var pinClipX: CGFloat?
    /// Distance the data pattern has travelled along the cable (drives the dash phase).
    private(set) var dataPhase: CGFloat = 0
    /// 0...1 fade of the data animation (1 only while seated).
    private(set) var dataOpacity: CGFloat = 0
    /// Electric arc shown right after unplugging: where it starts, how far along it is, and a flicker seed.
    private(set) var spark: Spark?

    // Layout
    var config: CableConfiguration
    private(set) var anchor = CGPoint.zero
    private(set) var socketPoints = [ID: CGPoint]()
    /// Callbacks are re-assigned by the board on every body evaluation so they never go stale;
    /// ignored by observation so that assignment doesn't invalidate the body that made it.
    @ObservationIgnored var onEvent: ((CableEvent<ID>) -> Void)?
    @ObservationIgnored var onConnectionChange: ((ID?) -> Void)?
    #if os(iOS)
    /// The scene the board is shown in; maps device gravity into the interface's orientation.
    /// Set by the view, so nothing here touches `UIApplication` (which app extensions can't use).
    @ObservationIgnored weak var windowScene: UIWindowScene?
    #endif

    var connected: ID? {
        switch phase {
        case .plugged(let id),
             .tugging(let id),
             .snapping(let id),
             .inserting(let id): id
        default: nil
        }
    }

    /// Middle of the plug body, in the board's coordinate space; the centre of the touch target.
    var headCenter: CGPoint {
        guard points.count >= 2 else { return .zero }
        let h = points[points.count - 1]
        return CGPoint(x: h.x + cos(headAngle) * headLength * 0.5, y: h.y + sin(headAngle) * headLength * 0.5)
    }

    /// Called by the board whenever geometry changes: where the cable leaves the source, where each socket's
    /// centre is, which sockets can currently take this plug, the seated direction per socket, and the board's
    /// bounds (the rope's floor and walls).
    ///
    /// Rest length and the hang cap are derived here unless ``CableConfiguration/restLength`` is set. The first
    /// call also settles the rope for 300 sub-steps so the cable never appears as a straight line, seating the
    /// plug straight away if `setConnection` asked for it before layout existed.
    func updateLayout(anchor: CGPoint, sockets: [ID: CGPoint], enabled: [ID: Bool], angles: [ID: CGFloat] = [:], bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let changed = needsLengthRecompute
            || anchor != self.anchor || sockets != socketPoints || bounds != self.bounds || angles != socketAngles
        needsLengthRecompute = false
        self.anchor = anchor
        socketPoints = sockets
        socketEnabled = enabled
        socketAngles = angles
        self.bounds = bounds
        guard changed else { return }

        let farthest = sockets.values.map { hypot($0.x - anchor.x, $0.y - anchor.y) }.max() ?? 200
        // Long enough to reach every socket, and for a hanging plug to reach `hangFraction` of the way down.
        let hang = max((bounds.maxY - anchor.y) * min(max(config.hangFraction, 0), 1) - headLength, config.slack * 2)
        restLength = config.restLength ?? max(farthest * 1.06 + 30, hang + 10)
        hangLength = min(restLength, hang + 10)
        maxLength = restLength * config.maxStretch
        if !layoutReady {
            currentLength = config.autoSlack ? config.slack * 2 : restLength
        }
        sim.segmentLength = currentLength / CGFloat(sim.count - 1)
        sim.anchor = anchor
        sim.bounds = bounds
        sim.floorInset = config.cable.width * 0.5 + 6

        if !layoutReady {
            layoutReady = true
            // Start pre-settled so the first frame isn't a straight line.
            if case .plugged(let id) = phase, let end = ropeEnd(forSocket: id, insertion: 1) {
                insertion = 1
                sim.entryDirection = entryDirection(id)
                sim.reset(toward: end, tipToward: sim.entryDirection)
                sim.tail = end
                sim.tipPin = seatedTip(forSocket: id)
                sim.alignTail = true
            } else {
                if phase != .hanging { // `@Observable` notifies on every set, even of the same value
                    phase = .hanging
                }
                sim.reset(toward: CGPoint(x: anchor.x + 40, y: bounds.maxY - 80), tipToward: CGVector(dx: 0, dy: 1))

                sim.tail = nil
                sim.tipPin = nil
            }
            for _ in 0..<300 {
                updateSlack(dt: 1 / 120)
                sim.step(dt: 1 / 120)
            }
            publish()
        }
        wake()
    }

    /// Applies a new configuration live. Length-related settings trigger a layout recompute; toggling
    /// ``CableConfiguration/gravityFollowsDevice`` starts or stops Core Motion.
    func updateConfig(_ new: CableConfiguration) {
        guard new != config else { return }
        let motionChanged = new.gravityFollowsDevice != config.gravityFollowsDevice
        let lengthChanged = new.restLength != config.restLength
            || new.hangFraction != config.hangFraction
            || new.maxStretch != config.maxStretch
            || new.plugStyle.length != config.plugStyle.length
        config = new
        if lengthChanged, layoutReady {
            needsLengthRecompute = true
            updateLayout(anchor: anchor, sockets: socketPoints, enabled: socketEnabled, angles: socketAngles, bounds: bounds)
        }
        sim.headLength = new.plugStyle.length
        if motionChanged {
            updateMotion()
        }
        wake()
    }

    /// Programmatic connection (the `connection` binding changed). `animated` snaps the plug over like a
    /// release near the socket would; otherwise it seats instantly. A `nil` id ejects.
    func setConnection(_ id: ID?, animated: Bool = true) {
        guard layoutReady else {
            // No layout yet, so no socket positions either: remember the wish and let the first layout
            // pass seat the plug (or fall back to hanging if the socket never shows up).
            phase = id.map { .plugged($0) } ?? .hanging
            return
        }
        if id == connected {
            return
        }
        if let id, socketPoints[id] != nil {
            if animated {
                beginSnap(to: id)
            } else {
                seat(id)
                publish()
            }
        } else if connected != nil {
            release()
        }
        wake()
    }

    /// Whether a touch at this point lands on the plug body (as opposed to the cable).
    func isOnPlug(_ p: CGPoint) -> Bool {
        let c = headCenter
        return hypot(p.x - c.x, p.y - c.y) <= config.plugHitRadius
    }

    /// Distance from a point to the nearest grabbable rope node, for choosing which cable a touch is on.
    func cableDistance(to p: CGPoint) -> CGFloat {
        let near = sim.nearestNode(to: p)
        return near.index < sim.count - 1 ? near.distance : .infinity
    }

    /// One sample of the drag gesture. The first sample of a gesture decides what the finger holds (the plug
    /// body, or a point along the cable when ``CableConfiguration/cableGrabEnabled``); every sample after that
    /// just moves the target.
    func dragChanged(at location: CGPoint, start: CGPoint) {
        // Decide once per gesture whether the finger holds the plug or the cable.
        if !gestureActive {
            gestureActive = true
            if config.cableGrabEnabled, !isOnPlug(start) {
                let near = sim.nearestNode(to: start)
                if near.distance <= config.cableHitRadius + config.cable.width, near.index < sim.count - 1 {
                    let node = sim.points[near.index]
                    cableGrab = (near.index, CGVector(dx: start.x - node.x, dy: start.y - node.y))
                    if config.hapticsEnabled {
                        haptics.grab()
                    }
                }
            }
        }
        if let grab = cableGrab {
            sim.grabbedNode = (grab.index, CGPoint(x: location.x - grab.offset.dx, y: location.y - grab.offset.dy))
            sim.grabStrength = 1 - min(max(config.cableGrabSoftness, 0), 1) * 0.85
            if case .hanging = phase {
                wasAirborne = true
            }
            wake()
            return
        }
        switch phase {
        case .hanging,
             .snapping,
             .ejecting:
            grabOffset = CGVector(dx: location.x - sim.tipPosition.x, dy: location.y - sim.tipPosition.y)
            phase = .dragging
            sim.tail = nil
            sim.alignTail = false
            if config.hapticsEnabled {
                haptics.grab()
            }
            onEvent?(.grabbed)
            fingerTarget = location

        case .plugged(let id),
             .inserting(let id):
            grabOffset = CGVector(dx: location.x - sim.tipPosition.x, dy: location.y - sim.tipPosition.y)
            phase = .tugging(id)
            fingerTarget = location
            dragStart = location
            dragStartTime = CACurrentMediaTime()
            dragMoved = 0

        case .tugging(let id):
            fingerTarget = location
            dragMoved = max(dragMoved, hypot(location.x - dragStart.x, location.y - dragStart.y))
            guard let seated = seatedTip(forSocket: id) else { return }
            let target = CGPoint(x: location.x - grabOffset.dx, y: location.y - grabOffset.dy)
            if hypot(target.x - seated.x, target.y - seated.y) > config.unplugDistance {
                phase = .ejecting(id)
                if config.hapticsEnabled {
                    haptics.unplug()
                }
                if config.soundEnabled {
                    sounds.eject()
                }
                if config.spark.includesUnplug {
                    startSpark(socket: id)
                }
                onEvent?(.unplugged(id))
                onConnectionChange?(nil)
            }

        case .dragging:
            fingerTarget = location
        }
        wake()
    }

    /// The finger lifted. A dragged plug snaps to the hovered socket or drops; a tugged plug either settles
    /// back in or, if the gesture was a quick tap, ejects.
    func dragEnded() {
        gestureActive = false
        if cableGrab != nil {
            cableGrab = nil
            sim.grabbedNode = nil // the node keeps the finger's velocity from the Verlet history
            haptics.stopStretch()
            stretch = 0
            lastCreakLevel = 0
            wake()
            return
        }
        switch phase {
        case .dragging:
            if let hovered, socketEnabled[hovered] ?? true {
                beginSnap(to: hovered)
            } else {
                release()
            }

        case .tugging(let id):
            if dragMoved < 10, CACurrentMediaTime() - dragStartTime < 0.35 {
                // A tap on the seated plug ejects it.
                phase = .plugged(id)
                tapSocket(id)
            } else {
                phase = .plugged(id) // didn't pull hard enough — settles back in
            }

        case .ejecting:
            release()

        default: break
        }
        setHovered(nil)
        haptics.stopStretch()
        stretch = 0
        wake()
    }

    /// A tap on a socket view: ejects the plug if it is in that socket, otherwise snaps the plug over (unplugging
    /// it from wherever it was first). Ignored for disabled sockets.
    func tapSocket(_ id: ID) {
        guard socketEnabled[id] ?? true else { return }
        if connected == id {
            release()
            if config.hapticsEnabled {
                haptics.unplug()
            }
            if config.soundEnabled {
                sounds.eject()
            }
            if config.spark.includesUnplug {
                startSpark(socket: id)
            }
            onEvent?(.unplugged(id))
            onConnectionChange?(nil)
        } else {
            // Moving straight from one socket to another counts as unplugging the first.
            if let old = connected {
                if config.hapticsEnabled {
                    haptics.unplug()
                }
                if config.soundEnabled {
                    sounds.eject()
                }
                if config.spark.includesUnplug {
                    startSpark(socket: old)
                }
                onEvent?(.unplugged(old))
            }
            beginSnap(to: id)
        }
        wake()
    }

    /// Starts the display link, Core Motion (if configured) and re-arms feedback. Idempotent.
    func start() {
        guard link == nil else { return }
        link = DisplayLink { [weak self] t in self?.tick(t) }
        lastTime = 0
        updateMotion()
        resumeFeedback()
        wake()
    }

    /// Stops the display link, motion updates, haptics and sound. Called when the view disappears
    /// or the app leaves the foreground; `start()` brings everything back.
    func stop() {
        link?.invalidate()
        link = nil
        lastTime = 0
        #if os(iOS)
        motion?.stopDeviceMotionUpdates()
        motion = nil
        #endif
        // Drop anything mid-gesture so nothing keeps buzzing.
        cableGrab = nil
        sim.grabbedNode = nil
        gestureActive = false
        spark = nil
        stretch = 0
        if case .dragging = phase {
            release()
        }
        if case .tugging(let id) = phase {
            phase = .plugged(id)
        }
        if case .ejecting = phase {
            release()
        }
        setHovered(nil)
        haptics.stopStretch()
        haptics.suspend()
        sounds.suspend()
    }

    /// Re-arms feedback after `stop()`.
    func resumeFeedback() {
        haptics.resume()
        sounds.resume()
    }

    /// Runs the simulation forward by `dt` seconds without a display link, for tests and previews.
    /// Steps at most 1/30 s at a time, the longest frame the simulation accepts.
    func advance(by dt: TimeInterval) {
        guard layoutReady else { return }
        var remaining = dt
        var time = lastTime == 0 ? 1.0 / 60.0 : lastTime
        while remaining > 0 {
            let step = min(remaining, 1.0 / 30.0)
            time += step
            tick(time)
            remaining -= step
        }
    }

    // MARK: Private

    /// Seconds for the pin to slide fully in (or out). Short enough to feel like a click, long enough to see.
    /// (Computed because generic types can't have stored statics.)
    private static var insertDuration: CGFloat {
        0.11
    }

    private var socketEnabled = [ID: Bool]()
    /// Seated plug direction per socket (radians).
    private var socketAngles = [ID: CGFloat]()
    private var bounds = CGRect.zero
    private var restLength: CGFloat = 300
    private var maxLength: CGFloat = 360
    private var currentLength: CGFloat = 300
    /// Cap on the paid-out length while the plug hangs free (from `hangFraction`).
    private var hangLength: CGFloat = 300
    private var elasticExtension: CGFloat = 0
    private var elasticVelocity: CGFloat = 0
    /// 0…1 how hard a grabbed cable is being stretched beyond its length.
    private var grabTension: CGFloat = 0

    // Internals
    private var sim: RopeSimulation
    private var link: DisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var idleFrames = 0
    private var grabOffset = CGVector.zero
    private var fingerTarget = CGPoint.zero
    private var dragStart = CGPoint.zero
    /// A finger holding the cable somewhere along its length (node index + offset from the finger).
    private var cableGrab: (index: Int, offset: CGVector)?
    private var sparkStart: CFTimeInterval = 0
    private var gestureActive = false
    private var dragStartTime: CFTimeInterval = 0
    private var dragMoved: CGFloat = 0
    private var snapVelocity = CGVector.zero
    private var snapPos = CGPoint.zero
    private var lastCreakLevel: CGFloat = 0
    private var lastStretchEvent: CFTimeInterval = 0
    private var hoverChangedAt: CFTimeInterval = 0
    private var wasAirborne = false
    private var layoutReady = false
    /// Set by `updateConfig` when a length-related setting changed, so the next layout pass recomputes even
    /// though nothing moved.
    private var needsLengthRecompute = false
    /// Created on first use so a board that supplies its own providers never spins up the engines.
    @ObservationIgnored private lazy var defaultHaptics = DefaultCableHaptics()
    @ObservationIgnored private lazy var defaultSounds = SynthesizedCableSounds()
    #if os(iOS)
    private var motion: CMMotionManager?
    #endif
    private var deviceGravity = CGVector(dx: 0, dy: 1)

    private var headLength: CGFloat {
        config.plugStyle.length
    }

    private var insertTravel: CGFloat {
        config.plugStyle.insertTravel
    }

    private var holeRadius: CGFloat {
        config.plugStyle.socketFaceOffset
    }

    private var haptics: any CableHapticsProvider {
        config.haptics ?? defaultHaptics
    }

    private var sounds: any CableSoundProvider {
        config.sounds ?? defaultSounds
    }

    /// Unit vector the plug points along when seated in a socket.
    private func entryDirection(_ id: ID) -> CGVector {
        let a = socketAngles[id] ?? 0
        return CGVector(dx: cos(a), dy: sin(a))
    }

    /// Where the rope must end for the plug to sit in front of a socket, pin tip touching the hole
    /// at insertion 0 and fully inside (collar against the bezel) at insertion 1.
    private func ropeEnd(forSocket id: ID, insertion: CGFloat) -> CGPoint? {
        guard let p = socketPoints[id] else { return nil }
        let d = entryDirection(id)
        let back = holeRadius + headLength - insertTravel * insertion
        return CGPoint(x: p.x - d.dx * back, y: p.y - d.dy * back)
    }

    /// Tip position for a given insertion into a socket.
    private func tip(forSocket id: ID, insertion: CGFloat) -> CGPoint? {
        guard let end = ropeEnd(forSocket: id, insertion: insertion) else { return nil }
        let d = entryDirection(id)
        return CGPoint(x: end.x + d.dx * headLength, y: end.y + d.dy * headLength)
    }

    private func seatedTip(forSocket id: ID) -> CGPoint? {
        tip(forSocket: id, insertion: 1)
    }

    /// The point on the socket's face where the pin disappears (and sparks jump from).
    private func face(ofSocket id: ID) -> CGPoint? {
        guard let p = socketPoints[id] else { return nil }
        let d = entryDirection(id)
        return CGPoint(x: p.x - d.dx * holeRadius, y: p.y - d.dy * holeRadius)
    }

    /// Un-pauses the display link. Called after anything that changes the picture; `tick` pauses it again once
    /// the rope has been still for a while.
    private func wake() {
        idleFrames = 0
        link?.isPaused = false
    }

    private func updateMotion() {
        #if os(iOS)
        if config.gravityFollowsDevice, link != nil {
            guard motion == nil else { return }
            let m = CMMotionManager()
            guard m.isDeviceMotionAvailable else { return }
            m.deviceMotionUpdateInterval = 1 / 30
            m.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let g = data?.gravity else { return }
                // Device frame: x right, y up (toward the top of the screen). Screen y points down.
                var v = CGVector(dx: g.x, dy: -g.y)
                switch windowScene?.interfaceOrientation ?? .portrait {
                case .landscapeLeft: v = CGVector(dx: -v.dy, dy: v.dx)
                case .landscapeRight: v = CGVector(dx: v.dy, dy: -v.dx)
                case .portraitUpsideDown: v = CGVector(dx: -v.dx, dy: -v.dy)
                default: break
                }
                let previous = deviceGravity
                deviceGravity = v
                if abs(v.dx - previous.dx) + abs(v.dy - previous.dy) > 0.01 {
                    wake()
                }
            }
            motion = m
        } else {
            motion?.stopDeviceMotionUpdates()
            motion = nil
            deviceGravity = CGVector(dx: 0, dy: 1)
        }
        #else
        deviceGravity = CGVector(dx: 0, dy: 1)
        #endif
    }

    /// Release near a socket: let go of the rope's tail and drive the tip toward the socket mouth with a spring,
    /// starting from the tip's current velocity so the hand-off is seamless.
    private func beginSnap(to id: ID) {
        phase = .snapping(id)
        insertion = 0
        sim.entryDirection = entryDirection(id)
        snapPos = sim.tipPosition
        let v = sim.tipVelocity
        snapVelocity = CGVector(dx: v.dx * 60, dy: v.dy * 60)
        sim.tail = nil
        sim.alignTail = false
    }

    /// Plug is touching the socket: start sliding the pin in.
    private func beginInsert(_ id: ID) {
        phase = .inserting(id)
        insertion = 0
        sim.entryDirection = entryDirection(id)
        sim.alignTail = true
        if config.soundEnabled {
            sounds.insert()
        }
        if config.spark.includesPlugIn {
            startSpark(socket: id, intensity: 0.7)
        }
    }

    /// Pin is all the way in: the click.
    private func seat(_ id: ID) {
        phase = .plugged(id)
        insertion = 1
        sim.entryDirection = entryDirection(id)
        sim.tail = ropeEnd(forSocket: id, insertion: 1)
        sim.tipPin = seatedTip(forSocket: id)
        sim.alignTail = true
        socketPulse[id] = 1
        if config.hapticsEnabled {
            haptics.plugIn()
        }
        if config.soundEnabled {
            sounds.plugIn()
        }
        onEvent?(.plugged(id))
        onConnectionChange?(id)
    }

    /// Back to free-hanging: drop every pin so the rope falls under gravity.
    private func release() {
        phase = .hanging
        insertion = 0
        sim.tail = nil
        sim.tipPin = nil
        sim.alignTail = false
        sim.levelHead = 0
        wasAirborne = true
        onEvent?(.dropped)
    }

    /// Full-size arc with the big crackle (unplug, or the zap as the pin slides in).
    private func startSpark(socket id: ID, intensity: CGFloat = 1) {
        guard let from = face(ofSocket: id) else { return }
        sparkStart = CACurrentMediaTime()
        spark = Spark(
            from: from,
            progress: 0,
            seed: Int.random(in: 0..<1000),
            intensity: intensity,
            duration: config.sparkDuration * Double(0.6 + 0.4 * intensity),
        )
        if config.hapticsEnabled {
            haptics.spark()
        }
        if config.soundEnabled {
            sounds.spark()
        }
        wake()
    }

    /// Tiny intermittent arc while approaching a socket.
    private func startCrackle(socket id: ID, intensity: CGFloat) {
        guard let from = face(ofSocket: id) else { return }
        sparkStart = CACurrentMediaTime()
        spark = Spark(
            from: from,
            progress: 0,
            seed: Int.random(in: 0..<1000),
            intensity: 0.25 + intensity * 0.45,
            duration: 0.06 + Double(intensity) * 0.06,
        )
        if config.hapticsEnabled {
            haptics.crackle(intensity: intensity)
        }
        if config.soundEnabled {
            sounds.crackle(intensity: intensity)
        }
    }

    private func setHovered(_ id: ID?) {
        guard id != hovered else { return }
        hovered = id
        if id != nil {
            if config.hapticsEnabled {
                haptics.hover()
            }
            if config.soundEnabled {
                sounds.hover()
            }
        }
        onEvent?(.hover(id))
    }

    /// One frame. Order matters:
    /// 1. gravity (fixed, or from the device),
    /// 2. the phase drives the rope's pins (`tail`, `tipPin`) and the plug's levelling,
    /// 3. the take-up reel and elastic set the segment length,
    /// 4. the rope solves,
    /// 5. feedback that depends on the solved rope (floor impact, grabbed-cable creak),
    /// 6. cosmetic timers (socket pulse, spark, data traffic),
    /// 7. `publish()` copies the result into the observed properties, and the link sleeps if nothing moved.
    private func tick(_ time: CFTimeInterval) {
        guard layoutReady else { return }
        let dt = lastTime == 0 ? 1.0 / 60.0 : CGFloat(time - lastTime)
        lastTime = time

        // Gravity: straight down, or following the device.
        if config.gravityFollowsDevice {
            let g = deviceGravity
            let mag = max(hypot(g.dx, g.dy), 0.15) // flat on a table still settles
            sim.gravity = CGVector(
                dx: g.dx / max(hypot(g.dx, g.dy), 0.0001) * mag * config.gravity,
                dy: g.dy / max(hypot(g.dx, g.dy), 0.0001) * mag * config.gravity,
            )
        } else {
            sim.gravity = CGVector(dx: 0, dy: config.gravity)
        }

        switch phase {
        case .hanging:
            sim.tail = nil
            sim.tipPin = nil
            sim.levelHead = 0

        case .dragging:
            // The finger holds the tip of the plug; the body and cable trail behind it.
            var tip = CGPoint(x: fingerTarget.x - grabOffset.dx, y: fingerTarget.y - grabOffset.dy)

            // Nearest enabled socket, with hysteresis so sitting between two doesn't flicker.
            var best: (ID, CGFloat)?
            for (id, p) in socketPoints where socketEnabled[id] ?? true {
                let d = hypot(p.x - tip.x, p.y - tip.y)
                if d < config.snapRadius, d < (best?.1 ?? .infinity) {
                    best = (id, d)
                }
            }
            var next = best?.0
            if let current = hovered, let cp = socketPoints[current], socketEnabled[current] ?? true {
                let dCurrent = hypot(cp.x - tip.x, cp.y - tip.y)
                if dCurrent < config.snapRadius * 1.35 {
                    next = current
                    if
                        let (candidate, dCandidate) = best, candidate != current,
                        dCandidate < dCurrent - config.hoverSwitchMargin,
                        time - hoverChangedAt > config.hoverSwitchDelay
                    {
                        next = candidate
                    }
                }
            }
            if next != hovered {
                hoverChangedAt = time
            }
            setHovered(next)

            // Magnetic pull toward the socket mouth, and level the plug as it gets close. `closeness` is 0 at
            // the snap radius and 1 on the socket; the pull ramps in gently (power 1.5) and never exceeds 75%
            // so the finger stays in charge until release.
            var level: CGFloat = 0
            if let id = next, let p = socketPoints[id], let target = self.tip(forSocket: id, insertion: 0) {
                let d = hypot(p.x - tip.x, p.y - tip.y)
                let closeness = max(0, 1 - d / config.snapRadius)
                let pull = pow(closeness, 1.5) * 0.75
                tip.x += (target.x - tip.x) * pull
                tip.y += (target.y - tip.y) * pull
                level = closeness * 0.6
                sim.entryDirection = entryDirection(id)
            }
            sim.levelHead = level

            // Approach sparks: the closer the pin, the more often (and brighter) it arcs across the gap.
            if config.spark.includesPlugIn, spark == nil, let id = next, let p = socketPoints[id] {
                let d = hypot(p.x - tip.x, p.y - tip.y)
                let closeness = max(0, 1 - d / config.snapRadius)
                if closeness > 0.15, CGFloat.random(in: 0..<1) < closeness * closeness * 0.35 {
                    startCrackle(socket: id, intensity: closeness)
                }
            }

            // Cable length limit: past maxLength the plug stops following the finger.
            let dx = tip.x - anchor.x
            let dy = tip.y - anchor.y
            let dist = hypot(dx, dy) - headLength
            let rawStretch = (dist - restLength) / max(maxLength - restLength, 1)
            stretch = min(max(rawStretch, 0), 1)
            if dist > maxLength {
                let reach = maxLength + headLength
                let full = hypot(dx, dy)
                tip = CGPoint(x: anchor.x + dx / full * reach, y: anchor.y + dy / full * reach)
            }
            sim.tipPin = tip
            sim.tail = nil

            if config.hapticsEnabled {
                haptics.stretch(level: stretch)
            }
            if config.soundEnabled, stretch > 0.5, stretch - lastCreakLevel > 0.18 {
                sounds.creak(level: stretch)
                lastCreakLevel = stretch
            }
            if stretch < 0.3 {
                lastCreakLevel = 0
            }
            if stretch > 0.05, time - lastStretchEvent > 0.1 {
                onEvent?(.stretched(stretch))
                lastStretchEvent = time
            }

        case .tugging(let id):
            guard let seated = ropeEnd(forSocket: id, insertion: 1), let seatedTipPoint = seatedTip(forSocket: id) else { break }
            let d = entryDirection(id)
            let target = CGPoint(x: fingerTarget.x - grabOffset.dx, y: fingerTarget.y - grabOffset.dy)
            let delta = CGVector(dx: target.x - seatedTipPoint.x, dy: target.y - seatedTipPoint.y)
            // Only a little give along the pin axis (and only pulling out, never pushing in), more sideways:
            // 12% of the pull shows along the pin, 22% sideways — enough to feel the plug is held.
            let along = min(0, delta.dx * d.dx + delta.dy * d.dy) * 0.12
            let sideX = delta.dx - (delta.dx * d.dx + delta.dy * d.dy) * d.dx
            let sideY = delta.dy - (delta.dx * d.dx + delta.dy * d.dy) * d.dy
            let give = CGVector(dx: d.dx * along + sideX * 0.22, dy: d.dy * along + sideY * 0.22)
            sim.tail = CGPoint(x: seated.x + give.dx, y: seated.y + give.dy)
            sim.tipPin = CGPoint(x: seatedTipPoint.x + give.dx, y: seatedTipPoint.y + give.dy)
            sim.alignTail = true

        case .snapping(let id):
            guard let target = tip(forSocket: id, insertion: 0) else { release()
                break
            }
            // Critically-damped-ish spring of the tip to the socket mouth, then slide in. Sub-stepped so a
            // long frame (a hitch, or a device stuck at 30 fps) can't make the spring overshoot forever.
            let k: CGFloat = 1400
            let c: CGFloat = 52
            var remaining = dt
            while remaining > 0 {
                let h = min(remaining, 1 / 120)
                let ax = (target.x - snapPos.x) * k - snapVelocity.dx * c
                let ay = (target.y - snapPos.y) * k - snapVelocity.dy * c
                snapVelocity.dx += ax * h
                snapVelocity.dy += ay * h
                snapPos.x += snapVelocity.dx * h
                snapPos.y += snapVelocity.dy * h
                remaining -= h
            }

            sim.tipPin = snapPos
            sim.tail = nil
            sim.levelHead = 0.6
            let d = hypot(target.x - snapPos.x, target.y - snapPos.y)
            if d < 1.5, hypot(snapVelocity.dx, snapVelocity.dy) < 40 {
                beginInsert(id)
            }

        case .inserting(let id):
            guard socketPoints[id] != nil else { release()
                break
            }
            insertion = min(1, insertion + dt / Self.insertDuration)
            // Ease-in: the pin picks up speed then stops dead — that's the click.
            let eased = insertion * insertion
            sim.tail = ropeEnd(forSocket: id, insertion: eased)
            sim.tipPin = tip(forSocket: id, insertion: eased)
            if insertion >= 1 {
                seat(id)
            }

        case .ejecting(let id):
            guard socketPoints[id] != nil else { release()
                break
            }
            insertion = max(0, insertion - dt / Self.insertDuration)
            sim.tail = ropeEnd(forSocket: id, insertion: insertion)
            sim.tipPin = tip(forSocket: id, insertion: insertion)
            sim.alignTail = true
            if insertion <= 0 {
                phase = .dragging
                sim.tail = nil
                sim.alignTail = false
                // Re-base the grab so the head doesn't jump to the finger.
                let t = sim.tipPin ?? sim.tipPosition
                grabOffset = CGVector(dx: fingerTarget.x - t.x, dy: fingerTarget.y - t.y)
            }

        case .plugged(let id):
            if socketPoints[id] != nil {
                sim.tail = ropeEnd(forSocket: id, insertion: 1)
                sim.tipPin = seatedTip(forSocket: id)
            } else {
                release()
            }
        }

        updateSlack(dt: dt)
        if case .dragging = phase {
            sim.damping = config.dragDamping
        } else {
            sim.damping = config.damping
        }
        sim.step(dt: dt)

        // Stretching a grabbed cable: same creak + tension rumble as pulling the plug taut.
        if cableGrab != nil, config.cableGrabStretchFeedback {
            stretch = grabTension
            if config.hapticsEnabled {
                haptics.stretch(level: grabTension)
            }
            if config.soundEnabled, grabTension > 0.15, grabTension - lastCreakLevel > 0.15 {
                sounds.creak(level: grabTension * 0.35)
                lastCreakLevel = grabTension
            }
            if grabTension < lastCreakLevel - 0.25 {
                lastCreakLevel = max(0, grabTension)
            }
            if grabTension > 0.05, time - lastStretchEvent > 0.1 {
                onEvent?(.stretched(grabTension))
                lastStretchEvent = time
            }
        }

        // Plug hitting the floor after a drop.
        if case .hanging = phase, wasAirborne {
            let floorY = bounds.maxY - sim.floorInset
            let v = sim.tipVelocity
            let onFloor = sim.tipPosition.y >= floorY - 0.5 || sim.head.y >= floorY - 0.5
            if onFloor, v.dy >= 0 {
                let speed = hypot(v.dx, v.dy) * 60 / 10
                if speed > 3 {
                    if config.hapticsEnabled {
                        haptics.drop(velocity: speed)
                    }
                    if config.soundEnabled {
                        sounds.drop(velocity: speed)
                    }
                }
                wasAirborne = false
            }
        }

        // Pulse decay
        for (id, v) in socketPulse where v > 0 {
            socketPulse[id] = max(0, v - dt * 2.2)
        }

        // Unplug spark: advance and flicker, then clear.
        if var sp = spark {
            // The display link's timestamp can precede the moment the spark started; clamp at 0.
            let elapsed = max(0, time - sparkStart)
            let progress = CGFloat(elapsed / max(sp.duration, 0.03))
            if progress >= 1 {
                spark = nil
            } else {
                sp.progress = progress
                sp.seed = Int(elapsed * 45) // new jagged shape ~45×/s
                spark = sp
            }
        }

        // Data traffic: only flows while the plug is seated.
        let dataActive =
            if case .plugged = phase, config.dataFlow != .none {
                true
            } else {
                false
            }
        let targetOpacity: CGFloat = dataActive ? 1 : 0
        dataOpacity += (targetOpacity - dataOpacity) * min(1, dt * 6)
        if dataOpacity < 0.01 {
            dataOpacity = 0
        }
        if dataOpacity > 0 {
            dataPhase += config.dataFlowSpeed * dt
        }

        publish()

        // Sleep when nothing is happening: any gesture-bound phase, a live spark or a held cable keeps the
        // link running; otherwise wait for the rope, the pulses, the traffic fade and the elastic to settle.
        let busy: Bool =

            switch phase {
            case _ where cableGrab != nil || spark != nil: true
            case .dragging,
                 .tugging,
                 .snapping,
                 .inserting,
                 .ejecting: true
            default: sim.kineticEnergy > 0.08 || socketPulse.values.contains { $0 > 0 } || dataOpacity > 0 || elasticExtension > 0
            }
        idleFrames = busy ? 0 : idleFrames + 1
        if idleFrames > 30 {
            link?.isPaused = true
            lastTime = 0
        }
    }

    /// Take-up reel: keep only a little slack beyond what the cable has to span.
    /// A hanging cable only pays out (never reels in), otherwise length and drop chase each other forever.
    /// On top of that an elastic extension springs the length out when the cable is pulled taut.
    private func updateSlack(dt: CGFloat) {
        let end = sim.tail ?? sim.head
        var span = hypot(end.x - anchor.x, end.y - anchor.y)
        // Holding the cable somewhere along its length: it has to reach the finger and then the plug.
        if let g = sim.grabbedNode {
            span = hypot(g.position.x - anchor.x, g.position.y - anchor.y) + hypot(end.x - g.position.x, end.y - g.position.y)
        }
        if config.autoSlack {
            var wanted = min(restLength, max(span * 1.04 + config.slack, config.slack * 2))
            if case .hanging = phase, sim.grabbedNode == nil {
                // Free-hanging: pay out (never reel in while falling) but no further than the hang length,
                // so a plug dropped after a long drag gently retracts to where it should dangle.
                wanted = min(hangLength, max(wanted, currentLength))
            }
            currentLength += (wanted - currentLength) * min(1, dt * 7)
        } else {
            currentLength = restLength
        }

        // Elastic: only a hand pulling on the cable stretches it — never its own weight or a swing,
        // otherwise gravity would read as tension and the cable would balloon. An under-damped spring
        // toward how far the finger has pulled past the cable's length, so it twangs back on release.
        let e = min(max(config.elasticity, 0), 1)
        let pulledByHand: Bool =
            switch phase {
            case .dragging,
                 .tugging: true
            default: sim.grabbedNode != nil
            }
        let target = pulledByHand ? max(0, span - currentLength) * e * 0.9 : 0
        if sim.grabbedNode != nil {
            // Tension from stretching the held cable: excess span relative to a fifth of the cable.
            let excess = max(0, span - currentLength)
            grabTension = min(1, excess / max(restLength * 0.2, 1))
        } else {
            grabTension = 0
        }
        let k: CGFloat = 90 + (1 - e) * 200 // stiffer when less elastic
        let damping: CGFloat = 2 * sqrt(k) * (0.55 - e * 0.3) // less damped when more elastic → bouncier
        let accel = (target - elasticExtension) * k - elasticVelocity * damping
        elasticVelocity += accel * dt
        elasticExtension += elasticVelocity * dt
        elasticExtension = max(0, elasticExtension)
        if elasticExtension < 0.05, abs(elasticVelocity) < 0.5 {
            elasticExtension = 0
            elasticVelocity = 0
        }

        sim.segmentLength = (currentLength + elasticExtension) / CGFloat(sim.count - 1)
        // Softer rope only while it's being handled; free or plugged, it's an inextensible cable.
        sim.stiffness = pulledByHand ? 1 - e * 0.55 : 1
    }

    /// Copies the simulation's state into the properties the canvas observes. Kept separate so a frame can run
    /// several sub-steps (see `updateLayout`, `advance(by:)`) and notify SwiftUI once.
    private func publish() {
        points = sim.points
        // The plug is a rigid body in the simulation, so its angle is simply rope end → tip.
        headAngle = sim.headAngle

        pinClipX = nil
        switch phase {
        case .plugged(let id),
             .snapping(let id),
             .tugging(let id),
             .inserting(let id),
             .ejecting(let id):
            if let f = face(ofSocket: id) {
                let d = entryDirection(id)
                pinClipX = (f.x - sim.head.x) * d.dx + (f.y - sim.head.y) * d.dy
            }

        default: break
        }
    }

}

// MARK: - DisplayLink

/// CADisplayLink wrapper that doesn't retain its owner. On macOS the link comes from the main screen.
private final class DisplayLink {

    // MARK: Lifecycle

    init(_ handler: @escaping (CFTimeInterval) -> Void) {
        self.handler = handler
        #if os(macOS)
        link = NSScreen.main?.displayLink(target: self, selector: #selector(fire(_:)))
        #else
        link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        #endif
        // Ask for 60 and allow 120: the frame is dominated by blur and shadow filters, which older
        // devices can't sustain at 120, while ProMotion displays still get the smoother rate when idle.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)

        link?.add(to: .main, forMode: .common)
    }

    // MARK: Internal

    var isPaused: Bool {
        get { link?.isPaused ?? true }
        set { link?.isPaused = newValue }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }

    // MARK: Private

    private var link: CADisplayLink?
    private let handler: (CFTimeInterval) -> Void

    @objc
    private func fire(_ l: CADisplayLink) {
        handler(l.timestamp)
    }

}
