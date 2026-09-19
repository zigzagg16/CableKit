import SwiftUI

// MARK: - PlugStyle

/// The connector on the end of the cable: its dimensions, how it is drawn, and how its socket looks.
///
/// Use one of the built-in presets (``audioJack``, ``europlug``, ``usbC``, ``banana``, ``ethernet``, ``magSafe``,
/// ``telephone``, ``idc``, ``electrode``)
/// or build your own:
///
/// ```swift
/// let myPlug = PlugStyle(
///     id: "my-plug", displayName: "My plug",
///     length: 60, insertTravel: 12, socketFaceOffset: 8,
///     draw: { ctx, plug in
///         PlugArt.boot(&ctx, rect: CGRect(x: -4, y: -6, width: 20, height: 12), plug: plug)
///         if let pin = PlugArt.pin(from: 16, to: 60, halfHeight: 4, clip: plug.pinClipX) {
///             ctx.fill(pin, with: PlugArt.nickel)
///         }
///     },
///     socket: { socket in
///         ZStack {
///             Circle().fill(.gray).frame(width: 30, height: 30)
///             socket.cover(Circle(), size: CGSize(width: 12, height: 12), fill: PlugArt.goldFace)
///             socket.ring(Circle(), size: CGSize(width: 30, height: 30))
///         }
///     }
/// )
/// ```
///
/// Plugs are drawn in a local space where the origin is the end of the rope (the boot), `+x` points
/// toward the tip and `+y` is down. ``length`` is where the tip ends up. The socket closure draws the
/// receptacle inside a 44×44 frame, centered on the point the tip lands on.
public struct PlugStyle: Identifiable, Sendable {

    // MARK: Lifecycle

    /// - Parameters:
    ///   - id: Stable identifier; two styles with the same id are equal.
    ///   - displayName: Human-readable name, e.g. for a picker.
    ///   - length: Boot-to-tip distance in points, in plug-local space.
    ///   - insertTravel: How far the plug slides in while seating; the controller animates this distance.
    ///   - socketFaceOffset: From the socket's centre to the face the pins vanish into.
    ///   - draw: Draws the plug in local space (origin at the boot, +x toward the tip, +y down).
    ///   - socket: Builds the receptacle artwork inside a 44×44 frame.
    public init(
        id: String,
        displayName: String,
        length: CGFloat,
        insertTravel: CGFloat,
        socketFaceOffset: CGFloat,
        draw: @escaping Drawer,
        @ViewBuilder socket: @escaping @Sendable @MainActor (SocketContext) -> some View,
    ) {
        self.id = id
        self.displayName = displayName
        self.length = length
        self.insertTravel = insertTravel
        self.socketFaceOffset = socketFaceOffset
        self.draw = draw
        self.socket = { AnyView(socket($0)) }
    }

    // MARK: Public

    /// Draws the plug each frame. The context is already translated to the boot and rotated along the plug.
    public typealias Drawer = @Sendable (_ context: inout GraphicsContext, _ plug: PlugDrawingContext) -> Void
    /// Builds the socket artwork; the view is re-evaluated whenever the socket's state changes.
    public typealias SocketBuilder = @Sendable @MainActor (_ socket: SocketContext) -> AnyView

    /// Every built-in style, in display order.
    public static let builtIn: [PlugStyle] = [
        .audioJack,
        .europlug,
        .usbC,
        .banana,
        .ethernet,
        .magSafe,
        .telephone,
        .idc,
        .electrode,
    ]

    /// Stable identifier; also what makes two styles equal.
    public var id: String
    /// Human-readable name, e.g. for a picker.
    public var displayName: String
    /// Distance from the rope's end (the boot) to the tip of the pin(s).
    public var length: CGFloat
    /// How far the plug travels while being inserted into a socket.
    public var insertTravel: CGFloat
    /// Distance from the socket's centre to the face the pins disappear into.
    public var socketFaceOffset: CGFloat
    /// Draws the plug. See ``PlugArt`` for reusable pieces.
    public var draw: Drawer
    /// Builds the socket artwork.
    public var socket: SocketBuilder

    /// Finds a built-in style by ``id``.
    public static func builtIn(id: String) -> PlugStyle? {
        builtIn.first { $0.id == id }
    }

}

// MARK: Equatable

