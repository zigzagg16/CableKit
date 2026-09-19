import CableKit
import SwiftUI

// MARK: - ConnectView

/// The "Orders" service is a 1U unit on the left; drag its uplink into one of the machines racked
/// on the right. Rows are custom (hostname, address, live throughput), the ports and cable come from CableKit.
struct ConnectView: View {

    // MARK: Internal

    let settings: DemoSettings

    var body: some View {
        ZStack {
            RackRoomBackground()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patch the uplink")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                        LinkStatus(host: current)
                    }
                    Spacer()
                    SettingsButton(isPresented: $showSettings)
                }
                .padding(.horizontal, 24)

                CableBoard(sockets: sockets, connection: $connection, configuration: config, onEvent: handle) {
                    HStack(alignment: .top, spacing: 0) {
                        ServiceUnit(
                            name: "ORDERS",
                            host: "orders-01",
                            linked: current != nil,
                            tint: current?.tint ?? settings.cableColor,
                        )
                        .cableSource(edge: .trailing)
                        .padding(.leading, 20)

                        Spacer(minLength: 16)

                        Rack {
                            ForEach(hosts) { HostRow(host: $0) }
                        }
                        .padding(.trailing, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .containerRelativeFrame(.vertical) { height, _ in height * 0.68 }
                .overlay(alignment: .bottomTrailing) {
                    Text(lastEvent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 24)
                        .allowsHitTesting(false)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, canEject: connection != nil, eject: { connection = nil })
                .presentationDetents([.fraction(0.3), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: Private

    @State private var connection: DataSource? = nil
    @State private var lastEvent = "link down"
    @State private var showSettings = false
    @Environment(\.colorScheme) private var scheme

    private let hosts: [Host] = [
        Host(id: .postgres, name: "db-prod-01", detail: "10.0.4.12 · pg16", unit: "U4", icon: "cylinder.split.1x2", tint: .cyan),
        Host(
            id: .s3,
            name: "obj-store-eu",
            detail: "eu-west-1 · s3",
            unit: "U3",
            icon: "externaldrive.connected.to.line.below",
            tint: .orange,
        ),
        Host(id: .api, name: "edge-gw-03", detail: "api.example.com", unit: "U2", icon: "network", tint: .green),
        Host(id: .csv, name: "cold-archive", detail: "offline", unit: "U1", icon: "archivebox", tint: .purple, isEnabled: false),
    ]

    private var sockets: [PlugSocket<DataSource>] {
        hosts.map { PlugSocket(
            id: $0.id,
            title: $0.name,
            subtitle: $0.detail,
            systemImage: $0.icon,
            tint: $0.tint,
            isEnabled: $0.isEnabled,
        ) }
    }

    private var current: Host? {
        hosts.first { $0.id == connection }
    }

    private var config: CableConfiguration {
        var c = settings.configuration()
        c.theme = settings.customTheme ? settings.studioTheme : rackTheme // custom theme from settings wins
        return c
    }

    /// Rack hardware is dark whatever the room lighting: only the socket metal follows the scheme.
    private var rackTheme: CableTheme {
        var t = CableTheme.dark
        t.socketBezel = [Color(white: 0.55), Color(white: 0.22)]
        t.socketHole = [Color(white: 0.02), Color(white: 0.12)]
        t.ledOff = Color(white: 0.22)
        return t
    }

    private func name(_ id: DataSource) -> String {
        hosts.first { $0.id == id }?.name ?? ""
    }

    private func handle(_ event: CableEvent<DataSource>) {
        switch event {
        case .grabbed: lastEvent = "uplink unseated"
        case .hover(let id): lastEvent = id.map { "negotiating \(name($0))" } ?? "no carrier"
        case .plugged(let id): lastEvent = "link up → \(name(id))"
        case .unplugged(let id): lastEvent = "link down ← \(name(id))"
        case .dropped: lastEvent = "no carrier"
        case .stretched(let t): lastEvent = String(format: "strain %.0f%%", t * 100)
        }
    }

}

// MARK: - Host

struct Host: Identifiable {
    let id: DataSource
    let name: String
    let detail: String
    let unit: String
    let icon: String
    let tint: Color
    var isEnabled = true
}

// MARK: - LinkStatus

/// "Not linked" or "orders → host · 10 GbE · 3.2 Gb/s" with a throughput figure that wanders while linked.
private struct LinkStatus: View {
    let host: Host?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                if let host {
                    Circle().fill(host.tint).frame(width: 7, height: 7)
                        .shadow(color: host.tint.opacity(0.8), radius: 4)
                    Text("orders → \(host.name)")
                    Text("·").foregroundStyle(.tertiary)
                    Text(String(format: "%.1f Gb/s", 2.4 + sin(t * 1.3) * 0.6 + sin(t * 3.7) * 0.3))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Circle().fill(Color(white: 0.5, opacity: 0.5)).frame(width: 7, height: 7)
                    Text("Not linked")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .animation(.easeOut(duration: 0.4), value: t)
        }
    }
}

// MARK: - ServiceUnit

/// A 1U server: label, vent grille, status LEDs and the uplink port on its trailing edge.
private struct ServiceUnit: View {
    let name: String
    let host: String
    let linked: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(host)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            VentGrille(rows: 5)
                .frame(height: 30)

            HStack(spacing: 6) {
                StatusLED(label: "PWR", color: .green, on: true)
                StatusLED(label: "LNK", color: tint, on: linked)
                ActivityLED(label: "ACT", color: tint, active: linked)
            }

            Spacer(minLength: 0)

            // Uplink port cage, flush with the trailing edge where the cable leaves
            HStack(spacing: 6) {
                Text("UPLINK")
                    .font(.system(size: 8, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(
                        .white.opacity(0.2),
                        lineWidth: 1,
                    ))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1).fill(.black.opacity(0.7)).frame(width: 20, height: 5).padding(
                            .bottom,
                            3,
                        )
                    }
                    .padding(.trailing, -12)
            }
        }
        .padding(10)
        .frame(width: 92, height: 168)
        .background(Chassis(cornerRadius: 12))
        .overlay(alignment: .leading) { RackEar().padding(.leading, -6) }
        .overlay(alignment: .trailing) { RackEar().padding(.trailing, -6) }
        .accessibilityLabel("\(name) service, \(linked ? "linked" : "not linked")")
    }
}

// MARK: - Rack

/// Two rails with mounting holes, machines racked between them.
private struct Rack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Rail()
            VStack(spacing: 8) { content }
            Rail()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Rail

private struct Rail: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2),
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.34), Color(white: 0.2)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0),
                ),
            )
            var y: CGFloat = 8
            while y < size.height - 4 {
                let hole = Path(roundedRect: CGRect(x: size.width / 2 - 2.5, y: y, width: 5, height: 5), cornerRadius: 1)
                ctx.fill(hole, with: .color(.black.opacity(0.8)))
                ctx.stroke(hole, with: .color(.white.opacity(0.15)), lineWidth: 0.5)
                y += 12
            }
        }
        .frame(width: 11)
    }
}

