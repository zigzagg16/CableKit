import SwiftUI

// MARK: - CableTheme

/// Every colour the component draws with, apart from the cable and plug artwork.
/// Use `.light` / `.dark`, tweak a copy, or build your own. When `CableConfiguration.theme`
/// is `nil` the view picks `.light` or `.dark` from the current color scheme.
public struct CableTheme: Equatable, Sendable {

    // MARK: Lifecycle

    /// Builds a theme from scratch. Starting from ``light`` or ``dark`` and changing a few properties is usually
    /// easier.
    public init(
        cardFill: Color,
        cardBorder: Color,
        cardShadow: Color,
        title: Color,
        subtitle: Color,
        ledOff: Color,
        deviceGradient: [Color],
        deviceBorder: Color,
        deviceText: Color,
        devicePort: [Color],
        socketBezel: [Color],
        socketHole: [Color],
        shadowOpacity: Double,
    ) {
        self.cardFill = cardFill
        self.cardBorder = cardBorder
        self.cardShadow = cardShadow
        self.title = title
        self.subtitle = subtitle
        self.ledOff = ledOff
        self.deviceGradient = deviceGradient
        self.deviceBorder = deviceBorder
        self.deviceText = deviceText
        self.devicePort = devicePort
        self.socketBezel = socketBezel
        self.socketHole = socketHole
        self.shadowOpacity = shadowOpacity
    }

    // MARK: Public

    /// Built-in theme for dark appearance: charcoal cards, brushed-steel sockets, strong shadows.
    public static let dark = CableTheme(
        cardFill: Color(white: 0.11),
        cardBorder: .white.opacity(0.08),
        cardShadow: .black.opacity(0.35),
        title: .white,
        subtitle: .white.opacity(0.55),
        ledOff: Color(white: 0.25),
        deviceGradient: [Color(white: 0.24), Color(white: 0.13)],
        deviceBorder: .white.opacity(0.12),
        deviceText: .white.opacity(0.9),
        devicePort: [Color(white: 0.05), Color(white: 0.18)],
        socketBezel: [Color(white: 0.5), Color(white: 0.18)],
        socketHole: [Color(white: 0.02), Color(white: 0.12)],
        shadowOpacity: 0.45,
    )

    /// Built-in theme for light appearance: white cards, soft shadows, a light-grey device.
    public static let light = CableTheme(
        cardFill: .white,
        cardBorder: .black.opacity(0.08),
        cardShadow: .black.opacity(0.10),
        title: Color(white: 0.1),
        subtitle: Color(white: 0.45),
        ledOff: Color(white: 0.82),
        deviceGradient: [Color(white: 0.97), Color(white: 0.86)],
        deviceBorder: .black.opacity(0.1),
        deviceText: Color(white: 0.2),
        devicePort: [Color(white: 0.2), Color(white: 0.35)],
        socketBezel: [Color(white: 0.85), Color(white: 0.55)],
        socketHole: [Color(white: 0.08), Color(white: 0.22)],
        shadowOpacity: 0.22,
    )

    // Socket cards (``CablePatchView`` rows)

    /// Background of a socket row.
    public var cardFill: Color
    /// Hairline around a socket row when it is neither hovered nor connected.
    public var cardBorder: Color
    /// Drop shadow under a socket row.
    public var cardShadow: Color
    /// Socket title text.
    public var title: Color
    /// Socket subtitle text.
    public var subtitle: Color
    /// The row's status LED when nothing is connected.
    public var ledOff: Color

    // Source "device" the cable comes out of (``SourcePortView``)

    /// Top-leading to bottom-trailing gradient of the device body.
    public var deviceGradient: [Color]
    /// Hairline around the device.
    public var deviceBorder: Color
    /// Icon and title on the device.
    public var deviceText: Color
    /// Top-to-bottom gradient of the port the cable exits from.
    public var devicePort: [Color]

    // Socket receptacles (``SocketContext/bezel`` and ``SocketContext/hole``)

    /// Top-to-bottom gradient of the metal ring around a socket.
    public var socketBezel: [Color]
    /// Centre-out gradient inside a socket's hole.
    public var socketHole: [Color]

    /// Opacity of the drop shadows under the cable and plug.
    public var shadowOpacity: Double

    /// The built-in theme for a colour scheme.
    public static func automatic(for scheme: ColorScheme) -> CableTheme {
        scheme == .dark ? .dark : .light
    }

}

extension EnvironmentValues {
    /// Theme in effect inside a `CablePatchView`. `nil` means automatic (light/dark from the color scheme).
    /// Custom `source` views can read this to match the component.
    @Entry public var cableTheme: CableTheme? = nil
}

extension View {
    /// Overrides the theme for any `CablePatchView` in this hierarchy.
    public func cableTheme(_ theme: CableTheme?) -> some View {
        environment(\.cableTheme, theme)
    }
}
