import CableKit
import SwiftUI

// MARK: - BayView

/// Several cables on one board: three cords from a stage box into a wall of sockets. Two sockets
/// only take USB‑C, so only the green cable fits them; a socket that already has a plug refuses the
/// others. Everything here is `CableBoard(cables:sockets:connections:)`.
struct BayView: View {

    // MARK: Internal

    enum Cord: String, CaseIterable, Hashable {
        case orange
        case blue
        case green

        var color: Color {
            switch self {
            case .orange: Color(red: 0.98, green: 0.45, blue: 0.18)
            case .blue: Color(red: 0.2, green: 0.55, blue: 1)
            case .green: Color(red: 0.25, green: 0.8, blue: 0.45)
            }
        }

        var plug: PlugStyle {
            self == .green ? .usbC : .audioJack
        }
    }

    enum Port: Int, CaseIterable, Hashable {
        case a1
        case a2
        case a3
        case b1
        case b2
        case b3

        var isUSB: Bool {
            self == .b2 || self == .b3
        }

        var title: String {
            isUSB ? "USB \(rawValue - 3)" : "Line \(rawValue + 1)"
        }
    }

    let settings: DemoSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patch bay")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                SettingsButton(isPresented: $showSettings)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            CableBoard(cables: cables, sockets: sockets, connections: $connections, configuration: config, onEvent: log) {
                VStack {
                    // The wall: two columns of sockets.
                    HStack {
                        VStack(spacing: 22) {
                            ForEach([Port.a1, .a2, .a3], id: \.self) { port in socketCell(port) }
                        }
                        Spacer()
                        VStack(spacing: 22) {
                            ForEach([Port.b1, .b2, .b3], id: \.self) { port in socketCell(port) }
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 30)
                    Spacer()
                    // The stage box the cords come out of.
                    HStack(spacing: 28) {
                        ForEach(Cord.allCases, id: \.self) { cord in
                            StageBoxPort(cord: cord, live: connections[cord] != nil)
                                .cableSource(for: cord, edge: .top)
                        }
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 26)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(white: 0.28), Color(white: 0.12)],
                                startPoint: .top,
                                endPoint: .bottom,
                            ))
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                    )
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, canEject: !connections.isEmpty) { connections = [:] }
        }
    }

    // MARK: Private

    @State private var connections: [Cord: Port] = [.orange: .a1]
    @State private var showSettings = false
    @State private var lastEvent = ""

    private var cables: [PlugCable<Cord>] {
        Cord.allCases.map { cord in
            var c = config
            c.cable.color = cord.color
            c.plugStyle = cord.plug
            return PlugCable(id: cord, configuration: c)
        }
    }

    private var sockets: [PlugSocket<Port>] {
        Port.allCases.map { port in
            PlugSocket(
                id: port,
                title: port.title,
                systemImage: port.isUSB ? "cable.connector" : "waveform",
                tint: port.isUSB ? Cord.green.color : .white,
                entryAngle: .degrees(-90), // cords come up from the box below
                accepts: port.isUSB ? [.usbC] : [.audioJack],
            )
        }
    }

    private var config: CableConfiguration {
        var c = settings.configuration()
        c.cable = CableStyle(color: c.cable.color)
        c.plugStyle = .audioJack
        c.hangFraction = 0.35
        c.dataFlow = .none
        return c
    }

    private var summary: String {
        let live = Cord.allCases.compactMap { cord in connections[cord].map { "\(cord.rawValue) → \($0.title)" } }
        return live.isEmpty ? "Nothing patched" : live.joined(separator: "  ·  ")
    }

    private func socketCell(_ port: Port) -> some View {
        VStack(spacing: 4) {
            CableSocketPortView(
                id: port,
                tint: port.isUSB ? Cord.green.color : .white,
                accessibilityLabel: Text(verbatim: port.title),
            )
            Text(port.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
    }

    private func log(_ cord: Cord, _ event: CableEvent<Port>) {
        switch event {
        case .plugged(let p): lastEvent = "\(cord.rawValue) plugged \(p.title)"
        case .unplugged(let p): lastEvent = "\(cord.rawValue) unplugged \(p.title)"
        default: break
        }
    }

}

// MARK: - StageBoxPort

/// One output on the stage box: a labelled jack with an LED that lights when its cord is patched.
private struct StageBoxPort: View {
    let cord: BayView.Cord
    let live: Bool

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(live ? cord.color : Color(white: 0.2))
                .frame(width: 6, height: 6)
                .shadow(color: live ? cord.color : .clear, radius: 4)
            Text(cord.rawValue.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }
}
