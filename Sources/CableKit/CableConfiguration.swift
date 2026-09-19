import SwiftUI

// MARK: - DataFlowStyle

/// Animated traffic shown inside the cable while it is plugged in.
public enum DataFlowStyle: Equatable, Sendable {
    /// No animation.
    case none
    /// Irregular packets streaming along the cable.
    case bits
    /// The message encoded in Morse code, repeating along the cable.
    case morse(String)

    // MARK: Internal

    /// On/off run lengths in "units" (dot = 1). Even indices are lit, odd are gaps.
    var pattern: [CGFloat] {
        switch self {
        case .none: []
        case .bits: [1, 1.5, 1, 1.5, 3, 1.5, 1, 4, 3, 1.5, 3, 1.5, 1, 1.5, 1, 6, 3, 4, 1, 1.5, 1, 1.5, 1, 8]
        case .morse(let text): Self.morsePattern(text)
        }
    }

    // MARK: Private

    private static let morse: [Character: String] = [
        "A": ".-",
        "B": "-...",
        "C": "-.-.",
        "D": "-..",
        "E": ".",
        "F": "..-.",
        "G": "--.",
        "H": "....",
        "I": "..",
        "J": ".---",
        "K": "-.-",
        "L": ".-..",
        "M": "--",
        "N": "-.",
        "O": "---",
        "P": ".--.",
        "Q": "--.-",
        "R": ".-.",
        "S": "...",
        "T": "-",
        "U": "..-",
        "V": "...-",
        "W": ".--",
        "X": "-..-",
        "Y": "-.--",
        "Z": "--..",
        "0": "-----",
        "1": ".----",
        "2": "..---",
        "3": "...--",
        "4": "....-",
        "5": ".....",
        "6": "-....",
        "7": "--...",
        "8": "---..",
        "9": "----.",
    ]

    private static func morsePattern(_ text: String) -> [CGFloat] {
        var out = [CGFloat]()
        for word in text.uppercased().split(separator: " ") {
            for ch in word {
                guard let code = morse[ch] else { continue }
                for symbol in code {
                    out.append(symbol == "." ? 1 : 3)
                    out.append(1)
                }
                out[out.count - 1] = 3 // letter gap
            }
            if !out.isEmpty {
                out[out.count - 1] = 7
            } // word gap
        }
        return out.isEmpty ? [1, 3] : out
    }
}

// MARK: - SparkTrigger

/// When the cable throws electric sparks.
public enum SparkTrigger: String, CaseIterable, Equatable, Sendable {
    /// Never.
    case none
    /// Small arcs flicker as the pin approaches a socket, and a zap as it slides in.
    case plugIn
    /// A crackling arc as the plug is pulled out.
    case unplug
    /// Both of the above.
    case both

    // MARK: Lifecycle

    init(plugIn: Bool, unplug: Bool) {
        switch (plugIn, unplug) {
        case (true, true): self = .both
        case (true, false): self = .plugIn
        case (false, true): self = .unplug
        case (false, false): self = .none
        }
    }

    // MARK: Internal

    var includesPlugIn: Bool {
        self == .plugIn || self == .both
    }

    var includesUnplug: Bool {
        self == .unplug || self == .both
    }
}

// MARK: - DataFlowDirection

/// Which way the traffic travels along the cable.
public enum DataFlowDirection: Equatable, Sendable {
    /// From the plugged socket back to the source device (data being pulled in). Default.
    case toSource
    /// From the source device out to the plugged socket (data being pushed out).
    case toSocket
}

// MARK: - CableConfiguration

/// Everything that shapes how the cable looks, moves, sounds and feels.
///
/// The defaults are what the demo ships with. Change a copy and pass it to ``CablePatchView``;
/// changes apply live, even while the cable is plugged in.
///
/// ```swift
/// var config = CableConfiguration()
/// config.plugStyle = .usbC
/// config.cable.color = .cyan
/// config.elasticity = 0.8
/// config.dataFlow = .morse("SYNC")
/// config.haptics = MyHaptics()          // any CableHapticsProvider
/// ```
public struct CableConfiguration: Equatable {

    // MARK: Lifecycle

    /// The defaults: an orange audio-jack cable with sound, haptics, bit traffic and unplug sparks.
    public init() { }

    // MARK: Public

    /// Connector on the end of the cable. Built-ins: `.audioJack`, `.europlug`, `.usbC`, `.banana`, `.ethernet`, `.magSafe`, `.telephone`, `.idc`, `.electrode`.
    public var plugStyle = PlugStyle.audioJack
    /// How the cable is drawn. `CableStyle()` is a plain tube; presets: `.coiled()`, `.ribbon()`, `.neon()`.
    public var cable = CableStyle()
    /// Colours for cards, sockets and the source device. `nil` follows the system light/dark appearance.
    /// Can also be set for a whole hierarchy with `View.cableTheme(_:)`.
    public var theme: CableTheme? = nil

