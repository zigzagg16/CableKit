import CableKit
import SwiftUI

// MARK: - DataSource

enum DataSource: String, CaseIterable, Hashable {
    case postgres
    case s3
    case api
    case csv
}

// MARK: - CableDemoApp

@main
struct CableDemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

// MARK: - RootView

struct RootView: View {

    // MARK: Internal

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectView(settings: settings)
                .tabItem { Label("Connect", systemImage: "cable.connector") }
                .tag(0)
            ArcadeView(settings: settings)
                .tabItem { Label("Arcade", systemImage: "gamecontroller.fill") }
                .tag(1)
            StudioView(settings: settings)
                .tabItem { Label("Studio", systemImage: "pianokeys") }
                .tag(2)
            BayView(settings: settings)
                .tabItem { Label("Bay", systemImage: "rectangle.connected.to.line.below") }
                .tag(3)
        }
        .preferredColorScheme(settings.appearance.scheme)
    }

    // MARK: Private

    @AppStorage("selectedTab") private var selectedTab = 0

    private let settings = DemoSettings()

}

// MARK: - SettingsButton

/// The settings button used at the top of every tab.
struct SettingsButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .padding(8)
        }
        .buttonStyle(.bordered)
        .clipShape(Circle())
        .accessibilityLabel("Settings")
    }
}

// MARK: - Appearance

enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var scheme: ColorScheme? {
        self == .system ? nil : (self == .dark ? .dark : .light)
    }
}

// MARK: - Flow

enum Flow: String, CaseIterable, Identifiable {
    case off
    case bits
    case morse

    var id: String {
        rawValue
    }

    var style: DataFlowStyle {
        switch self {
        case .off: .none
        case .bits: .bits
        case .morse: .morse("HELLO WORLD")
        }
    }
}

// MARK: - DemoSettings

/// All demo settings, stored in UserDefaults via @AppStorage.
struct DemoSettings: DynamicProperty {
    @AppStorage("plugStyle") var plugStyleID: String = PlugStyle.audioJack.id

    @AppStorage("cableColor") var cableColorHex = "#FA732E"
    @AppStorage("cord") var cord = Cord.round
    @AppStorage("sound") var sound = true
    @AppStorage("appearance") var appearance = Appearance.system
    @AppStorage("customTheme") var customTheme = false
    @AppStorage("dataFlow") var flow = Flow.bits
    @AppStorage("motionGravity") var motionGravity = true
    @AppStorage("gravity") var gravity: Double = 2600
    @AppStorage("slack") var slack: Double = 36
    @AppStorage("elasticity") var elasticity = 0.5
    @AppStorage("hangFraction") var hangFraction = 0.75
    @AppStorage("sparkTrigger") var spark = SparkTrigger.both
    @AppStorage("grabStretchFeedback") var grabStretchFeedback = true

    var plugStyle: PlugStyle {
        get { PlugStyle.builtIn(id: plugStyleID) ?? .audioJack }
        nonmutating set { plugStyleID = newValue.id }
    }

    var cableColor: Color {
        get { Color(hex: cableColorHex) ?? Color(red: 0.98, green: 0.45, blue: 0.18) }
        nonmutating set { cableColorHex = newValue.hexString }
    }

    /// Example of a user-supplied theme: warm studio look, tinted by the cable colour.
    var studioTheme: CableTheme {
        var t = CableTheme.dark
        let cable = cableColor
        t.cardFill = Color(red: 0.16, green: 0.12, blue: 0.10)
        t.cardBorder = cable.opacity(0.25)
        t.subtitle = Color(red: 0.8, green: 0.7, blue: 0.6)
        t.deviceGradient = [cable.opacity(0.9), cable.opacity(0.5)]
        t.deviceText = .white
        t.socketBezel = [Color(red: 0.85, green: 0.7, blue: 0.4), Color(red: 0.5, green: 0.35, blue: 0.15)]
        return t
    }

    /// The configuration every tab starts from; tabs tweak a copy for their layout.
    func configuration() -> CableConfiguration {
        var c = CableConfiguration()
        c.plugStyle = plugStyle
        c.cable = cord.style(color: cableColor)
        c.soundEnabled = sound
        c.theme = customTheme ? studioTheme : nil
        c.dataFlow = flow.style
        c.gravityFollowsDevice = motionGravity
        c.gravity = gravity
        c.slack = slack
        c.elasticity = elasticity
        c.hangFraction = hangFraction
        c.spark = spark
        c.cableGrabStretchFeedback = grabStretchFeedback
        return c
    }
}

