import SwiftUI

// MARK: - CableSourceEdge

/// Where the cable comes out of the source view.
public enum CableSourceEdge: Sendable { case trailing, leading, top, bottom, center }

// MARK: - CableMark

/// How content tells the board where things are. `cableSource` / `cableSocket` attach an anchor preference to
/// a view; the board collects every mark in its overlay and resolves the anchors into its own coordinate
/// space, so sources and sockets can live anywhere in the hierarchy, inside any layout.
struct CableMark {
    enum Kind {
        /// `nil` cable = the default source, used by every cable without its own.
        case source(AnyHashable?, CableSourceEdge)
        case socket(AnyHashable)
    }

    var kind: Kind
    var anchor: Anchor<CGRect>
}

// MARK: - CableMarkKey

struct CableMarkKey: PreferenceKey {
    static var defaultValue: [CableMark] {
        []
    }

    static func reduce(value: inout [CableMark], nextValue: () -> [CableMark]) {
        value += nextValue()
    }
}

extension View {
    /// Marks this view as the device the cable comes out of. Use inside a ``CableBoard``. On a board with
    /// several cables this is the source for every cable that has no ``cableSource(for:edge:)`` of its own.
    public func cableSource(edge: CableSourceEdge = .trailing) -> some View {
        anchorPreference(key: CableMarkKey.self, value: .bounds) { [CableMark(kind: .source(nil, edge), anchor: $0)] }
    }

    /// Marks this view as the device one particular cable comes out of, on a board with several cables.
    public func cableSource(for cable: some Hashable, edge: CableSourceEdge = .trailing) -> some View {
        anchorPreference(key: CableMarkKey.self, value: .bounds) {
            [CableMark(kind: .source(AnyHashable(cable), edge), anchor: $0)]
        }
    }

    /// Marks this view as the receptacle for a socket: the plug's tip lands on its centre. Use inside a ``CableBoard``.
    public func cableSocket(_ id: some Hashable) -> some View {
        anchorPreference(key: CableMarkKey.self, value: .bounds) { [CableMark(kind: .socket(AnyHashable(id)), anchor: $0)] }
    }
}

// MARK: - CableSocketStates

/// Live state of every socket, keyed by id, available to views inside a ``CableBoard``.
///
/// `Equatable` so SwiftUI only re-evaluates socket views when something they can see changed, not on
/// every frame the cable moves.
public struct CableSocketStates: Equatable {

    // MARK: Public

    /// Hover / connected / seated state of a socket. Unknown ids read as idle.
    public subscript(id: some Hashable) -> SocketRowState {
        states[AnyHashable(id)] ?? SocketRowState(isHovered: false, isConnected: false, isSeated: false)
    }

    /// 1 → 0 pulse right after the plug seats in this socket.
    public func pulse(_ id: some Hashable) -> CGFloat {
        pulses[AnyHashable(id)] ?? 0
    }

    /// The socket's `entryAngle`.
    public func entryAngle(_ id: some Hashable) -> Angle {
        angles[AnyHashable(id)] ?? .zero
    }

    /// The plug style to draw this socket with: the style of the cable in it (or hovering over it),
    /// else the first style the socket accepts, else `nil` for the board's default.
    public func plugStyle(_ id: some Hashable) -> PlugStyle? {
        styles[AnyHashable(id)]
    }

    // MARK: Internal

    var states = [AnyHashable: SocketRowState]()
    var pulses = [AnyHashable: CGFloat]()
    var angles = [AnyHashable: Angle]()
    var styles = [AnyHashable: PlugStyle]()

}

extension EnvironmentValues {
    /// Hover / connected / seated state of each socket inside a ``CableBoard``.
    @Entry public var cableSocketStates = CableSocketStates()

    /// The plug style in effect inside a ``CableBoard``.
    @Entry public var cablePlugStyle = PlugStyle.audioJack

    /// Connects to / disconnects from a socket, as tapping it would. Call with the socket's id.
    public var cableToggleSocket: (AnyHashable) -> Void {
        get { self[CableToggleKey.self] }
        set { self[CableToggleKey.self] = newValue }
    }
}

// MARK: - CableToggleKey

/// Kept as a manual key: `@Entry` warns about closures because they can't be compared, and every
/// socket view already re-evaluates whenever ``CableSocketStates`` changes.
// swiftformat:disable:next environmentEntry
private struct CableToggleKey: EnvironmentKey {
    /// The default captures nothing, so it is safe to share; the closure type itself can't be `Sendable`
    /// because the real value captures the board.
    nonisolated(unsafe) static let defaultValue: (AnyHashable) -> Void = { _ in }
}

