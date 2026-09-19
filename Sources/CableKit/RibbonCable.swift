import SwiftUI

// MARK: - CableStyle.ribbon

extension CableStyle {
    /// A flat multi-conductor ribbon cable, like the IDE and floppy cables inside an old PC:
    /// parallel grey conductors with a red stripe marking pin 1 along one edge.
    ///
    /// `width` is the full width of the ribbon. Pairs with ``PlugStyle/idc``.
    ///
    /// - Parameters:
    ///   - color: Jacket colour of the conductors.
    ///   - keyColor: Colour of the pin-1 stripe. `nil` for no stripe.
    ///   - width: Width of the whole ribbon, in points.
    ///   - conductors: How many conductors run side by side.
    public static func ribbon(
        color: Color = Color(white: 0.8),
        keyColor: Color? = Color(red: 0.85, green: 0.2, blue: 0.18),
        width: CGFloat = 22,
        conductors: Int = 10,
    ) -> CableStyle {
        let ribbon = Ribbon(keyColor: keyColor, conductors: max(2, conductors))
        return CableStyle(
            color: color,
            width: width,
            stretchThinning: 0,
            highlight: 0.4,
            renderer: { ctx, cable in ribbon.draw(&ctx, cable) },
        )
    }
}

// MARK: - Ribbon

private struct Ribbon: Sendable {

    // MARK: Internal

    var keyColor: Color?
    var conductors: Int

    func draw(_ ctx: inout GraphicsContext, _ cable: CableDrawingContext) {
        let sampler = CentrelineSampler(points: cable.points)
        guard sampler.isUsable else { return }
        let frames = sampler.frames(step: 3)
        let halfWidth = cable.width / 2
        let pitch = cable.width / CGFloat(conductors)
        let style = cable.style
        let jacket = cable.jacket
        let shadowOpacity = style.shadowOpacity ?? cable.theme.shadowOpacity

        let outline = band(frames, from: -halfWidth, to: halfWidth)
        if shadowOpacity > 0 {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(shadowOpacity), radius: 5, x: 0, y: 5))
                layer.fill(outline, with: .color(.black.opacity(0.001)))
            }
        }

        // Each conductor is a slightly rounded strand: lighter down its middle, a groove between neighbours.
        for i in 0..<conductors {
            let a = -halfWidth + CGFloat(i) * pitch
            let b = a + pitch
            let base = i == 0 ? keyColor ?? jacket : jacket
            ctx.fill(band(frames, from: a, to: b), with: .color(PlugArt.darken(base, by: 0.12, in: cable.environment)))
            ctx.fill(band(frames, from: a + pitch * 0.2, to: b - pitch * 0.3), with: .color(base))
            if style.highlight > 0 {
                ctx.fill(
                    band(frames, from: a + pitch * 0.3, to: a + pitch * 0.5),
                    with: .color(.white.opacity(style.highlight * 0.6)),
                )
            }
            if i > 0 {
                ctx.stroke(edge(frames, at: a), with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            }
        }
        ctx.stroke(outline, with: .color(.black.opacity(0.45)), lineWidth: 0.8)
    }

    // MARK: Private

    /// Closed strip between two sideways offsets: down one edge, back along the other.
    private func band(_ frames: [CentrelineSampler.Frame], from a: CGFloat, to b: CGFloat) -> Path {
        guard !frames.isEmpty else { return Path() }
        var outline = frames.map { $0.offset(a) }
        outline.append(contentsOf: frames.reversed().map { $0.offset(b) })
        var p = Path()
        p.addLines(outline)
        p.closeSubpath()
        return p
    }

    private func edge(_ frames: [CentrelineSampler.Frame], at d: CGFloat) -> Path {
        var p = Path()
        p.addLines(frames.map { $0.offset(d) })
        return p
    }

}

// MARK: - PlugStyle.idc