// MARK: - SettingsSheet

struct SettingsSheet: View {

    // MARK: Internal

    let settings: DemoSettings
    var canEject = false
    var eject: () -> Void = { }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plug") {
                    Picker("Style", selection: settings.$plugStyleID) {
                        ForEach(PlugStyle.builtIn) { Text($0.displayName).tag($0.id) }
                    }

                    Picker("Cord", selection: settings.$cord) {
                        ForEach(Cord.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }

                    HStack(spacing: 10) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                            let selected = color.hexString == settings.cableColorHex
                            Circle()
                                .fill(color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.15), lineWidth: 2))
                                .scaleEffect(selected ? 1.15 : 1)
                                .onTapGesture { withAnimation(.spring(duration: 0.25)) { settings.cableColor = color } }
                        }
                        Spacer()
                        ColorPicker(
                            "",
                            selection: Binding(get: { settings.cableColor }, set: { settings.cableColor = $0 }),
                            supportsOpacity: false,
                        )
                        .labelsHidden()
                    }
                }

                Section("Data") {
                    Picker("Traffic", selection: settings.$flow) {
                        Text("Off").tag(Flow.off)
                        Text("Bits").tag(Flow.bits)
                        Text("Morse").tag(Flow.morse)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Physics") {
                    Toggle(isOn: settings.$motionGravity) { Label("Gravity follows tilt", systemImage: "gyroscope") }
                    LabeledContent("Gravity") {
                        Slider(value: settings.$gravity, in: 800...5000, step: 100)
                    }
                    LabeledContent("Slack") {
                        Slider(value: settings.$slack, in: 10...120, step: 2)
                    }
                    LabeledContent("Elasticity") {
                        Slider(value: settings.$elasticity, in: 0...1, step: 0.05)
                    }
                    LabeledContent("Hang length") {
                        Slider(value: settings.$hangFraction, in: 0.3...1, step: 0.05)
                    }
                }

                Section("Feedback & look") {
                    Toggle(isOn: settings.$sound) { Label("Sound", systemImage: "speaker.wave.2") }
                    Toggle(isOn: settings.$grabStretchFeedback) { Label("Creak when stretching cable", systemImage: "waveform") }
                    Picker(selection: settings.$spark) {
                        Text("None").tag(SparkTrigger.none)
                        Text("In").tag(SparkTrigger.plugIn)
                        Text("Out").tag(SparkTrigger.unplug)
                        Text("In & out").tag(SparkTrigger.both)
                    } label: { Label("Sparks", systemImage: "bolt.fill") }
                    Toggle(isOn: settings.$customTheme) { Label("Custom theme (studio)", systemImage: "paintpalette") }
                    Picker("Appearance", selection: settings.$appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Eject plug") { eject() }
                        .disabled(!canEject)
                    Button("Reset settings", role: .destructive) {
                        for key in [
                            "plugStyle",
                            "cord",
                            "cableColor",
                            "sound",
                            "appearance",
                            "customTheme",
                            "dataFlow",
                            "motionGravity",
                            "gravity",
                            "slack",
                            "elasticity",
                            "hangFraction",
                            "sparkTrigger",
                            "grabStretchFeedback",
                        ] {
                            UserDefaults.standard.removeObject(forKey: key)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let swatches: [Color] = [
        Color(hex: "#FA732E")!,
        Color(hex: "#F23340")!,
        Color(hex: "#338CFF")!,
        Color(hex: "#40CC73")!,
        Color(hex: "#F2D933")!,
        Color(hex: "#B373FF")!,
        Color(hex: "#EBEBEB")!,
        Color(hex: "#333333")!,
    ]

}

// MARK: - Color <-> hex

extension Color {

    // MARK: Lifecycle

    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") {
            h.removeFirst()
        }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    // MARK: Internal

    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

}

// MARK: - Cord

/// The cable presets the demo can switch between.
enum Cord: String, CaseIterable {
    case round
    case coiled
    case ribbon
    case neon

    func style(color: Color) -> CableStyle {
        switch self {
        case .round: CableStyle(color: color)
        case .coiled: .coiled(color: color)
        case .ribbon: .ribbon(color: color)
        case .neon: .neon(color: color)
        }
    }
}
