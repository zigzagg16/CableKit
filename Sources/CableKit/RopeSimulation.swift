import CoreGraphics

/// Position-based (Verlet) rope: a chain of points with distance constraints, gravity,
/// damping, a floor and side walls, plus a rigid "head" segment (the plug) hanging off the
/// last node. Pure value type, no SwiftUI.
///
/// Node 0 is the anchor (the source port). Node `count - 1` is the rope's end where the plug's boot sits;
/// `tip` is a separate node exactly `headLength` further on, so the plug is a rigid body the rope can swing.
/// Velocity is implicit — each node keeps its previous position — which is what makes pinning a node
/// (`tail`, `tipPin`, `grabbedNode`) trivial: overwrite its position and the constraints do the rest.
struct RopeSimulation {

    // MARK: Lifecycle

    init(count: Int, segmentLength: CGFloat, anchor: CGPoint, gravity: CGFloat, damping: CGFloat) {
        self.segmentLength = segmentLength
        self.anchor = anchor
        self.gravity = CGVector(dx: 0, dy: gravity)
        self.damping = damping
        nodes = (0..<max(count, 3)).map { i in
            let p = CGPoint(x: anchor.x + CGFloat(i) * 2, y: anchor.y + CGFloat(i) * 2)
            return Node(pos: p, prev: p)
        }
        tip = nodes[nodes.count - 1]
    }

    // MARK: Internal

    struct Node {
        var pos: CGPoint
        var prev: CGPoint
    }

    private(set) var nodes: [Node]
    /// The plug tip. Rigidly `headLength` away from the last rope node.
    private(set) var tip: Node
    var headLength: CGFloat = 66
    /// How much of a tail↔tip correction the tip takes (the rest moves the rope end). Lower = heavier plug.
    var tipMass: CGFloat = 0.25

    var segmentLength: CGFloat
    /// Gravity as a vector, points / s².
    var gravity: CGVector
    var damping: CGFloat
    var iterations = 14
    /// Fraction of each distance error corrected per iteration (1 = rigid, lower = stretchy rope).
    var stiffness: CGFloat = 1
    var bounds = CGRect.zero
    var floorInset: CGFloat = 8

    /// First node is always pinned here; second node is eased so the cable exits horizontally.
    var anchor: CGPoint
    /// Optional pin for the last rope node (the boot of the plug).
    var tail: CGPoint?
    /// Optional pin for the plug tip.
    var tipPin: CGPoint?
    /// A rope node held by a finger: (index, position). Never the anchor or the last node.
    var grabbedNode: (index: Int, position: CGPoint)?
    /// How firmly the grabbed node follows the finger per iteration (1 = rigid pin, lower = held loosely).
    var grabStrength: CGFloat = 0.5
    /// Unit direction the plug points when seated. Used to align the rope's last segment behind the
    /// tail (so the cable enters the socket straight) and to level the head near a socket.
    var entryDirection = CGVector(dx: 1, dy: 0)
    /// When true the second-to-last node is pulled behind the tail along `entryDirection`.
    var alignTail = false
    /// Soft pull of the rope end toward a position behind the tip along `entryDirection` (0 = none, 1 = hard).
    var levelHead: CGFloat = 0

    var count: Int {
        nodes.count
    }

    var points: [CGPoint] {
        nodes.map(\.pos)
    }

    var head: CGPoint {
        nodes[nodes.count - 1].pos
    }

    var tipPosition: CGPoint {
        tip.pos
    }

    var headVelocity: CGVector {
        let n = nodes[nodes.count - 1]
        return CGVector(dx: n.pos.x - n.prev.x, dy: n.pos.y - n.prev.y)
    }

    var tipVelocity: CGVector {
        CGVector(dx: tip.pos.x - tip.prev.x, dy: tip.pos.y - tip.prev.y)
    }

    /// Direction the plug points (rope end → tip), radians.
    var headAngle: CGFloat {
        atan2(tip.pos.y - head.y, tip.pos.x - head.x)
    }

    /// Largest per-node displacement in the last step — used to sleep the display link.
    var kineticEnergy: CGFloat {
        let rope = nodes.reduce(0) { max($0, abs($1.pos.x - $1.prev.x) + abs($1.pos.y - $1.prev.y)) }
        return max(rope, abs(tip.pos.x - tip.prev.x) + abs(tip.pos.y - tip.prev.y))
    }

    /// Index of the rope node closest to a point (excluding the anchor end), and its distance.
    func nearestNode(to p: CGPoint) -> (index: Int, distance: CGFloat) {
        var best = (index: 2, distance: CGFloat.infinity)
        for i in 2..<nodes.count {
            let d = hypot(nodes[i].pos.x - p.x, nodes[i].pos.y - p.y)
            if d < best.distance {
                best = (i, d)
            }
        }
        return best
    }

    /// Lay the rope out in a straight line from the anchor to a point, with the plug pointing on along it.
    mutating func reset(toward target: CGPoint, tipToward direction: CGVector) {
        let n = CGFloat(nodes.count - 1)
        for i in nodes.indices {
            let t = CGFloat(i) / n
            let p = CGPoint(x: anchor.x + (target.x - anchor.x) * t, y: anchor.y + (target.y - anchor.y) * t)
            nodes[i] = Node(pos: p, prev: p)
        }
        let len = max(hypot(direction.dx, direction.dy), 0.001)
        let tp = CGPoint(x: target.x + direction.dx / len * headLength, y: target.y + direction.dy / len * headLength)
        tip = Node(pos: tp, prev: tp)
    }

