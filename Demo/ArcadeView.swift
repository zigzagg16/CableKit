import CableKit
import SwiftUI

// MARK: - ArcadeBubble

struct ArcadeBubble: Identifiable, Hashable {
    static let all: [ArcadeBubble] = [
        .init(
            id: "zongo",
            name: "zongo",
            tagline: "Draw one path through every cell. Just one.",
            systemImage: "scribble.variable",
            color: Color(red: 0.35, green: 0.85, blue: 0.6),
            url: URL(string: "https://zongo.papitooo.com/"),
        ),
        .init(
            id: "mystery1",
            name: "???",
            tagline: "Something small is brewing…",
            systemImage: "sparkles",
            color: Color(red: 0.75, green: 0.55, blue: 1.0),
            url: nil,
        ),
        .init(
            id: "dozzzo",
            name: "dozzzo",
            tagline: "One family profile. Every app.",
            systemImage: "person.2.fill",
            color: Color(red: 1.0, green: 0.7, blue: 0.3),
            url: URL(string: "https://dozo.papitooo.com/"),
        ),
        .init(
            id: "mystery2",
            name: "???",
            tagline: "Not ready yet. Plug in later.",
            systemImage: "moon.zzz.fill",
            color: Color(red: 0.4, green: 0.7, blue: 1.0),
            url: nil,
        ),
        .init(
            id: "papitooo",
            name: "papitooo",
            tagline: "Little things that do you good.",
            systemImage: "heart.fill",
            color: Color(red: 1.0, green: 0.45, blue: 0.55),
            url: URL(string: "https://papitooo.com/"),
        ),
        .init(
            id: "mystery3",
            name: "???",
            tagline: "A tiny idea, charging…",
            systemImage: "bolt.heart.fill",
            color: Color(red: 0.95, green: 0.9, blue: 0.4),
            url: nil,
        ),
    ]

    let id: String
    let name: String
    let tagline: String
    let systemImage: String
    let color: Color
    let url: URL?

    var isMystery: Bool {
        url == nil
    }
}

// MARK: - ArcadeView

struct ArcadeView: View {

    // MARK: Internal

    let settings: DemoSettings

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                GeometryReader { geo in
                    let radius = min(geo.size.width, geo.size.height) * 0.33
                    CableBoard(sockets: sockets, connection: $connection, configuration: config, onEvent: handle) {
                        ZStack {
                            Hub(lit: lit.count, total: bubbles.count)
                                .cableSource(edge: .center)

                            ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                                let a = angle(of: index)
                                Bubble(bubble: bubble, discovered: lit.contains(bubble.id), angle: a)
                                    .offset(x: cos(a) * radius, y: sin(a) * radius)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                promoCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if finale {
                Confetti().allowsHitTesting(false).transition(.opacity)
            } // ~4 s of confetti, then fades
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, canEject: connection != nil, eject: { connection = nil })
                .presentationDetents([.fraction(0.3), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: Private

    @State private var connection: String? = nil
    @State private var lit = Set<String>()
    @State private var finale = false
    @State private var lastEvent: CableEvent<String>? = nil
    @State private var showSettings = false
    @Environment(\.colorScheme) private var scheme

    private let bubbles = ArcadeBubble.all

    /// The plug enters each bubble radially, pointing away from the hub.
    private var sockets: [PlugSocket<String>] {
        bubbles.enumerated().map { i, b in
            PlugSocket(
                id: b.id,
                title: b.name,
                subtitle: b.tagline,
                systemImage: b.systemImage,
                tint: b.color,
                entryAngle: .radians(Double(angle(of: i))),
            )
        }
    }

    private var current: ArcadeBubble? {
        bubbles.first { $0.id == connection }
    }

    private var allLit: Bool {
        lit.count == bubbles.count
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(allLit ? "You lit them all ✨" : "Plug the hub into a bubble · \(lit.count)/\(bubbles.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: lit.count)
                .padding(.top, 12)
            Spacer()
            SettingsButton(isPresented: $showSettings)
        }
        .padding(.horizontal, 24)
    }

    private var promoCard: some View {
        ZStack {
            if finale {
                PromoCard(bubble: bubbles.first { $0.id == "papitooo" }!, finale: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let bubble = current, lit.contains(bubble.id) {
                PromoCard(bubble: bubble)
                    .id(bubble.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Color.clear
            }
        }
        .frame(height: 96)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: connection)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: lit)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: finale)
    }

    /// Shared settings, plus what the ring layout needs.
    private var config: CableConfiguration {
        var c = settings.configuration()
        if let current {
            c.cable.color = current.color
            c.sparkColor = current.color
        } // takes the bubble's colour when lit
        c.hangFraction = min(c.hangFraction, 0.45)
        c.snapRadius = 70
        c.dataFlowDirection = .toSocket
        c.theme = settings.customTheme ? settings.studioTheme : arcadeTheme // custom theme from settings wins
        return c
    }

    private var arcadeTheme: CableTheme {
        var t = CableTheme.automatic(for: scheme)
        if scheme == .dark {
            t.socketBezel = [Color.white.opacity(0.55), Color.white.opacity(0.15)]
            t.socketHole = [Color(white: 0.02), Color(white: 0.15)]
            t.shadowOpacity = 0.5
        }
        return t
    }

    /// Angle of each bubble around the hub (clockwise from the upper right, leaving top and bottom clear).
    private func angle(of index: Int) -> CGFloat {
        -CGFloat.pi / 3 + CGFloat(index) / CGFloat(bubbles.count) * 2 * .pi
    }

    private func handle(_ event: CableEvent<String>) {
        lastEvent = event
        if case .plugged(let id) = event {
            let wasAll = allLit
            lit.insert(id)
            if !wasAll, allLit {
                withAnimation { finale = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) { withAnimation { finale = false } }
            }
        }
    }

}

// MARK: - Hub

private struct Hub: View {
    let lit: Int
    let total: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.03 * sin(t * 2)
            let progress = Double(lit) / Double(max(total, 1))
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1, green: 0.5, blue: 0.6).opacity(0.55), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70,
                    ))
                    .frame(width: 140, height: 140)
                    .scaleEffect(breathe)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.25, green: 0.2, blue: 0.35), Color(red: 0.1, green: 0.08, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    ))
                    .frame(width: 84, height: 84)
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .purple, .pink], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 96, height: 96)
                    .animation(.spring(duration: 0.6), value: progress)
                Text("p")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [.white, Color(red: 1, green: 0.75, blue: 0.85)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ))
                    .offset(y: -20)
                // The port the cable comes out of, dead centre
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.02), Color(white: 0.2)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 11,
                    ))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .offset(y: 8)
            }
        }
    }
}