// MARK: - CableBoard

/// Free-layout cable: put the source and the sockets anywhere in `content` and mark them with
/// ``SwiftUI/View/cableSource(edge:)`` and ``SwiftUI/View/cableSocket(_:)``. The cable, plug,
/// gestures and feedback are laid over the content. ``CablePatchView`` is a `CableBoard` with a
/// left-device / right-column layout.
///
/// ```swift
/// CableBoard(sockets: sockets, connection: $connection) {
///     ZStack {
///         HubView().cableSource(edge: .center)
///         ForEach(sockets) { socket in
///             CableSocketPortView(id: socket.id, tint: socket.tint)
///                 .offset(x: ..., y: ...)
///         }
///     }
/// }
/// ```
///
/// A board can also carry several cables at once — a patch bay, a wiring puzzle:
///
/// ```swift
/// CableBoard(cables: [PlugCable(id: "left"), PlugCable(id: "right", configuration: blue)],
///            sockets: sockets, connections: $connections) {
///     ZStack {
///         MixerView().cableSource(for: "left", edge: .bottom)
///         DeckView().cableSource(for: "right", edge: .bottom)
///         …
///     }
/// }
/// ```
///
/// `connections` maps each cable id to the socket it is in. A socket holds one plug at a time, and
/// ``PlugSocket/accepts`` can restrict which plug styles fit. Every cable can have its own
/// ``CableConfiguration``; ``CableEvent``s arrive with the cable id.
///
/// Socket views can read `@Environment(\.cableSocketStates)` to light up, and call
/// `@Environment(\.cableToggleSocket)` to connect on tap (``CableSocketPortView`` does both).
public struct CableBoard<CableID: Hashable, ID: Hashable, Content: View>: View {

    // MARK: Lifecycle