// MARK: - HostRow

/// One racked machine: port, hostname, address, live throughput and a status LED.
private struct HostRow: View {

    // MARK: Internal

    let host: Host

    var body: some View {
        let state = states[host.id]
        HStack(spacing: 8) {
            CableSocketPortView(id: host.id, tint: host.tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: host.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(host.tint)
                    Text(host.name)
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(host.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    Text(host.unit)
                        .font(.system(size: 8, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                    Circle()
                        .fill(state.isConnected ? host.tint : Color(white: 0.22))
                        .frame(width: 7, height: 7)
                        .shadow(color: state.isConnected ? host.tint.opacity(0.9) : .clear, radius: 5)
                        .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.5))
                }
                Throughput(active: state.isSeated, color: host.tint)
            }
            .fixedSize()
        }
        .padding(.vertical, 9)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .background(Chassis(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    state.isConnected ? host.tint.opacity(0.9) : (state.isHovered ? host.tint.opacity(0.6) : .clear),
                    lineWidth: 1.5,
                )
                .shadow(color: state.isConnected ? host.tint.opacity(0.5) : .clear, radius: 8)
        )
        .scaleEffect(1 + states.pulse(host.id) * 0.03)
        .opacity(host.isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { toggle(AnyHashable(host.id)) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(host.name)
        .accessibilityValue(state.isConnected ? "Linked" : "Not linked")
        .accessibilityHint(state.isConnected ? "Double tap to unlink" : "Double tap to link")
        .animation(.spring(duration: 0.25), value: state.isHovered)
        .animation(.spring(duration: 0.3), value: state.isConnected)
    }

    // MARK: Private

    @Environment(\.cableSocketStates) private var states
    @Environment(\.cableToggleSocket) private var toggle

}

// MARK: - Chassis

/// Brushed dark front panel with a top highlight and a drop shadow.
private struct Chassis: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(white: 0.2), Color(white: 0.13), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom,
            ))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1,
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
    }
}

