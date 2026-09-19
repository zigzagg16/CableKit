import SwiftUI

// MARK: - CableStyle.coiled

extension CableStyle {
    /// A coiled handset cord, like the one between an old desk phone and its receiver.
    ///
    /// The strand spirals around the rope's centreline. Pulling the cable taut stretches the coils
    /// apart and flattens them, and both ends keep a short straight lead so the cord leaves the port
    /// and enters the plug cleanly. Pairs well with ``PlugStyle/telephone``.
    ///
    /// - Parameters:
    ///   - color: Jacket colour of the strand.
    ///   - width: Thickness of the strand, in points.
    ///   - coilRadius: How far the strand swings out from the centreline at rest.
    ///   - pitch: Distance along the centreline per turn at rest.
    ///   - leadLength: Straight, uncoiled length at each end.
    public static func coiled(
        color: Color = Color(red: 0.93, green: 0.88, blue: 0.78),
        width: CGFloat = 6.5,
        coilRadius: CGFloat = 9,
        pitch: CGFloat = 11,
        leadLength: CGFloat = 18,
    ) -> CableStyle {
        let coil = Coil(radius: coilRadius, pitch: pitch, lead: leadLength, cache: Coil.Cache())
        return CableStyle(
            color: color,
            width: width,
            stretchThinning: 0.15,
            renderer: { ctx, cable in coil.draw(&ctx, cable) },
            dataFlowPath: { cable in coil.strandPath(cable) },
        )
    }
}

// MARK: - Coil

/// Helix geometry and rendering for ``CableStyle/coiled(color:width:coilRadius:pitch:leadLength:)``.
private struct Coil: Sendable {

    // MARK: Internal

    struct Sample {
        var point: CGPoint
        /// `sin` of the helix angle: positive is the half of the turn nearest the viewer.
        var depth: CGFloat
    }

    /// The renderer and the data-flow path are separate closures that both need the helix for the same frame;
    /// this shares one sampling between them.
    final class Cache: @unchecked Sendable {

        // MARK: Internal

        struct Key: Equatable {
            var points: [CGPoint]
            var stretch: CGFloat
        }

        func samples(for key: Key, make: () -> [Sample]) -> [Sample] {
            lock.lock()
            defer { lock.unlock() }
            if key == self.key {
                return samples
            }
            let fresh = make()
            self.key = key
            samples = fresh
            return fresh
        }

        // MARK: Private

        private let lock = NSLock()
        private var key: Key?
        private var samples = [Sample]()

    }

    var radius: CGFloat
    var pitch: CGFloat
    var lead: CGFloat
    var cache: Cache

    /// One continuous path through every sample, front and back — what the data traffic runs along.
    func strandPath(_ cable: CableDrawingContext) -> Path {
        var path = Path()
        let samples = samples(cable)
        guard let first = samples.first else { return path }
        path.move(to: first.point)
        for s in samples.dropFirst() {
            path.addLine(to: s.point)
        }
        return path
    }

    func draw(_ ctx: inout GraphicsContext, _ cable: CableDrawingContext) {
        let samples = samples(cable)
        guard samples.count > 1 else { return }
        let (front, back) = runs(samples)
        let w = cable.width
        let style = cable.style
        let round = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        let rim = StrokeStyle(lineWidth: w + 2, lineCap: .round, lineJoin: .round)
        let jacket = cable.jacket
        let shadowOpacity = style.shadowOpacity ?? cable.theme.shadowOpacity

        if shadowOpacity > 0 {
            var all = back
            all.addPath(front)
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(shadowOpacity), radius: 5, x: 0, y: 6))
                layer.stroke(all, with: .color(.black.opacity(0.001)), style: round)
            }
        }

        // The half of each turn that curls away from the viewer: darker, no highlight.
        ctx.stroke(
            back,
            with: .color(PlugArt.darken(jacket, by: min(1, style.rimShade + 0.2), in: cable.environment)),
            style: rim,
        )
        ctx.stroke(back, with: .color(PlugArt.darken(jacket, by: 0.3, in: cable.environment)), style: round)

        // The half that comes toward the viewer, shaded like the default tube.
        ctx.stroke(front, with: .color(PlugArt.darken(jacket, by: style.rimShade, in: cable.environment)), style: rim)
        ctx.stroke(front, with: .color(jacket), style: round)
        if style.highlight > 0 {
            var hi = ctx
            hi.translateBy(x: -w * 0.12, y: -w * 0.22)
            hi.stroke(
                front,
                with: .color(.white.opacity(style.highlight)),
                style: StrokeStyle(lineWidth: w * 0.3, lineCap: .round, lineJoin: .round),
            )
        }
    }

    // MARK: Private

    /// Samples the helix along the smoothed centreline, 14 points per turn. Cached per frame, see ``Cache``.
    private func samples(_ cable: CableDrawingContext) -> [Sample] {
        cache.samples(for: Cache.Key(points: cable.points, stretch: cable.stretch)) { sampleHelix(cable) }
    }

    private func sampleHelix(_ cable: CableDrawingContext) -> [Sample] {
        let sampler = CentrelineSampler(points: cable.points)

        guard sampler.isUsable else { return [] }
        let total = sampler.length

        // Tension pulls the turns apart and flattens them.
        let stretch = cable.stretch
        let effectivePitch = pitch * (1 + stretch * 1.8)
        let effectiveRadius = radius * (1 - stretch * 0.45)

        return sampler.frames(step: max(1.2, effectivePitch / 14)).map { f in
            // Straight leads: the radius ramps in over `lead` at both ends.
            let ramp = smoothstep(f.distance / lead) * smoothstep((total - f.distance) / lead)
            let angle = 2 * .pi * f.distance / effectivePitch
            return Sample(point: f.offset(effectiveRadius * ramp * cos(angle)), depth: sin(angle))
        }
    }

    /// Splits the samples into front-facing and back-facing runs, sharing the crossing sample so the
    /// strand stays continuous where it passes behind the centreline.
    private func runs(_ samples: [Sample]) -> (front: Path, back: Path) {
        var front = Path()
        var back = Path()
        var isFront = samples[0].depth >= 0
        var current = Path()
        current.move(to: samples[0].point)
        for s in samples.dropFirst() {
            let nowFront = s.depth >= 0
            current.addLine(to: s.point)
            if nowFront != isFront {
                if isFront {
                    front.addPath(current)
                } else {
                    back.addPath(current)
                }
                current = Path()
                current.move(to: s.point)
                isFront = nowFront
            }
        }
        if isFront {
            front.addPath(current)
        } else {
            back.addPath(current)
        }
        return (front, back)
    }

}