    /// A board with several cables. See ``CableBoard``.
    public init(
        cables: [PlugCable<CableID>],
        sockets: [PlugSocket<ID>],
        connections: Binding<[CableID: ID]>,
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableID, CableEvent<ID>) -> Void)? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.cables = cables
        self.sockets = sockets
        socketAngles = Dictionary(uniqueKeysWithValues: sockets.map { ($0.id, CGFloat($0.entryAngle.radians)) })
        socketEnabled = Dictionary(uniqueKeysWithValues: sockets.map { ($0.id, $0.isEnabled) })
        _connections = connections

        config = configuration
        self.onEvent = onEvent
        self.content = content()
        var controllers = [CableID: CableController<ID>]()
        for cable in cables {
            let c = CableController<ID>(config: cable.configuration ?? configuration)
            c.setConnection(connections.wrappedValue[cable.id], animated: false)
            controllers[cable.id] = c
        }
        _controllers = State(initialValue: controllers)
    }

    // MARK: Public

    /// Layering, bottom to top: the caller's `content` (with socket state in the environment), then one
    /// `CableCanvas` per cable in an overlay driven by the collected marks. The overlay owns the drag gesture
    /// and a hit shape that follows the plugs and cables, so touches anywhere else fall through to the
    /// content underneath.
    public var body: some View {
        let occupancy = occupancy
        // Assigning closures on the controllers is a plain pointer store (they're ignored by observation),
        // so doing it here keeps `onEvent` and the binding current even when the parent passes new ones.
        wire()
        return content
            .environment(\.cableSocketStates, socketStates)
            .environment(\.cablePlugStyle, config.plugStyle)
            .environment(\.cableTheme, theme)
            .environment(\.cableToggleSocket) { id in
                if let id = id.base as? ID {
                    toggle(id)
                }
            }
            .overlayPreferenceValue(CableMarkKey.self) { marks in
                GeometryReader { proxy in
                    let layout = resolve(marks, in: proxy)
                    CableInteractionLayer(
                        cables: cables,
                        controllers: controllers,
                        theme: theme,
                        frontCable: $frontCable,
                        configuration: configuration(for:),
                    )
                    .onChange(of: layout, initial: true) { _, new in
                        currentLayout.value = new
                        sync(new)
                    }
                }
            }
            .onAppear {
                isVisible = true
                for value in controllers.values { value.start() }
            }
            .onDisappear {
                isVisible = false
                for value in controllers.values { value.stop() }
            }
            .background(windowSceneProbe)
            // App to the background (or inactive, e.g. app switcher): everything off. Back: everything on —
            // but only for a board that is actually on screen; a hidden tab stays stopped until it appears.
            .onChange(of: scenePhase) { _, phase in
                for controller in controllers.values {
                    if phase == .active, isVisible {
                        controller.start()
                    } else {
                        controller.stop()
                    }
                }
            }
            .onChange(of: connections) { _, new in
                for cable in cables {
                    controllers[cable.id]?.setConnection(new[cable.id])
                }
            }
            .onChange(of: cables.map(\.id)) { _, _ in reconcileControllers() }
            .onChange(of: cables.map { configuration(for: $0) }) { _, _ in
                for cable in cables {
                    controllers[cable.id]?.updateConfig(configuration(for: cable))
                }
            }
            // A socket taken by one cable is off-limits to the others, so occupancy feeds the enabled maps.
            .onChange(of: occupancy) { _, _ in
                if let layout = currentLayout.value {
                    sync(layout)
                }
            }
    }

    // MARK: Private

    private final class LayoutBox {
        var value: Layout?
    }

    private struct Layout: Equatable {
        /// One anchor per cable: its own source mark, else the default mark, else the left edge.
        var anchors: [CableID: CGPoint]
        var sockets: [ID: CGPoint]
        var angles: [ID: CGFloat]
        /// Part of the layout so a socket being enabled or disabled at runtime reaches the controller.
        var enabled: [ID: Bool]
        var bounds: CGRect
    }

    @Binding private var connections: [CableID: ID]
    @State private var controllers: [CableID: CableController<ID>]
    @State private var frontCable: CableID?
    /// The last resolved layout, kept for re-syncing when occupancy changes. A reference box rather than a
    /// `@State` value: writing it from `onChange(of: layout)` must not invalidate this view again in the same
    /// frame (SwiftUI faults on that).
    @State private var currentLayout = LayoutBox()
    /// Between `onAppear` and `onDisappear`; gates restarting on scene activation.
    @State private var isVisible = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.cableTheme) private var environmentTheme
    @Environment(\.scenePhase) private var scenePhase

    private let cables: [PlugCable<CableID>]
    private let sockets: [PlugSocket<ID>]
    // Derived from `sockets` once per view value rather than on every layout resolve.
    private let socketAngles: [ID: CGFloat]
    private let socketEnabled: [ID: Bool]
    private let config: CableConfiguration
    private let content: Content
    private let onEvent: ((CableID, CableEvent<ID>) -> Void)?

    private var theme: CableTheme {
        config.theme ?? environmentTheme ?? .automatic(for: scheme)
    }

    /// Feeds the window scene to the controllers so device gravity can follow the interface orientation.
    @ViewBuilder
    private var windowSceneProbe: some View {
        #if os(iOS)
        WindowSceneProbe { scene in for value in controllers.values { value.windowScene = scene } }
        #else
        EmptyView()
        #endif
    }

    /// Which cable is connected to (snapping, inserting or seated in) which socket. A socket takes one plug
    /// at a time, so this feeds each controller's enabled map.
    private var occupancy: [ID: CableID] {
        var map = [ID: CableID]()
        for cable in cables {
            if let socket = controllers[cable.id]?.connected {
                map[socket] = cable.id
            }
        }
        return map
    }

    /// What socket views see: hover / connection state merged across every cable, keyed by socket id. Pushed
    /// through the environment; being `Equatable`, SwiftUI only re-renders sockets when this actually changes.
    private var socketStates: CableSocketStates {
        var s = CableSocketStates()
        for socket in sockets {
            var state = SocketRowState()
            var pulse: CGFloat = 0
            var style = socket.accepts?.first
            for cable in cables {
                guard let controller = controllers[cable.id] else { continue }
                let connected = controller.connected == socket.id
                let hovered = controller.hovered == socket.id
                if connected || hovered {
                    state.cableID = AnyHashable(cable.id)
                    style = configuration(for: cable).plugStyle
                }
                state.isHovered = state.isHovered || hovered
                state.isConnected = state.isConnected || connected
                state.isSeated = state.isSeated || controller.phase == .plugged(socket.id)
                pulse = max(pulse, controller.socketPulse[socket.id] ?? 0)
            }
            s.states[AnyHashable(socket.id)] = state
            s.pulses[AnyHashable(socket.id)] = pulse
            s.angles[AnyHashable(socket.id)] = socket.entryAngle
            if let style {
                s.styles[AnyHashable(socket.id)] = style
            }
        }
        return s
    }

    private func configuration(for cable: PlugCable<CableID>) -> CableConfiguration {
        cable.configuration ?? config
    }

    /// Hooks each controller's callbacks to the binding and the event closure. Runs on every body
    /// evaluation so the controllers never hold a stale closure.
    private func wire() {
        let binding = _connections
        for cable in cables {
            guard let controller = controllers[cable.id] else { continue }
            let id = cable.id
            // Only write when it differs: the first layout pass seats a preset connection, and echoing the
            // binding's own value back would re-render the parent for nothing.
            controller.onConnectionChange = { socket in
                if binding.wrappedValue[id] != socket {
                    binding.wrappedValue[id] = socket
                }
            }

            controller.onEvent = { [onEvent] event in onEvent?(id, event) }
        }
    }

    /// Cables added or removed at runtime get a controller created or torn down.
    private func reconcileControllers() {
        let ids = Set(cables.map(\.id))
        for (id, controller) in controllers where !ids.contains(id) {
            controller.stop()
            controllers[id] = nil
        }
        for cable in cables where controllers[cable.id] == nil {
            let c = CableController<ID>(config: configuration(for: cable))
            c.setConnection(connections[cable.id], animated: false)
            controllers[cable.id] = c
            c.start()
        }
        wire()
        if let layout = currentLayout.value {
            sync(layout)
        }
    }

    /// Tap on a socket: unplug whatever is in it, else plug the nearest free cable that fits.
    private func toggle(_ socket: ID) {
        if let cableID = occupancy[socket] {
            controllers[cableID]?.tapSocket(socket)
            return
        }
        guard
            let target = sockets.first(where: { $0.id == socket }),
            let point = currentLayout.value?.sockets[socket]
        else { return }
        let fitting = cables.filter { target.accepts(configuration(for: $0).plugStyle) }
        let free = fitting.filter { controllers[$0.id]?.connected == nil }
        let candidates = free.isEmpty ? fitting : free
        let nearest = candidates.min { a, b in
            distance(controllers[a.id]?.headCenter, point) < distance(controllers[b.id]?.headCenter, point)
        }
        if let nearest {
            frontCable = nearest.id
            controllers[nearest.id]?.tapSocket(socket)
        }
    }

    /// Turns the collected marks into concrete points in the overlay's coordinate space. A source mark
    /// without a cable id is the default anchor; cables without their own mark share it, and a board with no
    /// source mark at all anchors on the left edge, vertically centred.
    private func resolve(_ marks: [CableMark], in proxy: GeometryProxy) -> Layout {
        var defaultAnchor = CGPoint(x: 0, y: proxy.size.height / 2)
        var anchors = [CableID: CGPoint]()
        var points = [ID: CGPoint]()
        for mark in marks {
            let f = proxy[mark.anchor]
            switch mark.kind {
            case .source(let cable, let edge):
                let anchor =
                    switch edge {
                    case .trailing: CGPoint(x: f.maxX - 2, y: f.midY)
                    case .leading: CGPoint(x: f.minX + 2, y: f.midY)
                    case .top: CGPoint(x: f.midX, y: f.minY + 2)
                    case .bottom: CGPoint(x: f.midX, y: f.maxY - 2)
                    case .center: CGPoint(x: f.midX, y: f.midY)
                    }
                if let cable {
                    if let id = cable.base as? CableID {
                        anchors[id] = anchor
                    }
                } else {
                    defaultAnchor = anchor
                }

            case .socket(let any):
                if let id = any.base as? ID {
                    points[id] = CGPoint(x: f.midX, y: f.midY)
                }
            }
        }
        for cable in cables where anchors[cable.id] == nil {
            anchors[cable.id] = defaultAnchor
        }
        return Layout(
            anchors: anchors,
            sockets: points,
            angles: socketAngles,
            enabled: socketEnabled,
            bounds: CGRect(origin: .zero, size: proxy.size),
        )
    }

    /// Pushes a resolved layout into every controller, with the enabled map narrowed per cable: a socket must
    /// be enabled, accept this cable's plug style, and not be taken by another cable.
    private func sync(_ layout: Layout) {
        // Sockets without a `cableSocket(_:)` mark simply can't be reached; the rest still work.
        let placed = sockets.filter { layout.sockets[$0.id] != nil }
        guard !placed.isEmpty || sockets.isEmpty else { return }
        let occupancy = occupancy
        let angles = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, CGFloat($0.entryAngle.radians)) })
        for cable in cables {
            guard let controller = controllers[cable.id], let anchor = layout.anchors[cable.id] else { continue }
            let style = configuration(for: cable).plugStyle
            var enabled = [ID: Bool]()
            for socket in placed {
                let taken = occupancy[socket.id].map { $0 != cable.id } ?? false
                enabled[socket.id] = (layout.enabled[socket.id] ?? true) && socket.accepts(style) && !taken
            }
            controller.updateLayout(
                anchor: anchor,
                sockets: layout.sockets,
                enabled: enabled,
                angles: angles,
                bounds: layout.bounds,
            )
        }
    }

}