extension PlugStyle: Equatable {
    /// Identity plus the dimensions the physics depends on; the drawing closures are not compared.
    public static func ==(lhs: PlugStyle, rhs: PlugStyle) -> Bool {
        lhs.id == rhs.id && lhs.length == rhs.length && lhs.insertTravel == rhs.insertTravel
            && lhs.socketFaceOffset == rhs.socketFaceOffset
    }
}

// MARK: - PlugDrawingContext

/// What a ``PlugStyle`` gets when drawing itself.
public struct PlugDrawingContext {
    /// Current jacket colour of the cable (already tinted for stretch, if enabled).
    public var jacket: Color
    /// Tension past rest length, 0…1.
    public var stretch: CGFloat
    /// Colour the boot glows under tension, if the cable style defines one.
    public var stretchedColor: Color?
    /// Local x beyond which the pins are hidden inside the socket, or `nil` when not seated.
    public var pinClipX: CGFloat?
    /// The whole configuration, for anything else you want to react to.
    public var configuration: CableConfiguration
    /// The environment the plug is drawn in; resolves dynamic colours for the current appearance.
    public var environment: EnvironmentValues

    /// Convenience: `pinClipX` or infinity.
    public var clip: CGFloat {
        pinClipX ?? .infinity
    }
}

// MARK: - SocketContext

/// What a ``PlugStyle`` gets when building its socket artwork.
public struct SocketContext {

    // MARK: Lifecycle

    /// Assembled by ``CableSocketPortView``; public so socket artwork can be previewed in any state.
    public init(theme: CableTheme, tint: Color, isHovered: Bool, isConnected: Bool, isSeated: Bool, pulse: CGFloat) {
        self.theme = theme
        self.tint = tint
        self.isHovered = isHovered
        self.isConnected = isConnected
        self.isSeated = isSeated
        self.pulse = pulse
    }

    // MARK: Public

    /// Resolved theme, for the bezel and hole gradients.
    public var theme: CableTheme
    /// The socket's tint colour (`PlugSocket.tint`).
    public var tint: Color
    /// The plug is hovering within snap range.
    public var isHovered: Bool
    /// The plug is connected (snapping, inserting or seated).
    public var isConnected: Bool
    /// The pin is fully inserted — the socket should look closed.
    public var isSeated: Bool
    /// 1 → 0 pulse right after the plug seats.
    public var pulse: CGFloat

    /// Bezel gradient from the theme.
    public var bezel: LinearGradient {
        LinearGradient(colors: theme.socketBezel, startPoint: .top, endPoint: .bottom)
    }

    /// Hole gradient from the theme.
    public var hole: RadialGradient {
        RadialGradient(colors: theme.socketHole, center: .center, startRadius: 1, endRadius: 10)
    }

    /// Tinted outline that lights up on hover / connection and pulses on plug-in.
    public func ring(_ shape: some InsettableShape, size: CGSize) -> some View {
        shape
            .strokeBorder(tint, lineWidth: 2)
            .frame(width: size.width, height: size.height)
            .opacity(isConnected ? 1 : (isHovered ? 0.8 : 0))
            .scaleEffect(1 + pulse * 0.25)
            .opacity(1 - pulse * 0.6)
    }

    /// Cap that fades in over the hole when a plug is seated (the plug's face, seen end-on).
    public func cover(_ shape: some Shape, size: CGSize, fill: LinearGradient) -> some View {
        shape
            .fill(fill)
            .overlay(shape.stroke(.black.opacity(0.5), lineWidth: 1))
            .frame(width: size.width, height: size.height)
            .opacity(isSeated ? 1 : 0)
            .scaleEffect(isSeated ? 1 : 0.6)
    }

}

// MARK: - PlugArt

/// Building blocks for drawing plugs: boots, metals, pins and shadows. All in plug-local space.
public enum PlugArt {
    // Socket faces: what covers the hole when a plug is seated, i.e. the plug's own face seen end-on.

