import SwiftUI

// MARK: - CableStyle.neon

extension CableStyle {
    /// A lit neon tube: layered glow around a bright core in the cable colour, no drop shadow.
    ///
    /// Works best on a dark theme. Pairs with ``PlugStyle/electrode``; set a bright
    /// ``CableConfiguration/dataFlowColor`` to send pulses of light down the tube.
    ///
    /// - Parameters:
    ///   - color: The gas colour.
    ///   - width: Tube diameter, in points.
    ///   - glow: How far the light bleeds out, in points.
    public static func neon(
        color: Color = Color(red: 1, green: 0.25, blue: 0.55),
        width: CGFloat = 8,
        glow: CGFloat = 12,
    ) -> CableStyle {
        CableStyle(
            color: color,
            width: width,
            stretchThinning: 0,
            shadowOpacity: 0,
            renderer: { ctx, cable in
                NeonArt.tube(&ctx, cable.path, color: cable.jacket, width: cable.width, glow: glow)
            },
        )
    }
}

// MARK: - NeonArt

/// Shared glow rendering for the neon cable and its electrode plug.
enum NeonArt {
    static func tube(_ ctx: inout GraphicsContext, _ path: Path, color: Color, width w: CGFloat, glow: CGFloat) {
        let round = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        if glow > 0 {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: glow))
                layer.stroke(
                    path,
                    with: .color(color.opacity(0.55)),
                    style: StrokeStyle(lineWidth: w * 2.6, lineCap: .round, lineJoin: .round),
                )
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: glow * 0.35))
                layer.stroke(
                    path,
                    with: .color(color.opacity(0.8)),
                    style: StrokeStyle(lineWidth: w * 1.5, lineCap: .round, lineJoin: .round),
                )
            }
        }
        ctx.stroke(path, with: .color(color), style: round)
        ctx.stroke(
            path,
            with: .color(PlugArt.lighten(color, by: 0.75, in: ctx.environment)),
            style: StrokeStyle(lineWidth: w * 0.42, lineCap: .round, lineJoin: .round),
        )
    }
}

// MARK: - PlugStyle.electrode

extension PlugStyle {
    /// Neon electrode — a nickel ferrule where the tube ends, then the bare glass electrode that
    /// slots into a ceramic holder. The glass keeps glowing in the cable colour.
    /// Made for ``CableStyle/neon(color:width:glow:)``.
    public static let electrode = PlugStyle(
        id: "electrode",
        displayName: "Electrode",
        length: 66,
        insertTravel: 16,
        socketFaceOffset: 9,
        draw: { ctx, plug in
            let clip = plug.clip
            let ferrule = Path(roundedRect: CGRect(x: -2, y: -7.5, width: 26, height: 15), cornerRadius: 3)
            let collar = Path(roundedRect: CGRect(x: 22, y: -6, width: 6, height: 12), cornerRadius: 1.5)
            let glass = PlugArt.pin(from: 27, to: 66, halfHeight: 4.2, clip: clip)

            // The gas glows right through the glass, so draw the glow first, under everything.
            if let glass {
                var line = Path()
                line.move(to: CGPoint(x: 27, y: 0))
                line.addLine(to: CGPoint(x: min(64, clip), y: 0))
                NeonArt.tube(&ctx, line, color: plug.jacket, width: 5, glow: 8)
            }

            PlugArt.dropShadow(&ctx, [ferrule, collar], opacity: 0.3)
            ctx.fill(ferrule, with: PlugArt.metal(-7.5, 7.5, light: 0.8))
            ctx.stroke(ferrule, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
            for i in 0..<3 { // knurl rings
                let x = 3 + CGFloat(i) * 6
                ctx.fill(Path(CGRect(x: x, y: -7.5, width: 1.2, height: 15)), with: .color(.black.opacity(0.3)))
                ctx.fill(Path(CGRect(x: x + 1.2, y: -7.5, width: 0.7, height: 15)), with: .color(.white.opacity(0.25)))
            }
            ctx.fill(collar, with: .color(Color(white: 0.2)))

            if let glass {
                // Clear glass: a faint tint plus a top highlight, over the glow.
                ctx.fill(glass, with: .color(.white.opacity(0.14)))
                ctx.stroke(glass, with: .color(.white.opacity(0.55)), lineWidth: 0.7)
                if let hi = PlugArt.pin(from: 29, to: 63, halfHeight: 0.6, clip: clip) {
                    ctx.fill(hi.applying(CGAffineTransform(translationX: 0, y: -2.6)), with: .color(.white.opacity(0.5)))
                }
                // Wire electrode inside the tip.
                if let wire = PlugArt.pin(from: 52, to: 64, halfHeight: 0.8, clip: clip) {
                    ctx.fill(wire, with: PlugArt.nickel)
                }
            }
        },
        socket: { s in
            ZStack {
                // Ceramic holder.
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                Circle().fill(s.hole).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                // The glass end-on: lit in the socket's tint once seated.
                s.cover(
                    Circle(),
                    size: CGSize(width: 14, height: 14),
                    fill: LinearGradient(
                        colors: [s.tint.opacity(0.95), s.tint.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .shadow(color: s.tint.opacity(s.isSeated ? 0.9 : 0), radius: 8)
                s.ring(Circle(), size: CGSize(width: 34, height: 34))
            }
        },
    )
}
