import CoreGraphics
import Testing
@testable import CableKit

struct RopeSimulationTests {

    // MARK: Internal

    @Test
    func `first node stays on the anchor`() {
        let sim = Self.settled()
        #expect(sim.points[0] == Self.anchor)
    }

    @Test
    func `segments keep their length once settled`() {
        let sim = Self.settled()
        let pts = sim.points
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            #expect(abs(d - sim.segmentLength) < 0.5, "segment \(i) is \(d)")
        }
    }

    @Test
    func `plug is rigidly attached to the rope end`() {
        let sim = Self.settled()
        let d = hypot(sim.tipPosition.x - sim.head.x, sim.tipPosition.y - sim.head.y)
        #expect(abs(d - sim.headLength) < 0.5)
    }

    @Test
    func `nothing falls through the floor or walls`() {
        let sim = Self.settled()
        let floor = Self.bounds.maxY - sim.floorInset
        for p in sim.points + [sim.tipPosition] {
            #expect(p.y <= floor + 0.01)
            #expect(p.x >= Self.bounds.minX)
            #expect(p.x <= Self.bounds.maxX)
        }
    }

    @Test
    func `hanging rope comes to rest`() {
        let sim = Self.settled()
        #expect(sim.kineticEnergy < 0.08)
    }

    @Test
    func `pinned tail and tip are honoured`() {
        let tail = CGPoint(x: 250, y: 300)
        let tip = CGPoint(x: 316, y: 300)
        let sim = Self.settled { sim in
            sim.tail = tail
            sim.tipPin = tip
        }
        #expect(sim.head == tail)
        #expect(sim.tipPosition == tip)
    }

    @Test
    func `reset lays the rope out straight`() {
        var sim = RopeSimulation(count: 10, segmentLength: 10, anchor: Self.anchor, gravity: 0, damping: 1)
        let target = CGPoint(x: 120, y: 100)
        sim.reset(toward: target, tipToward: CGVector(dx: 1, dy: 0))
        #expect(sim.points.first == Self.anchor)
        #expect(sim.points.last == target)
        #expect(sim.tipPosition == CGPoint(x: target.x + sim.headLength, y: target.y))
        #expect(sim.kineticEnergy == 0)
    }

    @Test
    func `nearest node skips the anchor end`() {
        let sim = Self.settled()
        let near = sim.nearestNode(to: Self.anchor)
        #expect(near.index >= 2)
    }

    // MARK: Private

    private static let anchor = CGPoint(x: 20, y: 100)
    private static let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private static func settled(_ configure: (inout RopeSimulation) -> Void = { _ in }) -> RopeSimulation {
        var sim = RopeSimulation(count: 30, segmentLength: 10, anchor: anchor, gravity: 2600, damping: 0.985)
        sim.bounds = bounds
        configure(&sim)
        for _ in 0..<600 {
            sim.step(dt: 1 / 120)
        }
        return sim
    }

}