extension CableBoard where CableID == SingleCable {
    /// A board with one cable. See ``CableBoard``.
    public init(
        sockets: [PlugSocket<ID>],
        connection: Binding<ID?>,
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableEvent<ID>) -> Void)? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        let single = SingleCable()
        self.init(
            cables: [PlugCable(id: single)],
            sockets: sockets,
            connections: Binding(
                get: { connection.wrappedValue.map { [single: $0] } ?? [:] },
                set: { connection.wrappedValue = $0[single] },
            ),
            configuration: configuration,
            onEvent: onEvent.map { handler in { _, event in handler(event) } },
            content: content,
        )
    }
}

// MARK: - CableInteractionLayer

/// The canvases, the hit shape and the drag gesture for every cable on a board.
///
/// This is its own view so that reading the live rope (`controller.points`, `headCenter`) for hit-testing
/// subscribes only this leaf to the physics. ``CableBoard/body`` then re-evaluates when socket state or
/// layout changes, not on every frame the cable moves.
private struct CableInteractionLayer<CableID: Hashable, ID: Hashable>: View {

    // MARK: Internal

    let cables: [PlugCable<CableID>]
    let controllers: [CableID: CableController<ID>]
    let theme: CableTheme
    /// The cable drawn on top and tried first for touches; shared with the board so socket taps can raise a cable.
    @Binding var frontCable: CableID?