    /// Gold-plated face (audio jack, banana).
    public static let goldFace = LinearGradient(
        colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.72, green: 0.52, blue: 0.13)],
        startPoint: .top,
        endPoint: .bottom,
    )
    /// Nickel face (USB-C, telephone, Ethernet).
    public static let nickelFace = LinearGradient(
        colors: [Color(white: 0.9), Color(white: 0.5)],
        startPoint: .top,
        endPoint: .bottom,
    )
    /// Light plastic face (Europlug).
    public static let plasticFace = LinearGradient(
        colors: [Color(white: 0.96), Color(white: 0.7)],
        startPoint: .top,
        endPoint: .bottom,
    )
    /// Black plastic face (IDC ribbon connector).
    public static let blackFace = LinearGradient(
        colors: [Color(white: 0.2), Color(white: 0.08)],
        startPoint: .top,
        endPoint: .bottom,
    )
    /// Translucent glass face (neon electrode).
    public static let clearFace = LinearGradient(
        colors: [Color(white: 0.9, opacity: 0.95), Color(white: 0.6, opacity: 0.95)],
        startPoint: .top,
        endPoint: .bottom,
    )

    /// Gold plating (±9 local y).
    public static var gold: GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [
            Color(red: 1, green: 0.88, blue: 0.5),
            Color(red: 0.72, green: 0.52, blue: 0.13),
            Color(red: 0.95, green: 0.78, blue: 0.35),
        ]), startPoint: CGPoint(x: 0, y: -9), endPoint: CGPoint(x: 0, y: 9))
    }

    /// Nickel plating (±5 local y).
    public static var nickel: GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [Color(white: 0.95), Color(white: 0.55), Color(white: 0.8)]),
            startPoint: CGPoint(x: 0, y: -5),
            endPoint: CGPoint(x: 0, y: 5),
        )
    }

    /// Strain-relief boot in the jacket colour, ribbed, glowing under tension if a stretched colour exists.
    public static func boot(_ ctx: inout GraphicsContext, rect: CGRect, plug: PlugDrawingContext) {
        let boot = Path(roundedRect: rect, cornerRadius: rect.height * 0.36)
        ctx.fill(boot, with: .linearGradient(
            Gradient(colors: [
                PlugArt.darken(plug.jacket, by: 0.25, in: plug.environment),
                PlugArt.darken(plug.jacket, by: 0.6, in: plug.environment),
            ]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY),
        ))
        var x = rect.minX + 6
        while x < rect.maxX - 4 {
            ctx.fill(Path(CGRect(x: x, y: rect.minY, width: 1.6, height: rect.height)), with: .color(.black.opacity(0.25)))
            x += 5
        }
        if let tint = plug.stretchedColor, plug.stretch > 0.4 {
            ctx.fill(boot, with: .color(tint.opacity((plug.stretch - 0.4) * 0.6)))
        }
    }

    /// Soft drop shadow under a set of paths.
    public static func dropShadow(_ ctx: inout GraphicsContext, _ paths: [Path], opacity: Double = 0.45) {
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(opacity), radius: 5, x: 0, y: 6))
            var all = Path()
            for path in paths { all.addPath(path) }
            layer.fill(all, with: .color(.black.opacity(0.001)))
        }
    }

    /// Brushed-metal vertical gradient between two local y values.
    public static func metal(_ y0: CGFloat, _ y1: CGFloat, light: CGFloat = 0.62) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: [
            .init(color: Color(white: light), location: 0),
            .init(color: Color(white: light * 0.5), location: 0.45),
            .init(color: Color(white: light * 0.22), location: 0.55),
            .init(color: Color(white: light * 0.55), location: 1),
        ]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
    }

    /// Mixes a colour toward white by `amount` (0…1).
    ///
    /// `environment` is where dynamic colours (`.accentColor`, asset-catalog colours with a dark variant…)
    /// get resolved; pass the drawing context's ``PlugDrawingContext/environment`` / ``CableDrawingContext/environment``.
    public static func lighten(_ color: Color, by amount: CGFloat, in environment: EnvironmentValues) -> Color {
        let c = color.resolve(in: environment)
        let t = Float(amount)
        return Color(
            red: Double(c.red + (1 - c.red) * t),
            green: Double(c.green + (1 - c.green) * t),
            blue: Double(c.blue + (1 - c.blue) * t),
            opacity: Double(c.opacity),
        )
    }

    /// Mixes a colour toward black by `amount` (0…1). See ``lighten(_:by:in:)`` for `environment`.
    public static func darken(_ color: Color, by amount: CGFloat, in environment: EnvironmentValues) -> Color {
        let c = color.resolve(in: environment)
        let t = Float(1 - amount)
        return Color(red: Double(c.red * t), green: Double(c.green * t), blue: Double(c.blue * t), opacity: Double(c.opacity))
    }

    @available(
        *,
        deprecated,
        message: "Pass the drawing context's environment so dynamic colours resolve for the current appearance."
    )
    public static func lighten(_ color: Color, by amount: CGFloat) -> Color {
        lighten(color, by: amount, in: EnvironmentValues())
    }

    @available(
        *,
        deprecated,
        message: "Pass the drawing context's environment so dynamic colours resolve for the current appearance."
    )
    public static func darken(_ color: Color, by amount: CGFloat) -> Color {
        darken(color, by: amount, in: EnvironmentValues())
    }

    /// A pin from `from` to `to` (local x), clipped where it enters the socket. `nil` if fully hidden.
    public static func pin(from: CGFloat, to: CGFloat, halfHeight: CGFloat, clip: CGFloat) -> Path? {
        let end = min(to, clip)
        let w = end - from
        guard w > 0.5 else { return nil }
        return Path(
            roundedRect: CGRect(x: from, y: -halfHeight, width: w, height: halfHeight * 2),
            cornerRadius: min(halfHeight, w / 2),
        )
    }
}