    /// Advances the rope by `dt` seconds: integrate every free node, then relax the constraints `iterations`
    /// times. Within one relaxation pass the order is deliberate — pins first (so they win), then the
    /// distance chain from anchor to plug, then the plug's rigid segment, then collisions last so nothing ends
    /// the pass inside the floor.
    mutating func step(dt: CGFloat) {
        // A longer frame (a hitch) would inject a burst of gravity; clamp rather than explode.
        let dt = min(dt, 1.0 / 30.0)
        let gx = gravity.dx * dt * dt
        let gy = gravity.dy * dt * dt
        let last = nodes.count - 1

        // Integrate
        for i in 1...last { integrate(&nodes[i], gx: gx, gy: gy) }
        integrate(&tip, gx: gx, gy: gy)

        // Constraints
        for _ in 0..<iterations {
            nodes[0].pos = anchor
            // Ease the second node so the cable leaves the port straight.
            let exit = CGPoint(x: anchor.x + segmentLength, y: anchor.y)
            nodes[1].pos.x += (exit.x - nodes[1].pos.x) * 0.35
            nodes[1].pos.y += (exit.y - nodes[1].pos.y) * 0.35

            if let tail {
                nodes[last].pos = tail
                if alignTail {
                    let entry = CGPoint(
                        x: tail.x - entryDirection.dx * segmentLength,
                        y: tail.y - entryDirection.dy * segmentLength,
                    )
                    nodes[last - 1].pos.x += (entry.x - nodes[last - 1].pos.x) * 0.5
                    nodes[last - 1].pos.y += (entry.y - nodes[last - 1].pos.y) * 0.5
                }
            }
            if let tipPin {
                tip.pos = tipPin
            }
            if let g = grabbedNode, g.index > 1, g.index < last {
                nodes[g.index].pos.x += (g.position.x - nodes[g.index].pos.x) * grabStrength
                nodes[g.index].pos.y += (g.position.y - nodes[g.index].pos.y) * grabStrength
            }

            // Distance constraints along the chain. A pinned end passes its whole correction to the other node;
            // `stiffness` < 1 leaves some error each pass, which reads as a stretchy rope.
            for i in 0..<last {
                let a = nodes[i].pos
                let b = nodes[i + 1].pos
                let dx = b.x - a.x
                let dy = b.y - a.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.0001)
                let diff = (dist - segmentLength) / dist * stiffness
                let ox = dx * diff * 0.5
                let oy = dy * diff * 0.5
                let aPinned = i == 0
                let bPinned = (i + 1 == last) && tail != nil
                if aPinned, bPinned {
                    continue
                }
                if aPinned {
                    nodes[i + 1].pos.x -= ox * 2
                    nodes[i + 1].pos.y -= oy * 2
                } else if bPinned {
                    nodes[i].pos.x += ox * 2
                    nodes[i].pos.y += oy * 2
                } else {
                    nodes[i].pos.x += ox
                    nodes[i].pos.y += oy
                    nodes[i + 1].pos.x -= ox
                    nodes[i + 1].pos.y -= oy
                }
            }

            // Rigid plug: rope end ↔ tip at exactly headLength.
            if levelHead > 0, tail == nil {
                let behind = CGPoint(x: tip.pos.x - entryDirection.dx * headLength, y: tip.pos.y - entryDirection.dy * headLength)
                nodes[last].pos.x += (behind.x - nodes[last].pos.x) * levelHead
                nodes[last].pos.y += (behind.y - nodes[last].pos.y) * levelHead
            }
            do {
                let a = nodes[last].pos
                let b = tip.pos
                let dx = b.x - a.x
                let dy = b.y - a.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.0001)
                let diff = (dist - headLength) / dist
                let ox = dx * diff
                let oy = dy * diff
                let tailPinned = tail != nil
                let tipPinned = tipPin != nil
                if tailPinned, tipPinned {
                    // both fixed; nothing to do
                } else if tailPinned {
                    tip.pos.x -= ox
                    tip.pos.y -= oy
                } else if tipPinned {
                    nodes[last].pos.x += ox
                    nodes[last].pos.y += oy
                } else {
                    nodes[last].pos.x += ox * (1 - tipMass)
                    nodes[last].pos.y += oy * (1 - tipMass)
                    tip.pos.x -= ox * tipMass
                    tip.pos.y -= oy * tipMass
                }
            }

            // Floor + walls with friction
            if bounds.width > 0 {
                for i in 1...last { collide(&nodes[i]) }
                if tipPin == nil {
                    collide(&tip)
                }
            }
        }
    }

    // MARK: Private

    /// Verlet: the new position is the old one plus damped implicit velocity plus gravity.
    private func integrate(_ n: inout Node, gx: CGFloat, gy: CGFloat) {
        let vx = (n.pos.x - n.prev.x) * damping
        let vy = (n.pos.y - n.prev.y) * damping
        n.prev = n.pos
        n.pos.x += vx + gx
        n.pos.y += vy + gy
    }

    /// Clamps a node inside `bounds`, bleeding off tangential velocity so the rope skids to a stop rather than
    /// sliding along the floor forever.
    private func collide(_ n: inout Node) {
        let floorY = bounds.maxY - floorInset
        if n.pos.y > floorY {
            n.pos.y = floorY
            n.pos.x -= (n.pos.x - n.prev.x) * 0.6 // friction
        }
        let minX = bounds.minX + 4
        let maxX = bounds.maxX - 4
        if n.pos.x < minX {
            n.pos.x = minX
            n.pos.y -= (n.pos.y - n.prev.y) * 0.6
        }
        if n.pos.x > maxX {
            n.pos.x = maxX
            n.pos.y -= (n.pos.y - n.prev.y) * 0.6
        }
        n.pos.y = max(n.pos.y, bounds.minY + 4)
    }

}