// MARK: - RackEar

/// Mounting flange either side of the service unit.
private struct RackEar: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 150)
            .overlay {
                VStack(spacing: 44) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(.black.opacity(0.8)).frame(width: 3.5, height: 3.5)
                    }
                }
            }
    }
}

// MARK: - VentGrille

/// Rows of vent slots.
private struct VentGrille: View {
    let rows: Int

    var body: some View {
        Canvas { ctx, size in
            let pitch = size.height / CGFloat(rows)
            for r in 0..<rows {
                let y = pitch * CGFloat(r) + pitch * 0.25
                var x: CGFloat = 0
                while x < size.width - 2 {
                    let slot = Path(roundedRect: CGRect(x: x, y: y, width: 6, height: pitch * 0.5), cornerRadius: 1)
                    ctx.fill(slot, with: .color(.black.opacity(0.7)))
                    x += 9
                }
            }
        }
    }
}

// MARK: - StatusLED

private struct StatusLED: View {
    let label: String
    let color: Color
    let on: Bool

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(on ? color : Color(white: 0.22))
                .frame(width: 6, height: 6)
                .shadow(color: on ? color.opacity(0.9) : .clear, radius: 4)
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .animation(.easeOut(duration: 0.2), value: on)
    }
}

// MARK: - ActivityLED

/// Flickers like a NIC activity light while there's traffic.
private struct ActivityLED: View {
    let label: String
    let color: Color
    let active: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.09)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let on = active && Self.noise(t) > 0.35
            StatusLED(label: label, color: color, on: on)
        }
    }

    /// Cheap deterministic flicker.
    static func noise(_ t: TimeInterval) -> Double {
        let x = sin(t * 91.7) * 43758.5453
        return x - floor(x)
    }
}

// MARK: - Throughput

/// Five bars that dance with traffic while a link is up, flat otherwise.
private struct Throughput: View {
    let active: Bool
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let h = active ? 3 + 11 * ActivityLED.noise(t + Double(i) * 0.37) : 2
                    RoundedRectangle(cornerRadius: 1)
                        .fill(active ? color : Color(white: 0.3))
                        .frame(width: 3, height: h)
                }
            }
            .frame(height: 14, alignment: .bottom)
            .animation(.easeOut(duration: 0.12), value: t)
        }
        .opacity(active ? 1 : 0.6)
    }
}

// MARK: - RackRoomBackground

/// Server-room floor: cool gradient with a faint grid, dark or light.
private struct RackRoomBackground: View {

    // MARK: Internal

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.09, blue: 0.13), Color(red: 0.02, green: 0.02, blue: 0.04)]
                    : [Color(red: 0.93, green: 0.94, blue: 0.97), Color(red: 0.82, green: 0.84, blue: 0.89)],
                startPoint: .top,
                endPoint: .bottom,
            )
            Canvas { ctx, size in
                let line = Color.primary.opacity(scheme == .dark ? 0.05 : 0.06)
                var x: CGFloat = 0
                while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(line))
                    x += 24
                }
                var y: CGFloat = 0
                while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(line))
                    y += 24
                }
            }
            RadialGradient(
                colors: [.clear, .black.opacity(scheme == .dark ? 0.5 : 0.08)],
                center: .center,
                startRadius: 200,
                endRadius: 600,
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Private

    @Environment(\.colorScheme) private var scheme

}