    /// Rest length in points. `nil` derives it from the layout: long enough for every socket, and for a
    /// free-hanging plug to reach ``hangFraction`` of the way down the view.
    public var restLength: CGFloat? = nil
    /// How far down the view a free-hanging plug reaches, as a fraction of the distance from the source
    /// port to the bottom edge (1 = rests on the floor, 0.6 = dangles 60% down). The full ``restLength``
    /// is still available while dragging and when plugged in; the cable retracts to this when dropped.
    public var hangFraction: CGFloat = 1
    /// How far past rest length the cable can be pulled (ratio). 1.22 = 22% stretch, then the plug stops following.
    public var maxStretch: CGFloat = 1.22
    /// How springy the cable is (0 = inextensible rope, 1 = bungee). Pulled taut it lengthens and bounces back.
    public var elasticity: CGFloat = 0.5
    /// Number of rope segments. More = smoother, slightly more CPU.
    public var segmentCount = 30
    /// Gravity in points / s².
    public var gravity: CGFloat = 2600
    /// Tilt the phone and the cable swings with it (Core Motion). Magnitude still comes from ``gravity``.
    public var gravityFollowsDevice = false
    /// Per-frame velocity retention (0…1). Lower = more viscous.
    public var damping: CGFloat = 0.985
    /// Damping used while the plug is being dragged, so the slack doesn't whip around.
    public var dragDamping: CGFloat = 0.955
    /// Keep the cable only slightly longer than the distance it spans (take-up reel behaviour).
    public var autoSlack = true
    /// Extra length beyond the straight-line distance when ``autoSlack`` is on.
    public var slack: CGFloat = 36

    /// Distance from a socket at which the plug starts being attracted and snaps on release.
    public var snapRadius: CGFloat = 60
    /// Another socket must be this much closer than the hovered one before the plug switches to it.
    public var hoverSwitchMargin: CGFloat = 22
    /// Minimum time the plug stays on a hovered socket before it can switch to another.
    public var hoverSwitchDelay: TimeInterval = 0.18
    /// How far a plugged-in head must be tugged before it pops out. A tap ejects it too.
    public var unplugDistance: CGFloat = 38
    /// Touch radius around the plug body that begins a drag.
    public var plugHitRadius: CGFloat = 46
    /// The cable itself can be grabbed anywhere along its length and flicked around.
    public var cableGrabEnabled = true
    /// Touch slop around the cable for grabbing it, in points (half the total hit width).
    public var cableHitRadius: CGFloat = 16
    /// How loosely the cable is held when grabbed (0 = rigidly pinned to the finger, 1 = very loose, lagging behind).
    public var cableGrabSoftness: CGFloat = 0.55
    /// Creak and tension haptics when a grabbed cable is stretched (uses the same stretch feedback as pulling the plug).
    public var cableGrabStretchFeedback = true

    /// Traffic animation shown while plugged in.
    public var dataFlow = DataFlowStyle.bits
    /// Direction of travel. Defaults to flowing from the socket into the source.
    public var dataFlowDirection = DataFlowDirection.toSource
    /// Speed of the traffic along the cable, in points per second.
    public var dataFlowSpeed: CGFloat = 120
    /// Length of one Morse/bit unit in points.
    public var dataFlowUnit: CGFloat = 4
    /// Colour of the packets. `nil` = white.
    public var dataFlowColor: Color? = nil
    /// Thickness of the packets as a fraction of the cable width (0…1).
    public var dataFlowWidth: CGFloat = 0.16
    /// Overall opacity of the packets (0…1).
    public var dataFlowOpacity: CGFloat = 0.7
    /// Soft glow around the packets, in points. 0 disables it.
    public var dataFlowGlow: CGFloat = 0

    /// When to flash electric arcs between the socket and the pin.
    public var spark = SparkTrigger.unplug
    /// Colour of the arc's glow (the core is white).
    public var sparkColor = Color(red: 0.45, green: 0.72, blue: 1.0)
    /// How long the arc lasts, in seconds.
    public var sparkDuration: TimeInterval = 0.3

    /// Master switch for haptics.
    public var hapticsEnabled = true
    /// Master switch for sounds.
    public var soundEnabled = true

    /// Custom haptics. `nil` uses ``DefaultCableHaptics``. Compared by identity.
    public var haptics: (any CableHapticsProvider)? {
        get { hapticsRef?.provider }
        set { hapticsRef = newValue.map(ProviderRef.init) }
    }

    /// Custom sounds. `nil` uses ``SynthesizedCableSounds``. Compared by identity.
    public var sounds: (any CableSoundProvider)? {
        get { soundsRef?.provider }
        set { soundsRef = newValue.map(ProviderRef.init) }
    }

    // One way to do each thing: the cable's look lives on `cable`, the spark trigger on `spark`.

    @available(*, deprecated, renamed: "cable.color")
    public var cableColor: Color {
        get { cable.color }
        set { cable.color = newValue }
    }

    @available(*, deprecated, renamed: "cable.width")
    public var cableWidth: CGFloat {
        get { cable.width }
        set { cable.width = newValue }
    }