// MARK: - Bubble

private struct Bubble: View {

    // MARK: Internal

    let bubble: ArcadeBubble
    let discovered: Bool
    /// Direction from the hub; the receptacle sits on the hub-facing side, the label on the far side.
    let angle: CGFloat

    var body: some View {
        let state = states[bubble.id]
        let on = state.isSeated
        let ink: Color = scheme == .dark ? .white : Color(white: 0.12)
        ZStack {
            // Fizz when lit
            if on {
                Fizz(color: bubble.color).frame(width: 120, height: 160).offset(y: -50)
            }

            // Glow
            Circle()
                .fill(bubble.color.opacity(on ? 0.6 : (discovered ? 0.25 : 0.08)))
                .frame(width: 110, height: 110)
                .blur(radius: 18)

            // Soap bubble
            Circle()
                .fill(RadialGradient(
                    colors: [bubble.color.opacity(on ? 0.55 : 0.18), bubble.color.opacity(on ? 0.25 : 0.05)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 4,
                    endRadius: 46,
                ))
                .frame(width: 84, height: 84)
                .overlay(Circle().strokeBorder(ink.opacity(on ? 0.7 : 0.3), lineWidth: 1.2))
                .overlay(alignment: .topLeading) {
                    Ellipse().fill(.white.opacity(on ? 0.7 : 0.5)).frame(width: 22, height: 12)
                        .rotationEffect(.degrees(-30)).offset(x: 14, y: 12)
                }
                .scaleEffect(state.isHovered ? 1.08 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.4), value: state.isHovered)

            VStack(spacing: 2) {
                Image(systemName: bubble.systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(on || discovered ? ink : ink.opacity(0.45))
                    .symbolEffect(.bounce, value: on)
                Text(discovered ? bubble.name : (bubble.isMystery ? "?" : bubble.name))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(ink.opacity(on || discovered ? 0.95 : 0.5))
            }
            .offset(x: cos(angle) * 14, y: sin(angle) * 14)

            // The receptacle faces the hub; the plug comes in radially and points outward.
            CableSocketPortView(
                id: bubble.id,
                tint: bubble.color,
                accessibilityLabel: discovered || !bubble.isMystery
                    ? Text(verbatim: bubble.name)
                    : Text("Mystery socket"),
            )
            .offset(x: -cos(angle) * 30, y: -sin(angle) * 30)
        }
        .frame(width: 110, height: 110)
        .animation(.easeOut(duration: 0.25), value: on)
    }

    // MARK: Private

    @Environment(\.cableSocketStates) private var states
    @Environment(\.colorScheme) private var scheme

}

// MARK: - Fizz

private struct Fizz: View {