extension PlugStyle {
    /// IDC ribbon connector — the black block that clamps onto a ribbon cable and pushes onto a pin
    /// header, with a polarising key on top. Made for ``CableStyle/ribbon(color:keyColor:width:conductors:)``.
    public static let idc = PlugStyle(
        id: "idc",
        displayName: "IDC",
        length: 62,
        insertTravel: 11,
        socketFaceOffset: 7,
        draw: { ctx, plug in
            let clip = plug.clip
            // Strain-relief clamp the ribbon disappears into, as wide as the ribbon.
            let clamp = Path(roundedRect: CGRect(x: -4, y: -12.5, width: 16, height: 25), cornerRadius: 2)
            let body = Path(roundedRect: CGRect(x: 10, y: -11, width: 42, height: 22), cornerRadius: 2.5)
            let nose = PlugArt.pin(from: 50, to: 62, halfHeight: 9, clip: clip)
            PlugArt.dropShadow(&ctx, [clamp, body, nose ?? Path()])

            let black = Gradient(colors: [Color(white: 0.3), Color(white: 0.14), Color(white: 0.08), Color(white: 0.2)])
            ctx.fill(clamp, with: .linearGradient(black, startPoint: CGPoint(x: 0, y: -12.5), endPoint: CGPoint(x: 0, y: 12.5)))
            ctx.stroke(clamp, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
            ctx.fill(Path(CGRect(x: 3.5, y: -12.5, width: 1, height: 25)), with: .color(.white.opacity(0.12)))

            ctx.fill(body, with: .linearGradient(black, startPoint: CGPoint(x: 0, y: -11), endPoint: CGPoint(x: 0, y: 11)))
            ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
            // Polarising key on top and the pin-1 triangle.
            ctx.fill(
                Path(roundedRect: CGRect(x: 26, y: -14, width: 12, height: 4), cornerRadius: 1),
                with: .color(Color(white: 0.16)),
            )
            var mark = Path()
            mark.move(to: CGPoint(x: 14, y: -7))
            mark.addLine(to: CGPoint(x: 19, y: -4))
            mark.addLine(to: CGPoint(x: 14, y: -1))
            mark.closeSubpath()
            ctx.fill(mark, with: .color(.white.opacity(0.7)))
            // Faint moulding lines.
            for x: CGFloat in [22, 34, 46] {
                ctx.fill(Path(CGRect(x: x, y: -9, width: 0.8, height: 18)), with: .color(.white.opacity(0.08)))
            }

            if let nose {
                ctx.fill(nose, with: .color(Color(white: 0.12)))
                ctx.stroke(nose, with: .color(.black.opacity(0.7)), lineWidth: 0.6)
                // Two rows of contact slots along the nose.
                for y: CGFloat in [-3.5, 3.5] {
                    if let slot = PlugArt.pin(from: 52, to: 61, halfHeight: 1, clip: clip) {
                        ctx.fill(slot.applying(CGAffineTransform(translationX: 0, y: y)), with: PlugArt.gold)
                    }
                }
            }
        },
        socket: { s in
            ZStack {
                // Shrouded box header with the key notch at the top.
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(white: 0.16)).frame(width: 30, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(
                        .black.opacity(0.8),
                        lineWidth: 1,
                    ))
                Rectangle().fill(s.hole).frame(width: 8, height: 3).offset(y: -12)
                RoundedRectangle(cornerRadius: 1.5).fill(s.hole).frame(width: 24, height: 18)
                    .overlay {
                        VStack(spacing: 5) {
                            ForEach(0..<2, id: \.self) { _ in
                                HStack(spacing: 2.5) {
                                    ForEach(0..<5, id: \.self) { _ in
                                        Rectangle().fill(Color(red: 0.9, green: 0.75, blue: 0.35)).frame(width: 1.6, height: 1.6)
                                    }
                                }
                            }
                        }
                    }
                s.cover(RoundedRectangle(cornerRadius: 1.5), size: CGSize(width: 24, height: 18), fill: PlugArt.blackFace)
                s.ring(RoundedRectangle(cornerRadius: 3, style: .continuous), size: CGSize(width: 30, height: 26))
            }
        },
    )
}
