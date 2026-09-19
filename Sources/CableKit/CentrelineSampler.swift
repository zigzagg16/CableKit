import SwiftUI

// MARK: - CentrelineSampler

/// The rope's centreline as a dense polyline that can be walked by arc length, for renderers that
/// build geometry off to the side of the cable (coils, ribbons, braids…).
///
/// The polyline is the same Catmull-Rom curve the default tube is stroked with, subdivided.
struct CentrelineSampler {

    // MARK: Lifecycle

    init(points: [CGPoint], subdivisions: Int = 6) {
        centre = Self.densify(points, subdivisions: subdivisions)
        var cumulative = [CGFloat](repeating: 0, count: centre.count)
        for i in 1..<max(centre.count, 1) {
            cumulative[i] = cumulative[i - 1] + hypot(centre[i].x - centre[i - 1].x, centre[i].y - centre[i - 1].y)
        }
        self.cumulative = cumulative
    }

    // MARK: Internal

    struct Frame {
        var point: CGPoint
        var tangent: CGVector
        /// Unit vector to the left of the tangent.
        var normal: CGVector
        /// Arc length from the source end.
        var distance: CGFloat

        /// A point offset sideways from the centreline.
        func offset(_ d: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.dx * d, y: point.y + normal.dy * d)
        }
    }

    /// Total arc length.
    var length: CGFloat {
        cumulative.last ?? 0
    }

    var isUsable: Bool {
        centre.count > 2 && length > 1
    }

    /// Frames every `step` points along the cable, always including both ends.
    func frames(step: CGFloat) -> [Frame] {
        guard isUsable else { return [] }
        var out = [Frame]()
        out.reserveCapacity(Int(length / step) + 2)
        var seg = 0
        var s: CGFloat = 0
        while s < length {
            out.append(frame(at: s, segmentHint: &seg))
            s += step
        }
        out.append(frame(at: length, segmentHint: &seg))
        return out
    }

    // MARK: Private

    private let centre: [CGPoint]
    private let cumulative: [CGFloat]

    private static func densify(_ pts: [CGPoint], subdivisions: Int) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        let n = pts.count
        var out: [CGPoint] = [pts[0]]
        out.reserveCapacity((n - 1) * subdivisions + 1)
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, n - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            for j in 1...subdivisions {
                let t = CGFloat(j) / CGFloat(subdivisions)
                let u = 1 - t
                let x = u * u * u * p1.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p2.x
                let y = u * u * u * p1.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p2.y
                out.append(CGPoint(x: x, y: y))
            }
        }
        return out
    }

    private func frame(at s: CGFloat, segmentHint seg: inout Int) -> Frame {
        while seg < centre.count - 2, cumulative[seg + 1] < s {
            seg += 1
        }
        let a = centre[seg]
        let b = centre[seg + 1]
        let len = max(cumulative[seg + 1] - cumulative[seg], 0.0001)
        let t = min(max((s - cumulative[seg]) / len, 0), 1)
        let tangent = CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
        return Frame(
            point: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
            tangent: tangent,
            normal: CGVector(dx: -tangent.dy, dy: tangent.dx),
            distance: s,
        )
    }

}

/// `x` clamped to 0…1 and eased.
func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}
