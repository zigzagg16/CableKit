import SwiftUI

// MARK: - CableCanvas

/// Draws the rope, the data traffic and the plug head. Pure rendering; all state comes from the controller.
///
/// Honours Reduce Motion: the physics stays (it *is* the control), but the flickering spark and the scrolling
/// data traffic — pure decoration — are not drawn.
///
/// Draw order, back to front: cable (default tube or the style's custom renderer), data traffic along it, the
/// spark, then the plug in its own translated-and-rotated context so plug styles draw in a simple local space
/// (origin at the boot, +x toward the tip). Reading the controller's properties inside the `Canvas` closure is
/// what subscribes this view to them, so a `publish()` redraws exactly this canvas and nothing else.
struct CableCanvas<ID: Hashable>: View {

    // MARK: Internal

    let controller: CableController<ID>
    let config: CableConfiguration
    let theme: CableTheme

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            let pts = controller.points
            guard pts.count >= 4 else { return }
            let stretch = controller.stretch
            let style = config.cable
            let path = smoothPath(pts)
            let w = style.width * (1 - stretch * style.stretchThinning)
            let jacket = style.stretchedColor.map { blend(style.color, $0, stretch * stretch, in: ctx.environment) } ?? style
                .color

            let cable = CableDrawingContext(
                path: path,
                points: pts,
                stretch: stretch,
                style: style,
                theme: theme,
                width: w,
                jacket: jacket,
                environment: ctx.environment,
            )
            if let renderer = style.renderer {
                var c = ctx
                renderer(&c, cable)
            } else {
                drawDefaultCable(ctx, cable)
            }

            if !reduceMotion {
                drawDataFlow(ctx, path: style.dataFlowPath?(cable) ?? path, width: w)
            }

            if let spark = controller.spark, !reduceMotion {
                let tail = pts[pts.count - 1]
                let tip = CGPoint(
                    x: tail.x + cos(controller.headAngle) * config.plugStyle.length,
                    y: tail.y + sin(controller.headAngle) * config.plugStyle.length,
                )
                drawSpark(ctx, from: spark.from, to: tip, progress: spark.progress, seed: spark.seed, intensity: spark.intensity)
            }