    let configuration: (PlugCable<CableID>) -> CableConfiguration

    var body: some View {
        ZStack {
            ForEach(cables) { cable in
                if let controller = controllers[cable.id] {
                    CableCanvas(controller: controller, config: configuration(cable), theme: theme)
                        .zIndex(cable.id == frontCable ? 1 : 0)
                }
            }
        }
        .contentShape(MultiCableHitShape(cables: hitRegions))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if activeCable == nil {
                        activeCable = cable(at: value.startLocation)
                        frontCable = activeCable
                    }
                    if let id = activeCable {
                        controllers[id]?.dragChanged(at: value.location, start: value.startLocation)
                    }
                }
                .onEnded { _ in
                    if let id = activeCable {
                        controllers[id]?.dragEnded()
                    }
                    activeCable = nil
                }
        )
        .accessibilityHidden(true) // socket views are the accessible path to connecting
    }

    // MARK: Private

    /// The cable the current gesture holds, decided on its first sample.
    @State private var activeCable: CableID?

    /// Touch targets for every cable, rebuilt from the live rope so the hit shape follows the physics.
    private var hitRegions: [MultiCableHitShape.Region] {
        cables.compactMap { cable in
            guard let controller = controllers[cable.id] else { return nil }
            let c = configuration(cable)
            return MultiCableHitShape.Region(
                head: controller.headCenter,
                headRadius: c.plugHitRadius,
                points: c.cableGrabEnabled ? controller.points : [],
                cableWidth: (c.cableHitRadius + c.cable.width / 2) * 2,
            )
        }
    }

    /// The cable a touch starts on: a plug first (the one drawn on top wins), else the nearest cable.
    private func cable(at p: CGPoint) -> CableID? {
        let ordered = cables.map(\.id).sorted { a, _ in a != frontCable } // front cable last
        if let hit = ordered.last(where: { controllers[$0]?.isOnPlug(p) ?? false }) {
            return hit
        }
        var best: (CableID, CGFloat)?
        for cable in cables {
            guard let controller = controllers[cable.id] else { continue }
            let c = configuration(cable)
            let d = c.cableGrabEnabled ? controller.cableDistance(to: p) : .infinity
            if d <= c.cableHitRadius + c.cable.width, d < (best?.1 ?? .infinity) {
                best = (cable.id, d)
            }
        }
        if let best {
            return best.0
        }
        // The hit shape said yes, so something is close: fall back to the nearest plug.
        return cables.min { a, b in
            distance(controllers[a.id]?.headCenter, p) < distance(controllers[b.id]?.headCenter, p)
        }?.id
    }

}