// MARK: - Built-in styles

extension PlugStyle {
    /// 6.35mm TRS audio jack — metal body, gold collar, nickel pin.
    public static let audioJack = PlugStyle(
        id: "audioJack",
        displayName: "Audio jack",
        length: 66,
        insertTravel: 15,
        socketFaceOffset: 10,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -7, width: 24, height: 14)
            let body = Path(roundedRect: CGRect(x: 14, y: -11, width: 32, height: 22), cornerRadius: 6)
            let collar = Path(roundedRect: CGRect(x: 43, y: -8.5, width: 8, height: 17), cornerRadius: 2)
            let pin = PlugArt.pin(from: 49, to: 66, halfHeight: 4, clip: clip)
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 5), body, collar, pin ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            ctx.fill(body, with: PlugArt.metal(-11, 11))
            ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 1)
            for i in 0..<4 { // grip grooves
                let x = 20 + CGFloat(i) * 5
                ctx.fill(Path(CGRect(x: x, y: -9, width: 1.4, height: 18)), with: .color(.black.opacity(0.35)))
                ctx.fill(Path(CGRect(x: x + 1.4, y: -9, width: 0.8, height: 18)), with: .color(.white.opacity(0.18)))
            }
            ctx.fill(collar, with: PlugArt.gold)
            if let pin {
                ctx.fill(pin, with: PlugArt.nickel)
                if clip > 60.6 { // insulator ring
                    ctx.fill(Path(CGRect(x: 59, y: -4, width: 1.6, height: 8)), with: .color(.black.opacity(0.85)))
                }
                ctx.stroke(pin, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            }
        },
        socket: { s in
            ZStack {
                Circle().fill(s.bezel).frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                Circle().fill(s.hole).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                s.cover(Circle(), size: CGSize(width: 20, height: 20), fill: PlugArt.goldFace)
                s.ring(Circle(), size: CGSize(width: 34, height: 34))
            }
        },
    )

    /// CEE 7/16 europlug — flat plastic body with two round pins.
    public static let europlug = PlugStyle(
        id: "europlug",
        displayName: "Europlug",
        length: 70,
        insertTravel: 16,
        socketFaceOffset: 8,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -7, width: 22, height: 14)
            var body = Path()
            body.move(to: CGPoint(x: 14, y: -13))
            body.addLine(to: CGPoint(x: 44, y: -17))
            body.addQuadCurve(to: CGPoint(x: 52, y: -9), control: CGPoint(x: 52, y: -17))
            body.addLine(to: CGPoint(x: 52, y: 9))
            body.addQuadCurve(to: CGPoint(x: 44, y: 17), control: CGPoint(x: 52, y: 17))
            body.addLine(to: CGPoint(x: 14, y: 13))
            body.addQuadCurve(to: CGPoint(x: 14, y: -13), control: CGPoint(x: 8, y: 0))
            body.closeSubpath()
            let pins: [Path] = [-9.5, 9.5].compactMap { (y: CGFloat) in
                PlugArt.pin(from: 52, to: 70, halfHeight: 2.2, clip: clip)?.applying(CGAffineTransform(translationX: 0, y: y))
            }
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 5), body] + pins)

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            ctx.fill(body, with: .linearGradient(
                Gradient(colors: [Color(white: 0.96), Color(white: 0.78), Color(white: 0.6)]),
                startPoint: CGPoint(x: 0, y: -17),
                endPoint: CGPoint(x: 0, y: 17),
            ))
            ctx.stroke(body, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
            ctx.fill(
                Path(roundedRect: CGRect(x: 24, y: -10, width: 3, height: 20), cornerRadius: 1.5),
                with: .color(.black.opacity(0.12)),
            )
            for y: CGFloat in [-9.5, 9.5] {
                guard let pin = PlugArt.pin(from: 52, to: 70, halfHeight: 2.2, clip: clip) else { continue }
                var c = ctx
                c.translateBy(x: 0, y: y)
                c.fill(pin, with: .linearGradient(
                    Gradient(colors: [Color(white: 0.9), Color(white: 0.5)]),
                    startPoint: CGPoint(x: 0, y: -2.2),
                    endPoint: CGPoint(x: 0, y: 2.2),
                ))
                if let sleeve = PlugArt.pin(from: 52, to: 60, halfHeight: 2.2, clip: clip) {
                    c.fill(sleeve, with: .color(.black.opacity(0.8)))
                }
            }
        },
        socket: { s in
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.85)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                VStack(spacing: 11) {
                    Circle().fill(s.hole).frame(width: 8, height: 8)
                    Circle().fill(s.hole).frame(width: 8, height: 8)
                }
                s.cover(Circle(), size: CGSize(width: 32, height: 32), fill: PlugArt.plasticFace)
                s.ring(Circle(), size: CGSize(width: 40, height: 40))
            }
        },
    )

    /// USB‑C — slim metal shell with an oval connector.
    public static let usbC = PlugStyle(
        id: "usbC",
        displayName: "USB‑C",
        length: 66,
        insertTravel: 10,
        socketFaceOffset: 5,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -6, width: 26, height: 12)
            let body = Path(roundedRect: CGRect(x: 18, y: -10, width: 38, height: 20), cornerRadius: 7)
            let connector = PlugArt.pin(from: 54, to: 66, halfHeight: 4.2, clip: clip)
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 4), body, connector ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            ctx.fill(body, with: .linearGradient(
                Gradient(colors: [Color(white: 0.55), Color(white: 0.28), Color(white: 0.2), Color(white: 0.4)]),
                startPoint: CGPoint(x: 0, y: -10),
                endPoint: CGPoint(x: 0, y: 10),
            ))
            ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 1)
            ctx.stroke(
                Path(ellipseIn: CGRect(x: 30, y: -3, width: 6, height: 6)),
                with: .color(.white.opacity(0.5)),
                lineWidth: 1,
            )
            ctx.fill(Path(CGRect(x: 37, y: -0.6, width: 8, height: 1.2)), with: .color(.white.opacity(0.5)))
            if let connector {
                ctx.fill(connector, with: .linearGradient(
                    Gradient(colors: [Color(white: 0.92), Color(white: 0.6), Color(white: 0.85)]),
                    startPoint: CGPoint(x: 0, y: -4.2),
                    endPoint: CGPoint(x: 0, y: 4.2),
                ))
                if let inner = PlugArt.pin(from: 56, to: 66, halfHeight: 2.4, clip: clip) {
                    ctx.fill(inner, with: .color(.black.opacity(0.55)))
                }
            }
        },
        socket: { s in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(s.bezel).frame(width: 36, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
                        .black.opacity(0.7),
                        lineWidth: 1,
                    ))
                Capsule().fill(s.hole).frame(width: 24, height: 9)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                s.cover(Capsule(), size: CGSize(width: 24, height: 9), fill: PlugArt.nickelFace)
                s.ring(RoundedRectangle(cornerRadius: 8, style: .continuous), size: CGSize(width: 36, height: 20))
            }
        },
    )

    /// 4mm banana plug — barrel in the cable colour with a sprung lamella pin.
    public static let banana = PlugStyle(
        id: "banana",
        displayName: "Banana",
        length: 66,
        insertTravel: 17,
        socketFaceOffset: 9,
        draw: { ctx, plug in
            let clip = plug.clip
            let jacket = plug.jacket
            let bootRect = CGRect(x: -4, y: -6, width: 22, height: 12)
            let barrel = Path(roundedRect: CGRect(x: 14, y: -8, width: 26, height: 16), cornerRadius: 3)
            let ridge = Path(roundedRect: CGRect(x: 38, y: -9.5, width: 8, height: 19), cornerRadius: 2)
            let pin = PlugArt.pin(from: 46, to: 66, halfHeight: 3.2, clip: clip)
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 4), barrel, ridge, pin ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            ctx.fill(barrel, with: .linearGradient(
                Gradient(colors: [
                    PlugArt.lighten(jacket, by: 0.35, in: plug.environment),
                    jacket,
                    PlugArt.darken(jacket, by: 0.45, in: plug.environment),
                ]),
                startPoint: CGPoint(x: 0, y: -8),
                endPoint: CGPoint(x: 0, y: 8),
            ))
            ctx.stroke(barrel, with: .color(.black.opacity(0.4)), lineWidth: 0.8)
            for i in 0..<3 {
                ctx.fill(Path(CGRect(x: 19 + CGFloat(i) * 6, y: -7, width: 1.2, height: 14)), with: .color(.black.opacity(0.2)))
            }
            ctx.fill(ridge, with: PlugArt.metal(-9.5, 9.5, light: 0.7))
            if let pin {
                ctx.fill(pin, with: PlugArt.gold)
                if let bulge = PlugArt.pin(from: 50, to: 63, halfHeight: 4, clip: clip) {
                    ctx.fill(bulge, with: PlugArt.gold)
                    ctx.stroke(bulge, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
                    for y: CGFloat in [-1.3, 1.3] {
                        let end = min(62, clip)
                        if end > 51 {
                            ctx.fill(
                                Path(CGRect(x: 51, y: y - 0.4, width: end - 51, height: 0.8)),
                                with: .color(.black.opacity(0.45)),
                            )
                        }
                    }
                }
            }
        },
        socket: { s in
            ZStack {
                Circle().fill(s.bezel).frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                Circle().fill(s.tint.opacity(0.85)).frame(width: 22, height: 22)
                Circle().fill(s.hole).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                s.cover(Circle(), size: CGSize(width: 12, height: 12), fill: PlugArt.goldFace)
                s.ring(Circle(), size: CGSize(width: 30, height: 30))
            }
        },
    )

    /// RJ11 telephone plug — the small clear connector on a handset cord, four gold contacts.
    /// Made for ``CableStyle/coiled(color:width:coilRadius:pitch:leadLength:)``.
    public static let telephone = PlugStyle(
        id: "telephone",
        displayName: "Phone",
        length: 66,
        insertTravel: 12,
        socketFaceOffset: 6,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -5.5, width: 22, height: 11)
            let body = PlugArt.pin(from: 16, to: 66, halfHeight: 5.5, clip: clip)
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 4), body ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            guard let body else { return }
            // Clear polycarbonate: the cord's colour shows through the back half.
            ctx.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(white: 0.97, opacity: 0.85),
                        Color(white: 0.8, opacity: 0.85),
                        Color(white: 0.62, opacity: 0.85),
                    ]),
                    startPoint: CGPoint(x: 0, y: -5.5),
                    endPoint: CGPoint(x: 0, y: 5.5),
                ),
            )
            if let inner = PlugArt.pin(from: 16, to: 38, halfHeight: 3.2, clip: clip) {
                ctx.fill(inner, with: .color(plug.jacket.opacity(0.45)))
            }
            ctx.stroke(body, with: .color(.black.opacity(0.35)), lineWidth: 0.7)
            // Latch: a thin springy tab angled back over the body.
            let latchEnd = min(61, clip)
            if latchEnd > 48 {
                var latch = Path()
                latch.move(to: CGPoint(x: latchEnd, y: -5.5))
                latch.addLine(to: CGPoint(x: latchEnd, y: -9))
                latch.addLine(to: CGPoint(x: 46, y: -9))
                latch.addLine(to: CGPoint(x: 30, y: -12.5))
                latch.addLine(to: CGPoint(x: 30, y: -9.8))
                latch.addLine(to: CGPoint(x: 44, y: -6.6))
                latch.addLine(to: CGPoint(x: 44, y: -5.5))
                latch.closeSubpath()
                ctx.fill(latch, with: .color(Color(white: 0.9, opacity: 0.85)))
                ctx.stroke(latch, with: .color(.black.opacity(0.3)), lineWidth: 0.5)
            }
            let contactEnd = min(66, clip)
            if contactEnd > 58 {
                for i in 0..<4 {
                    let y = -3 + CGFloat(i) * 2
                    ctx.fill(Path(CGRect(x: 58, y: y, width: contactEnd - 58, height: 1)), with: PlugArt.gold)
                }
            }
        },
        socket: { s in
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(s.bezel).frame(width: 26, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(
                        .black.opacity(0.7),
                        lineWidth: 1,
                    ))
                VStack(spacing: 0) {
                    Rectangle().fill(Color(white: 0.05)).frame(width: 5, height: 3)
                    RoundedRectangle(cornerRadius: 1.5).fill(s.hole).frame(width: 14, height: 12)
                        .overlay(alignment: .trailing) {
                            VStack(spacing: 1.2) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Rectangle().fill(Color(red: 0.9, green: 0.75, blue: 0.35).opacity(0.7)).frame(
                                        width: 3,
                                        height: 0.8,
                                    )
                                }
                            }
                            .padding(.trailing, 2)
                        }
                }
                s.cover(RoundedRectangle(cornerRadius: 1.5), size: CGSize(width: 14, height: 12), fill: PlugArt.clearFace)
                    .offset(y: 1.5)
                s.ring(RoundedRectangle(cornerRadius: 4, style: .continuous), size: CGSize(width: 26, height: 24))
            }
        },
    )

    /// RJ45 ethernet — clear body, latch tab, eight gold contacts.
    public static let ethernet = PlugStyle(
        id: "ethernet",
        displayName: "Ethernet",
        length: 66,
        insertTravel: 14,
        socketFaceOffset: 6,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -7, width: 24, height: 14)
            let body = PlugArt.pin(from: 16, to: 66, halfHeight: 8, clip: clip)
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 5), body ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            guard let body else { return }
            ctx.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(white: 0.95, opacity: 0.9),
                        Color(white: 0.7, opacity: 0.9),
                        Color(white: 0.55, opacity: 0.9),
                    ]),
                    startPoint: CGPoint(x: 0, y: -8),
                    endPoint: CGPoint(x: 0, y: 8),
                ),
            )
            if let inner = PlugArt.pin(from: 16, to: 40, halfHeight: 5, clip: clip) {
                ctx.fill(inner, with: .color(plug.jacket.opacity(0.35)))
            }
            ctx.stroke(body, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
            let latchEnd = min(60, clip)
            if latchEnd > 46 {
                var latch = Path()
                latch.move(to: CGPoint(x: latchEnd, y: -8))
                latch.addLine(to: CGPoint(x: latchEnd, y: -12.5))
                latch.addLine(to: CGPoint(x: 44, y: -12.5))
                latch.addLine(to: CGPoint(x: 28, y: -17))
                latch.addLine(to: CGPoint(x: 28, y: -13.5))
                latch.addLine(to: CGPoint(x: 42, y: -9.5))
                latch.addLine(to: CGPoint(x: 42, y: -8))
                latch.closeSubpath()
                ctx.fill(latch, with: .color(Color(white: 0.85, opacity: 0.9)))
                ctx.stroke(latch, with: .color(.black.opacity(0.3)), lineWidth: 0.6)
            }
            let contactEnd = min(66, clip)
            if contactEnd > 57 {
                for i in 0..<8 {
                    let y = -7 + CGFloat(i) * 2
                    ctx.fill(Path(CGRect(x: 57, y: y, width: contactEnd - 57, height: 1)), with: PlugArt.gold)
                }
            }
        },
        socket: { s in
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s.bezel).frame(width: 32, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
                        .black.opacity(0.7),
                        lineWidth: 1,
                    ))
                VStack(spacing: 0) {
                    Rectangle().fill(Color(white: 0.05)).frame(width: 8, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(s.hole).frame(width: 20, height: 16)
                        .overlay(alignment: .trailing) {
                            VStack(spacing: 1) {
                                ForEach(0..<8, id: \.self) { _ in
                                    Rectangle().fill(Color(red: 0.9, green: 0.75, blue: 0.35).opacity(0.7)).frame(
                                        width: 3,
                                        height: 0.8,
                                    )
                                }
                            }
                            .padding(.trailing, 2)
                        }
                }
                s.cover(RoundedRectangle(cornerRadius: 2), size: CGSize(width: 20, height: 16), fill: PlugArt.clearFace)
                    .offset(y: 2)
                s.ring(RoundedRectangle(cornerRadius: 5, style: .continuous), size: CGSize(width: 32, height: 28))
            }
        },
    )

    /// MagSafe — flat aluminium puck with five pogo pins and a status LED that lights up on contact.
    ///
    /// The travel is tiny: it's a magnetic snap, not a push. The front lip of the puck sinks into the
    /// shallow recess; the LED on top glows amber while it snaps in and green once it's seated.
    public static let magSafe = PlugStyle(
        id: "magSafe",
        displayName: "MagSafe",
        length: 66,
        insertTravel: 5,
        socketFaceOffset: 5,
        draw: { ctx, plug in
            let clip = plug.clip
            let bootRect = CGRect(x: -4, y: -5, width: 20, height: 10)
            // Slim neck between the boot and the puck.
            let neck = Path(roundedRect: CGRect(x: 14, y: -3.5, width: 26, height: 7), cornerRadius: 2)
            // The puck is clipped like a pin so its lip disappears into the recess; squarer than `PlugArt.pin`.
            let puckEnd = min(66, clip)
            let puck: Path? = puckEnd > 38.5
                ? Path(roundedRect: CGRect(x: 38, y: -6.5, width: puckEnd - 38, height: 13), cornerRadius: 3)
                : nil
            let pins: [Path] = [-4, -2, 0, 2, 4].compactMap { (y: CGFloat) in
                PlugArt.pin(from: 65, to: 66, halfHeight: 0.6, clip: clip)?.applying(CGAffineTransform(translationX: 0, y: y))
            }
            PlugArt.dropShadow(&ctx, [Path(roundedRect: bootRect, cornerRadius: 4), neck, puck ?? Path()])

            PlugArt.boot(&ctx, rect: bootRect, plug: plug)
            ctx.fill(neck, with: .linearGradient(
                Gradient(colors: [
                    PlugArt.lighten(plug.jacket, by: 0.3, in: plug.environment),
                    plug.jacket,
                    PlugArt.darken(plug.jacket, by: 0.4, in: plug.environment),
                ]),

                startPoint: CGPoint(x: 0, y: -3.5),
                endPoint: CGPoint(x: 0, y: 3.5),
            ))
            ctx.stroke(neck, with: .color(.black.opacity(0.3)), lineWidth: 0.6)

            if let puck {
                // Brushed aluminium, a touch lighter than the jack's steel.
                ctx.fill(puck, with: .linearGradient(Gradient(stops: [
                    .init(color: Color(white: 0.9), location: 0),
                    .init(color: Color(white: 0.74), location: 0.5),
                    .init(color: Color(white: 0.58), location: 0.85),
                    .init(color: Color(white: 0.7), location: 1),
                ]), startPoint: CGPoint(x: 0, y: -6.5), endPoint: CGPoint(x: 0, y: 6.5)))
                ctx.stroke(puck, with: .color(.black.opacity(0.4)), lineWidth: 0.8)
                // Chamfer highlight along the top edge.
                if let edge = PlugArt.pin(from: 40, to: 64, halfHeight: 0.5, clip: clip) {
                    ctx.fill(edge.applying(CGAffineTransform(translationX: 0, y: -5.5)), with: .color(.white.opacity(0.55)))
                }
                // Status LED on top: off when free, amber while it snaps in, green once seated.
                let led = Path(ellipseIn: CGRect(x: 46, y: -5.4, width: 3.2, height: 2.2))
                let glow: Color? = plug.pinClipX.map { clip in
                    clip <= 61.5 ? Color(red: 0.35, green: 0.95, blue: 0.45) : Color(red: 1, green: 0.65, blue: 0.15)
                }
                ctx.fill(led, with: .color(glow ?? Color(white: 0.3)))
                ctx.stroke(led, with: .color(.black.opacity(0.35)), lineWidth: 0.4)
                if let glow {
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 2.5))
                        layer.fill(led, with: .color(glow.opacity(0.8)))
                    }
                }
            }
            for pin in pins { ctx.fill(pin, with: PlugArt.gold) }
        },
        socket: { s in
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s.bezel).frame(width: 36, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(
                        .black.opacity(0.7),
                        lineWidth: 1,
                    ))
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(s.hole).frame(width: 26, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(
                        .white.opacity(0.2),
                        lineWidth: 1,
                    ))
                HStack(spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle().fill(Color(red: 0.9, green: 0.75, blue: 0.35)).frame(width: 2.2, height: 2.2)
                    }
                }
                s.cover(
                    RoundedRectangle(cornerRadius: 3, style: .continuous),
                    size: CGSize(width: 26, height: 10),
                    fill: PlugArt.nickelFace,
                )
                s.ring(RoundedRectangle(cornerRadius: 5, style: .continuous), size: CGSize(width: 36, height: 18))
            }
        },
    )
}
