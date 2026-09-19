import SwiftUI
import Testing
@testable import CableKit

// MARK: - DataFlowStyleTests

struct DataFlowStyleTests {
    @Test
    func `none pattern is empty`() {
        #expect(DataFlowStyle.none.pattern.isEmpty)
    }

    @Test
    func `bits pattern alternates lit and gap`() {
        let pattern = DataFlowStyle.bits.pattern
        #expect(!pattern.isEmpty)
        #expect(pattern.count.isMultiple(of: 2))
    }

    @Test
    func `morse encodes A single letter`() {
        // "E" is one dot: lit for 1 unit, then the word gap.
        #expect(DataFlowStyle.morse("E").pattern == [1, 7])
    }

    @Test
    func `morse uses letter and word gaps`() {
        // "SOS": three dots, three dashes, three dots. Letter gaps are 3, the trailing word gap is 7.
        let pattern = DataFlowStyle.morse("sos").pattern
        #expect(pattern == [1, 1, 1, 1, 1, 3, 3, 1, 3, 1, 3, 3, 1, 1, 1, 1, 1, 7])
    }

    @Test
    func `morse ignores unknown characters and falls back`() {
        #expect(DataFlowStyle.morse("").pattern == [1, 3])
        #expect(DataFlowStyle.morse("!?").pattern == [1, 3])
        #expect(DataFlowStyle.morse("E!").pattern == [1, 7])
    }
}

// MARK: - SparkTriggerTests

struct SparkTriggerTests {
    @Test(arguments: SparkTrigger.allCases)
    func `round trips through its flags`(trigger: SparkTrigger) {
        #expect(SparkTrigger(plugIn: trigger.includesPlugIn, unplug: trigger.includesUnplug) == trigger)
    }
}

// MARK: - CableConfigurationTests

struct CableConfigurationTests {
    @Test
    func `defaults are equal`() {
        #expect(CableConfiguration() == CableConfiguration())
    }

    @Test
    func `any visual change breaks equality`() {
        var config = CableConfiguration()
        config.cable.color = .cyan
        #expect(config != CableConfiguration())
        #expect(config.cable.color == .cyan)
    }

    @Test
    @MainActor
    func `providers compare by identity`() {
        var a = CableConfiguration()
        var b = CableConfiguration()
        let shared = SilentCableFeedback()
        a.haptics = shared
        b.haptics = shared
        #expect(a == b)
        b.haptics = SilentCableFeedback()
        #expect(a != b)
    }

    @Test
    func `a free layout socket needs only an id and a title`() {
        let socket = PlugSocket(id: 1, title: "Left")
        #expect(socket.systemImage == "circle")
        #expect(socket.isEnabled)
        #expect(socket.accepts == nil)
    }
}

// MARK: - PlugStyleTests

struct PlugStyleTests {
    @Test
    func `built in styles have unique I ds`() {
        let ids = PlugStyle.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test(arguments: PlugStyle.builtIn)
    func `built in lookup round trips`(style: PlugStyle) {
        #expect(PlugStyle.builtIn(id: style.id) == style)
        #expect(style.insertTravel < style.length)
    }

    @Test
    func `automatic theme follows color scheme`() {
        #expect(CableTheme.automatic(for: .dark) == .dark)
        #expect(CableTheme.automatic(for: .light) == .light)
    }
}

// MARK: - CableStylePresetTests

struct CableStylePresetTests {
    @Test
    func `ribbon and neon provide renderers`() {
        #expect(CableStyle.ribbon().renderer != nil)
        #expect(CableStyle.neon().renderer != nil)
        #expect(CableStyle.neon().shadowOpacity == 0)
        #expect(CableStyle.ribbon(width: 30).width == 30)
    }

    @Test
    func `coiled style supplies renderer and data path`() {
        let style = CableStyle.coiled()
        #expect(style.renderer != nil)
        #expect(style.dataFlowPath != nil)
        #expect(style == CableStyle.coiled())
        #expect(style != CableStyle())
    }

    @Test
    func `coiled data path follows the rope`() throws {
        let style = CableStyle.coiled(coilRadius: 8, pitch: 10, leadLength: 10)
        let points = (0..<30).map { CGPoint(x: CGFloat($0) * 10, y: 100) }
        var centre = Path()
        centre.move(to: points[0])
        for p in points.dropFirst() {
            centre.addLine(to: p)
        }
        let context = CableDrawingContext(
            path: centre,
            points: points,
            stretch: 0,
            style: style,
            theme: .light,
            width: style.width,
            jacket: style.color,
        )
        let bounds = try #require(style.dataFlowPath?(context).boundingRect)
        // Spans the rope and swings out by the coil radius, but no further.
        #expect(bounds.minX < 5)
        #expect(bounds.maxX > 285)
        #expect(abs(bounds.minY - 92) < 1)
        #expect(abs(bounds.maxY - 108) < 1)
    }
}

// MARK: - PlugSocketTests

struct PlugSocketTests {
    @Test
    func `accepts anything by default`() {
        let socket = PlugSocket(id: 1, title: "A", systemImage: "circle")
        #expect(socket.accepts(.audioJack))
        #expect(socket.accepts(.usbC))
    }

    @Test
    func `accepts only the listed styles`() {
        let socket = PlugSocket(id: 1, title: "A", systemImage: "circle", accepts: [.usbC, .magSafe])
        #expect(socket.accepts(.usbC))
        #expect(socket.accepts(.magSafe))
        #expect(!socket.accepts(.audioJack))
    }

    @Test
    func `row state carries the cable`() {
        let state = SocketRowState(isConnected: true, cableID: AnyHashable("left"))
        #expect(state.cableID == AnyHashable("left"))
        #expect(SocketRowState().cableID == nil)
    }
}
