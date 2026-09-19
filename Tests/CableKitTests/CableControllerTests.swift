import CoreGraphics
import Testing
@testable import CableKit

/// Drives the interaction state machine without a view or display link: layout → gestures → `advance(by:)`.
@MainActor
struct CableControllerTests {

    // MARK: Internal

    enum Socket: Hashable {
        case a
        case b
    }

    @Test
    func `starts hanging once laid out`() {
        let c = Self.laidOut()
        #expect(c.phase == .hanging)
        #expect(c.connected == nil)
        #expect(c.points.count == c.config.segmentCount)
        #expect(c.points.first == Self.anchor)
    }

    @Test
    func `dragging the plug onto a socket hovers, snaps and seats`() throws {
        let c = Self.laidOut()
        var events = [CableEvent<Socket>]()
        var connection: Socket??
        c.onEvent = { events.append($0) }
        c.onConnectionChange = { connection = .some($0) }

        Self.dragPlug(c, to: try #require(Self.sockets[.a]))
        c.advance(by: 0.1)
        #expect(c.phase == .dragging)
        #expect(c.hovered == .a)
        #expect(events.contains(.grabbed))
        #expect(events.contains(.hover(.a)))

        c.dragEnded()
        #expect(c.phase == .snapping(.a))
        c.advance(by: 2)
        #expect(c.phase == .plugged(.a))
        #expect(c.connected == .a)
        #expect(events.contains(.plugged(.a)))
        #expect(connection == .some(.a))
    }

    @Test
    func `releasing away from every socket drops the plug`() {
        let c = Self.laidOut()
        var events = [CableEvent<Socket>]()
        c.onEvent = { events.append($0) }

        Self.dragPlug(c, to: CGPoint(x: 150, y: 500))
        c.advance(by: 0.1)
        #expect(c.hovered == nil)
        c.dragEnded()
        #expect(c.phase == .hanging)
        #expect(events.contains(.dropped))
    }

    @Test
    func `a disabled socket refuses the plug`() throws {
        let c = Self.laidOut(enabled: [.a: false, .b: true])
        Self.dragPlug(c, to: try #require(Self.sockets[.a]))
        c.advance(by: 0.1)
        #expect(c.hovered == nil)
        c.dragEnded()
        #expect(c.phase == .hanging)
        #expect(c.connected == nil)
    }

    @Test
    func `tapping the seated socket ejects`() {
        let c = Self.seated(in: .a)
        var events = [CableEvent<Socket>]()
        var connection: Socket??
        c.onEvent = { events.append($0) }
        c.onConnectionChange = { connection = .some($0) }

        c.tapSocket(.a)
        #expect(c.phase == .hanging)
        #expect(c.connected == nil)
        #expect(events.contains(.unplugged(.a)))
        #expect(connection == .some(nil))
    }

    @Test
    func `tapping another socket moves the plug`() {
        let c = Self.seated(in: .a)
        var events = [CableEvent<Socket>]()
        c.onEvent = { events.append($0) }

        c.tapSocket(.b)
        #expect(events.contains(.unplugged(.a)))
        c.advance(by: 2)
        #expect(c.phase == .plugged(.b))
        #expect(events.contains(.plugged(.b)))
    }

    @Test
    func `a quick tap on the seated plug ejects it`() {
        let c = Self.seated(in: .a)
        let head = c.headCenter
        c.dragChanged(at: head, start: head)
        #expect(c.phase == .tugging(.a))
        c.dragEnded()
        #expect(c.phase == .hanging)
    }

    @Test
    func `pulling a seated plug past the unplug distance ejects it`() {
        let c = Self.seated(in: .a)
        let head = c.headCenter
        var events = [CableEvent<Socket>]()
        c.onEvent = { events.append($0) }
        c.dragChanged(at: head, start: head)
        c.dragChanged(at: CGPoint(x: head.x - c.config.unplugDistance * 2, y: head.y), start: head)
        #expect(c.phase == .ejecting(.a))
        #expect(events.contains(.unplugged(.a)))
        c.advance(by: 0.5)
        #expect(c.phase == .dragging)
    }

    @Test
    func `a connection requested before layout seats on the first layout pass`() {
        let c = CableController<Socket>(config: Self.config)
        c.setConnection(.a, animated: false)
        Self.layout(c)
        #expect(c.phase == .plugged(.a))
        #expect(c.connected == .a)
    }

    @Test
    func `a connection to an unknown socket falls back to hanging`() {
        let c = CableController<Socket>(config: Self.config)
        c.setConnection(.a, animated: false)
        c.updateLayout(anchor: Self.anchor, sockets: [:], enabled: [:], bounds: Self.bounds)
        #expect(c.phase == .hanging)
    }

    @Test
    func `setting the connection programmatically without animation seats immediately`() {
        let c = Self.laidOut()
        c.setConnection(.b, animated: false)
        #expect(c.phase == .plugged(.b))
        c.setConnection(nil)
        #expect(c.phase == .hanging)
    }

    @Test
    func `stopping mid drag releases the plug and clears the hover`() throws {
        let c = Self.laidOut()
        var events = [CableEvent<Socket>]()
        c.onEvent = { events.append($0) }
        Self.dragPlug(c, to: try #require(Self.sockets[.a]))
        c.advance(by: 0.1)
        #expect(c.phase == .dragging)
        #expect(c.hovered == .a)
        c.stop()
        #expect(c.phase == .hanging)
        #expect(c.hovered == nil)
        #expect(events.last == .hover(nil))
    }

    @Test
    func `a length change while plugged keeps the plug seated`() {
        let c = Self.seated(in: .a)
        var config = c.config
        config.restLength = 500
        c.updateConfig(config)
        c.advance(by: 0.5)
        #expect(c.phase == .plugged(.a))
    }

    @Test
    func `an identical configuration is ignored`() {
        let c = Self.laidOut()
        let before = c.points
        c.updateConfig(c.config)
        #expect(c.points == before)
    }

    // MARK: Private

    private static let anchor = CGPoint(x: 20, y: 100)
    private static let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    private static let sockets: [Socket: CGPoint] = [.a: CGPoint(x: 320, y: 120), .b: CGPoint(x: 320, y: 320)]

    private static var config: CableConfiguration {
        var c = CableConfiguration()
        c.hapticsEnabled = false
        c.soundEnabled = false
        c.haptics = SilentCableFeedback()
        c.sounds = SilentCableFeedback()
        c.spark = .none
        c.gravityFollowsDevice = false
        return c
    }

    private static func layout(_ c: CableController<Socket>, enabled: [Socket: Bool] = [.a: true, .b: true]) {
        c.updateLayout(anchor: anchor, sockets: sockets, enabled: enabled, bounds: bounds)
    }

    private static func laidOut(enabled: [Socket: Bool] = [.a: true, .b: true]) -> CableController<Socket> {
        let c = CableController<Socket>(config: config)
        layout(c, enabled: enabled)
        return c
    }

    private static func seated(in socket: Socket) -> CableController<Socket> {
        let c = laidOut()
        c.setConnection(socket, animated: false)
        c.advance(by: 0.5)
        return c
    }

    /// Picks the plug up by its body and moves the finger to `point` in a few steps.
    private static func dragPlug(_ c: CableController<Socket>, to point: CGPoint) {
        let start = c.headCenter
        c.dragChanged(at: start, start: start)
        for i in 1...4 {
            let t = CGFloat(i) / 4
            c.dragChanged(at: CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t), start: start)
            c.advance(by: 1 / 60)
        }
    }

}