/// Distance between two points, infinite when the first is missing (a cable without a controller).
private func distance(_ a: CGPoint?, _ b: CGPoint) -> CGFloat {
    guard let a else { return .infinity }
    return hypot(a.x - b.x, a.y - b.y)
}

// MARK: - MultiCableHitShape

/// Hit area of every cable on the board: a circle around each plug body plus a fat stroke along each cable.
struct MultiCableHitShape: Shape {
    struct Region {
        var head: CGPoint
        var headRadius: CGFloat
        var points: [CGPoint]
        var cableWidth: CGFloat
    }

    var cables: [Region]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for c in cables {
            p
                .addPath(CableHitShape(head: c.head, headRadius: c.headRadius, points: c.points, cableWidth: c.cableWidth)
                    .path(in: rect))
        }
        return p
    }
}

// MARK: - CableHitShape

/// Hit area: a circle around the plug body plus a fat stroke along the cable.
struct CableHitShape: Shape {
    var head: CGPoint
    var headRadius: CGFloat
    var points: [CGPoint]
    var cableWidth: CGFloat

    func path(in _: CGRect) -> Path {
        var p = Path(ellipseIn: CGRect(
            x: head.x - headRadius,
            y: head.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2,
        ))
        if points.count > 2 {
            var line = Path()
            line.move(to: points[0])
            for pt in points.dropFirst() { line.addLine(to: pt) }
            p.addPath(line.strokedPath(StrokeStyle(lineWidth: cableWidth, lineCap: .round, lineJoin: .round)))
        }
        return p
    }
}

// MARK: - CableSocketPortView

/// The receptacle for a socket, drawn by the current plug style, wired to hover / connection state,
/// and tappable to connect. Place it anywhere inside a ``CableBoard``; it marks itself with
/// ``SwiftUI/View/cableSocket(_:)``.
///
/// The cable overlay is hidden from assistive technologies, so this button is the VoiceOver path to
/// connecting: give it an `accessibilityLabel` that names the socket.
public struct CableSocketPortView<ID: Hashable>: View {

    // MARK: Lifecycle

    /// - Parameters:
    ///   - id: The socket this port belongs to.
    ///   - tint: Colour of the ring and hover glow.
    ///   - accessibilityLabel: What VoiceOver calls the socket. Defaults to a localized "Socket".
    public init(id: ID, tint: Color = .accentColor, accessibilityLabel: Text? = nil) {
        self.id = id
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel ?? CableStrings.socket
    }

    // MARK: Public

    public var body: some View {
        let state = states[id]
        let theme = environmentTheme ?? .automatic(for: scheme)
        ZStack {
            Circle()
                .fill(tint.opacity(state.isHovered ? 0.35 : 0))
                .frame(width: 60, height: 60)
                .blur(radius: 10)
            (states.plugStyle(id) ?? style).socket(SocketContext(
                theme: theme,
                tint: tint,
                isHovered: state.isHovered,
                isConnected: state.isConnected,
                isSeated: state.isSeated,
                pulse: states.pulse(id),
            ))
            .rotationEffect(states.entryAngle(id)) // artwork faces the way the plug comes in
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .onTapGesture { toggle(AnyHashable(id)) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(CableStrings.value(connected: state.isConnected))
        .accessibilityHint(CableStrings.hint(connected: state.isConnected))
        .accessibilityAction { toggle(AnyHashable(id)) }
        .animation(.easeOut(duration: 0.18), value: state.isHovered)
        .animation(.easeOut(duration: 0.12), value: state.isSeated)
        .cableSocket(id)
    }

    // MARK: Internal

    let id: ID
    let tint: Color
    let accessibilityLabel: Text

    // MARK: Private

    @Environment(\.cableSocketStates) private var states
    @Environment(\.cablePlugStyle) private var style
    @Environment(\.cableTheme) private var environmentTheme
    @Environment(\.cableToggleSocket) private var toggle
    @Environment(\.colorScheme) private var scheme

}

#if os(iOS)
// MARK: - WindowSceneProbe

/// Zero-size view that reports the `UIWindowScene` it ends up in, so the controller can map device
/// gravity to the interface orientation without going through `UIApplication.shared`.
private struct WindowSceneProbe: UIViewRepresentable {
    final class ProbeView: UIView {
        var onScene: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onScene?(window?.windowScene)
        }
    }

    let onScene: (UIWindowScene?) -> Void

    func makeUIView(context _: Context) -> ProbeView {
        let view = ProbeView()
        view.onScene = onScene
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_: ProbeView, context _: Context) { }
}
#endif