    // MARK: Internal

    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                for s in seeds {
                    let cycle: Double = t * s.speed + s.phase
                    let life: Double = cycle.truncatingRemainder(dividingBy: 1.6) / 1.6
                    let y: Double = size.height - life * size.height
                    let wobble: Double = sin(t * 3 + s.phase * 7) * 8
                    let x: Double = size.width * (0.2 + 0.6 * s.x) + wobble
                    let alpha: Double = (1 - life) * 0.9
                    let r: Double = s.size * (0.6 + 0.4 * life)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    g.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha * 0.5)))
                    g.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)), lineWidth: 0.8)
                }
            }
        }
    }

    // MARK: Private

    private struct Seed { var x: Double
        var phase: Double
        var size: Double
        var speed: Double
    }

    private let seeds: [Seed] = (0..<14).map { (i: Int) -> Seed in
        let d = Double(i)
        return Seed(x: d / 14, phase: d * 0.61, size: 3 + Double(i % 4) * 1.6, speed: 0.7 + Double(i % 3) * 0.25)
    }

}

// MARK: - PromoCard

private struct PromoCard: View {
    let bubble: ArcadeBubble
    var finale = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(bubble.color.opacity(0.25)).frame(width: 52, height: 52)
                Image(systemName: finale ? "party.popper.fill" : bubble.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(bubble.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(finale ? "All lit! Thanks for playing" : bubble.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(finale ? "More little things at papitooo.com" : bubble.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = bubble.url {
                Link(destination: url) {
                    Text(finale ? "Visit" : "Open")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(bubble.color))
                        .foregroundStyle(.black.opacity(0.85))
                }
            } else {
                Text("soon")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().stroke(Color.primary.opacity(0.3)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                    bubble.color.opacity(0.5),
                    lineWidth: 1,
                ))
        )
    }
}

// MARK: - SpaceBackground

private struct SpaceBackground: View {

    // MARK: Internal

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.07, green: 0.05, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.06)]
                    : [Color(red: 0.93, green: 0.92, blue: 0.99), Color(red: 0.84, green: 0.85, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom,
            )
            TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { g, size in
                    var rng = LCG(seed: 7)
                    for _ in 0..<90 {
                        let x: Double = rng.next() * size.width
                        let y: Double = rng.next() * size.height
                        let base = 0.25 + rng.next() * 0.5
                        let freq = 0.8 + rng.next() * 1.5
                        let phase: Double = rng.next() * 6.28
                        let tw = 0.5 + 0.5 * sin(t * freq + phase)
                        let r = 0.6 + rng.next() * 1.2
                        let star: Color = dark ? .white : Color(red: 0.45, green: 0.4, blue: 0.7)
                        g.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                            with: .color(star.opacity(base * tw * (dark
                                    ? 1
                                    : 0.5))),
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Private

    @Environment(\.colorScheme) private var scheme

}

// MARK: - Confetti

private struct Confetti: View {

    // MARK: Internal

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                var rng = LCG(seed: 42)
                for _ in 0..<120 {
                    let x0: Double = rng.next() * size.width
                    let vy: Double = 120 + rng.next() * 220
                    let vx: Double = (rng.next() - 0.5) * 120
                    let hue: Double = rng.next()
                    let w: Double = 6 + rng.next() * 6
                    let spin: Double = rng.next() * 10
                    let y: Double = -20 + vy * t + 60 * t * t
                    let sway: Double = sin(t * 3 + spin) * 12
                    let x: Double = x0 + vx * t + sway
                    guard y < size.height + 20 else { continue }
                    var c = g
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * spin))
                    c.fill(
                        Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)),
                        with: .color(Color(hue: hue, saturation: 0.8, brightness: 1).opacity(max(0, 1 - t / 4))),
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Private

    private let start = Date()

}

// MARK: - LCG

/// Deterministic little RNG for the decorative canvases.
private struct LCG {
    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