    @available(*, deprecated, renamed: "cable.stretchedColor")
    public var stretchedColor: Color? {
        get { cable.stretchedColor }
        set { cable.stretchedColor = newValue }
    }

    @available(*, deprecated, message: "Use `spark` (SparkTrigger) instead.")
    public var sparkOnUnplug: Bool {
        get { spark.includesUnplug }
        set { spark = SparkTrigger(plugIn: spark.includesPlugIn, unplug: newValue) }
    }

    // MARK: Private

    // Stored behind identity-comparing wrappers so `Equatable` can be synthesized: a field left out of a
    // hand-written `==` would silently stop applying live, since the controller only reacts to `new != config`.
    private var hapticsRef: ProviderRef<any CableHapticsProvider>?
    private var soundsRef: ProviderRef<any CableSoundProvider>?

}

// MARK: - ProviderRef

/// A feedback provider compared by object identity.
private struct ProviderRef<Provider>: Equatable {
    init(_ provider: Provider) {
        self.provider = provider
    }

    let provider: Provider

    static func ==(lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs.provider as AnyObject) == ObjectIdentifier(rhs.provider as AnyObject)
    }
}

// MARK: - PlugSocket

/// A socket the cable can be plugged into.
public struct PlugSocket<ID: Hashable>: Identifiable, Equatable {

    // MARK: Lifecycle

    /// - Parameters:
    ///   - id: Unique among the board's sockets; what `connection` holds.
    ///   - title: Shown in ``CablePatchView`` rows and read by VoiceOver.
    ///   - subtitle: Optional second line in the row.
    ///   - systemImage: SF Symbol for the row. Only ``CablePatchView`` draws it, so a free-layout board can
    ///     leave the default.
    ///   - tint: Ring, LED and card border colour when hovered or connected.
    ///   - isEnabled: Disabled sockets are dimmed and refuse the plug.
    ///   - entryAngle: Direction the plug points when seated.
    ///   - accepts: Plug styles that fit; `nil` takes any.
    public init(
        id: ID,
        title: String,
        subtitle: String? = nil,
        systemImage: String = "circle",
        tint: Color = .accentColor,
        isEnabled: Bool = true,
        entryAngle: Angle = .zero,
        accepts: [PlugStyle]? = nil,
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.entryAngle = entryAngle
        self.accepts = accepts
    }

    // MARK: Public

    public var id: ID
    /// Shown in ``CablePatchView`` rows and used as the VoiceOver label.
    public var title: String
    /// Optional second line in a ``CablePatchView`` row.
    public var subtitle: String?
    /// SF Symbol shown next to the title in a ``CablePatchView`` row.
    public var systemImage: String
    /// Colour of the socket's ring, LED and card border when connected or hovered.
    public var tint: Color
    /// Disabled sockets are dimmed and can't be connected to.
    public var isEnabled: Bool
    /// Direction the plug points when seated. `.zero` (default) enters from the left, pin pointing right;
    /// `.degrees(90)` enters from above, `.degrees(180)` from the right, `.degrees(-90)` from below.
    /// The socket artwork rotates to match.
    public var entryAngle: Angle
    /// Which plugs fit. `nil` takes any plug and draws the board's plug style; otherwise only cables
    /// whose plug style is listed can connect, and the socket is drawn with the first style's artwork.
    public var accepts: [PlugStyle]?

    /// Whether a cable with this plug style can go in.
    public func accepts(_ style: PlugStyle) -> Bool {
        accepts?.contains { $0.id == style.id } ?? true
    }

}

// MARK: - PlugCable

/// One cable on a ``CableBoard`` that has several.
public struct PlugCable<CableID: Hashable>: Identifiable {
    /// - Parameters:
    ///   - id: Unique among the board's cables; the key in `connections` and the first argument of `onEvent`.
    ///   - configuration: This cable's own look and physics, or `nil` for the board's.
    public init(id: CableID, configuration: CableConfiguration? = nil) {
        self.id = id
        self.configuration = configuration
    }

    /// Unique among the board's cables.
    public var id: CableID
    /// This cable's look, physics and feedback. `nil` uses the board's configuration.
    public var configuration: CableConfiguration?
}

// MARK: - SingleCable

/// The cable id of a single-cable ``CableBoard`` / ``CablePatchView``. There is only ever one value, so the
/// single-cable initialisers can wrap a `Binding<ID?>` as a one-entry `[SingleCable: ID]` map.
public struct SingleCable: Hashable, Sendable {
    public init() { }
}

// MARK: - CableEvent

/// Events the cable emits, for analytics, logging or custom feedback.
public enum CableEvent<ID: Hashable>: Equatable {

    /// The plug was picked up.
    case grabbed
    /// The plug entered (id) or left (`nil`) a socket's snap range.
    case hover(ID?)
    /// The pin seated in a socket (after the insert animation).
    case plugged(ID)
    /// The plug was pulled out of a socket.
    case unplugged(ID)
    /// The plug was released away from any socket.
    case dropped
    /// Tension while dragging, 0…1, throttled to ~10 Hz.
    case stretched(CGFloat)

}