            var plugCtx = ctx
            plugCtx.translateBy(x: pts[pts.count - 1].x, y: pts[pts.count - 1].y)
            plugCtx.rotate(by: .radians(controller.headAngle))
            let plug = PlugDrawingContext(
                jacket: jacket,
                stretch: stretch,
                stretchedColor: style.stretchedColor,
                pinClipX: controller.pinClipX,
                configuration: config,
                environment: ctx.environment,
            )
            config.plugStyle.draw(&plugCtx, plug)
        }
    }

    // MARK: Private

    /// Tiny deterministic RNG (SplitMix64) so each flicker frame has a stable shape: the same seed always
    /// yields the same bolt, and the controller bumps the seed ~45 times a second to animate it.
    private struct SplitMix {
        init(seed: UInt64) {
            state = seed
        }

        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextUnit() -> CGFloat {
            CGFloat(next() >> 11) / CGFloat(1 << 53)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shadowOpacity: Double {
        config.cable.shadowOpacity ?? theme.shadowOpacity
    }

    private func drawDefaultCable(_ ctx: GraphicsContext, _ cable: CableDrawingContext) {
        let w = cable.width
        let path = cable.path
        let style = cable.style
        let round = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)

        // Drop shadow
        if shadowOpacity > 0 {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 7))
                layer.stroke(path, with: .color(.black.opacity(0.001)), style: round)
            }
        }
        // Dark rim → jacket → highlights = cheap tube shading
        ctx.stroke(
            path,
            with: .color(PlugArt.darken(cable.jacket, by: style.rimShade, in: cable.environment)),
            style: StrokeStyle(lineWidth: w + 2.5, lineCap: .round, lineJoin: .round),
        )
        ctx.stroke(path, with: .color(cable.jacket), style: round)
        if style.highlight > 0 {
            var hi = ctx
            hi.translateBy(x: -w * 0.14, y: -w * 0.24)
            hi.stroke(
                path,
                with: .color(.white.opacity(style.highlight)),
                style: StrokeStyle(lineWidth: w * 0.32, lineCap: .round, lineJoin: .round),
            )
            hi.translateBy(x: 0, y: -w * 0.06)
            hi.stroke(
                path,
                with: .color(.white.opacity(style.highlight * 1.1)),
                style: StrokeStyle(lineWidth: w * 0.09, lineCap: .round, lineJoin: .round),
            )
        }
    }

    /// A dashed pattern (bits or Morse) travelling along the cable. The path runs source → plug,
    /// so a negative phase moves toward the plug.
    private func drawDataFlow(_ ctx: GraphicsContext, path: Path, width w: CGFloat) {
        guard controller.dataOpacity > 0 else { return }
        let dash = config.dataFlow.pattern.map { $0 * config.dataFlowUnit }
        guard !dash.isEmpty else { return }
        let phase = config.dataFlowDirection == .toSocket ? -controller.dataPhase : controller.dataPhase
        let color = config.dataFlowColor ?? .white
        let alpha = config.dataFlowOpacity * controller.dataOpacity
        let lineWidth = max(0.5, w * config.dataFlowWidth)
        if config.dataFlowGlow > 0 {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: config.dataFlowGlow))
                layer.stroke(
                    path,
                    with: .color(color.opacity(alpha * 0.6)),
                    style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round, dash: dash, dashPhase: phase),
                )
            }
        }
        // Runs along the highlight line so it reads as light inside the jacket.
        var line = ctx
        line.translateBy(x: -w * 0.05, y: -w * 0.12)
        line.stroke(
            path,
            with: .color(color.opacity(alpha)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash, dashPhase: phase),
        )
    }

    /// A jagged, flickering arc between the socket face and the pin tip, fading out as it stretches.
    private func drawSpark(
        _ ctx: GraphicsContext,
        from a: CGPoint,
        to b: CGPoint,
        progress: CGFloat,
        seed: Int,
        intensity: CGFloat,
    ) {
        let fade = pow(1 - progress, 1.4) * (0.5 + 0.5 * intensity)
        guard fade > 0.02 else { return }
        let scale = 0.45 + 0.55 * intensity
        var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)) &+ 0x9E37)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(hypot(dx, dy), 1)
        let nx = -dy / len
        let ny = dx / len // perpendicular
        let amplitude = min(14, 4 + len * 0.18) * (0.6 + 0.4 * (1 - progress)) * scale

        func bolt(segments: Int, amp: CGFloat, start: CGFloat = 0, end: CGFloat = 1, fromPoint: CGPoint? = nil) -> Path {
            var p = Path()
            let s0 = fromPoint ?? CGPoint(x: a.x + dx * start, y: a.y + dy * start)
            p.move(to: s0)
            for i in 1...segments {
                let t = start + (end - start) * CGFloat(i) / CGFloat(segments)
                let taper = sin(.pi * CGFloat(i) / CGFloat(segments)) // pinned at both ends
                let off = (rng.nextUnit() * 2 - 1) * amp * (0.35 + 0.65 * taper)
                p.addLine(to: CGPoint(x: a.x + dx * t + nx * off, y: a.y + dy * t + ny * off))
            }
            return p
        }

        let main = bolt(segments: max(6, Int(len / 9)), amp: amplitude)
        // One or two short branches peeling off the main bolt
        var branches = [Path]()
        let branchCount = intensity < 0.5 ? (rng.nextUnit() > 0.6 ? 1 : 0) : (rng.nextUnit() > 0.4 ? 2 : 1)
        for _ in 0..<branchCount {
            let t0 = 0.25 + rng.nextUnit() * 0.5
            let origin = CGPoint(
                x: a.x + dx * t0 + nx * (rng.nextUnit() * 2 - 1) * amplitude * 0.5,
                y: a.y + dy * t0 + ny * (rng.nextUnit() * 2 - 1) * amplitude * 0.5,
            )
            branches.append(bolt(
                segments: 4,
                amp: amplitude * 0.8,
                start: t0,
                end: min(1, t0 + 0.25 + rng.nextUnit() * 0.2),
                fromPoint: origin,
            ))
        }

        let glow = config.sparkColor
        var all = main
        for branch in branches { all.addPath(branch) }

        // Outer glow, inner glow, white-hot core
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.stroke(
                all,
                with: .color(glow.opacity(0.7 * fade)),
                style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round, lineJoin: .round),
            )
        }
        ctx.stroke(
            all,
            with: .color(glow.opacity(0.9 * fade)),
            style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round, lineJoin: .round),
        )
        ctx.stroke(
            main,
            with: .color(.white.opacity(fade)),
            style: StrokeStyle(lineWidth: max(0.6, 1.1 * scale), lineCap: .round, lineJoin: .round),
        )
        for b in branches {
            ctx.stroke(
                b,
                with: .color(.white.opacity(0.7 * fade)),
                style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round),
            )
        }
        // Hot spots at both contacts
        for p in [a, b] {
            let r = 5 * scale
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4 * scale))
                layer.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(glow.opacity(0.9 * fade)),
                )
            }
            let c = 1.8 * scale
            ctx.fill(
                Path(ellipseIn: CGRect(x: p.x - c, y: p.y - c, width: c * 2, height: c * 2)),
                with: .color(.white.opacity(fade)),
            )
        }
    }

    /// Catmull-Rom through the rope nodes, expressed as cubic Béziers, so 30 straight segments read as a
    /// smooth cable.
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, n - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Linear mix of two colours in resolved RGB, used to tint the jacket toward `stretchedColor` under tension.
    private func blend(_ a: Color, _ b: Color, _ t: CGFloat, in environment: EnvironmentValues) -> Color {
        let ca = a.resolve(in: environment)
        let cb = b.resolve(in: environment)

        return Color(
            red: Double(ca.red + (cb.red - ca.red) * Float(t)),
            green: Double(ca.green + (cb.green - ca.green) * Float(t)),
            blue: Double(ca.blue + (cb.blue - ca.blue) * Float(t)),
        )
    }

}
