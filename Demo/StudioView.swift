import AVFoundation
import CableKit
import os
import SwiftUI

// MARK: - StudioNote

struct StudioNote: Identifiable, Hashable {
    static let scale: [StudioNote] = [
        .init(id: "C4", name: "C", frequency: 261.63, color: Color(red: 1.0, green: 0.45, blue: 0.45)),
        .init(id: "D4", name: "D", frequency: 293.66, color: Color(red: 1.0, green: 0.65, blue: 0.35)),
        .init(id: "E4", name: "E", frequency: 329.63, color: Color(red: 0.95, green: 0.85, blue: 0.35)),
        .init(id: "F4", name: "F", frequency: 349.23, color: Color(red: 0.45, green: 0.85, blue: 0.5)),
        .init(id: "G4", name: "G", frequency: 392.00, color: Color(red: 0.35, green: 0.8, blue: 0.9)),
        .init(id: "A4", name: "A", frequency: 440.00, color: Color(red: 0.45, green: 0.6, blue: 1.0)),
        .init(id: "B4", name: "B", frequency: 493.88, color: Color(red: 0.7, green: 0.5, blue: 1.0)),
        .init(id: "C5", name: "C", frequency: 523.25, color: Color(red: 1.0, green: 0.5, blue: 0.8)),
    ]

    let id: String
    let name: String
    let frequency: Double
    let color: Color
}

// MARK: - StudioView

struct StudioView: View {

    // MARK: Internal

    enum Waveform: String, CaseIterable, Identifiable {
        case sine
        case saw
        case square

        var id: String {
            rawValue
        }
    }

    let settings: DemoSettings

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.12, green: 0.11, blue: 0.10), Color(red: 0.05, green: 0.05, blue: 0.05)]
                    : [Color(red: 0.96, green: 0.94, blue: 0.9), Color(red: 0.88, green: 0.85, blue: 0.8)],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patch a note")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                        Text(current.map { "\($0.name) · \(Int($0.frequency)) Hz" } ?? "Plug the oscillator into a key")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: connection)
                    }
                    Spacer()
                    SettingsButton(isPresented: $showSettings)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Picker("Waveform", selection: $waveform) {
                    ForEach(Waveform.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                CableBoard(sockets: sockets, connection: $connection, configuration: config, onEvent: handle) {
                    VStack(spacing: 18) {
                        OscillatorModule(
                            playing: current != nil,
                            color: current?.color ?? settings.cableColor,
                            frequency: current?.frequency ?? 0,
                            waveform: waveform,
                            synth: synth,
                        )
                        .cableSource(edge: .bottom)
                        .padding(.horizontal, 24)

                        // Keyboard: two columns so every socket has room for the plug body on its left
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { column in
                                VStack(spacing: 10) {
                                    ForEach(notes[(column * 4)..<(column * 4 + 4)]) { note in
                                        Key(note: note, mirrored: column == 1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: waveform) { _, new in synth.waveform = new }
        .onDisappear { synth.stop() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, canEject: connection != nil, eject: { connection = nil })
                .presentationDetents([.fraction(0.3), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: Private

    @State private var connection: String? = nil
    @State private var showSettings = false
    @State private var waveform = Waveform.saw
    @State private var synth = ToneSynth()
    @Environment(\.colorScheme) private var scheme

    private let notes = StudioNote.scale

    /// Left column jacks are entered from the left, right column from the right — like a patch bay.
    private var sockets: [PlugSocket<String>] {
        notes.enumerated().map { i, n in
            PlugSocket(
                id: n.id,
                title: n.name,
                systemImage: "music.note",
                tint: n.color,
                entryAngle: i < 4 ? .zero : .degrees(180),
            )
        }
    }

    private var current: StudioNote? {
        notes.first { $0.id == connection }
    }

    private var config: CableConfiguration {
        var c = settings.configuration()
        if let current {
            c.cable.color = current.color
            c.sparkColor = current.color
        }
        c.hangFraction = min(c.hangFraction, 0.6)
        c.dataFlow = .bits
        c.dataFlowDirection = .toSocket
        c.dataFlowSpeed = 60 + (current?.frequency ?? 0) * 0.4
        c.theme = settings.customTheme ? settings.studioTheme : studioTheme // custom theme from settings wins
        return c
    }

    private var studioTheme: CableTheme {
        var t = CableTheme.automatic(for: scheme)
        t.socketBezel = scheme == .dark ? [Color(white: 0.75), Color(white: 0.3)] : [Color(white: 0.9), Color(white: 0.55)]
        return t
    }

    private func handle(_ event: CableEvent<String>) {
        switch event {
        case .plugged(let id):
            if let note = notes.first(where: { $0.id == id }), settings.sound {
                synth.play(frequency: note.frequency)
            }

        case .unplugged,
             .dropped:
            synth.release()

        default: break
        }
    }

}

// MARK: - OscillatorModule

private struct OscillatorModule: View {
    let playing: Bool
    let color: Color
    let frequency: Double
    let waveform: StudioView.Waveform
    let synth: ToneSynth

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("OSC 1", systemImage: "waveform.path")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Circle().fill(playing ? color : Color(white: 0.3)).frame(width: 8, height: 8)
                    .shadow(color: playing ? color : .clear, radius: 6)
            }
            // Live scope
            TimelineView(.animation(paused: !playing)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { g, size in
                    var path = Path()
                    let cycles = max(1.5, frequency / 110)
                    for i in 0...Int(size.width) {
                        let x = Double(i)
                        let phase = (x / size.width) * cycles * 2 * .pi + t * 6
                        let y = size.height / 2 - ToneSynth.sample(waveform, phase: phase) * size.height * 0.36 * (playing
                            ? synth.level
                            : 0.15)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    g.stroke(
                        path,
                        with: .color(color.opacity(playing ? 1 : 0.35)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round),
                    )
                    g.drawLayer { layer in
                        layer.addFilter(.blur(radius: 6))
                        layer.stroke(path, with: .color(color.opacity(playing ? 0.6 : 0)), lineWidth: 5)
                    }
                }
            }
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)))

            // Output jack (the cable comes out of the bottom edge of the module)
            HStack {
                Text("OUT").font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.22, green: 0.2, blue: 0.18), Color(red: 0.13, green: 0.12, blue: 0.11)],
                    startPoint: .top,
                    endPoint: .bottom,
                ))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: - Key

private struct Key: View {

    // MARK: Internal

    let note: StudioNote
    /// Jack on the right edge, plug comes in from the right.
    var mirrored = false

    var body: some View {
        let state = states[note.id]
        let label = VStack(alignment: mirrored ? .trailing : .leading, spacing: 0) {
            Text(note.name)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(state.isSeated ? note.color : Color.primary.opacity(0.75))
            Text(note.id)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        HStack(spacing: 8) {
            if mirrored {
                Spacer(minLength: 0)
                label
                CableSocketPortView(id: note.id, tint: note.color, accessibilityLabel: Text(verbatim: note.name))
            } else {
                CableSocketPortView(id: note.id, tint: note.color, accessibilityLabel: Text(verbatim: note.name))
                label
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6)
        .padding(mirrored ? .trailing : .leading, 62) // room for the plug body
        .padding(mirrored ? .leading : .trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state.isSeated ? note.color.opacity(0.18) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    state.isSeated
                        ? note.color.opacity(0.8)
                        : (state.isHovered ? note.color.opacity(0.5) : Color.primary.opacity(0.1)),
                    lineWidth: 1,
                )
        )
        .scaleEffect(1 + states.pulse(note.id) * 0.03)
        .contentShape(Rectangle())
        .onTapGesture { toggle(AnyHashable(note.id)) }
        .animation(.easeOut(duration: 0.2), value: state.isSeated)
        .animation(.easeOut(duration: 0.2), value: state.isHovered)
    }

    // MARK: Private

    @Environment(\.cableSocketStates) private var states
    @Environment(\.cableToggleSocket) private var toggle

}

// MARK: - ToneSynth

/// A little monophonic synth: one AVAudioSourceNode, a waveform, and an attack/release envelope.
///
/// Two rules keep it well-behaved:
/// - The audio session and engine are started on a background queue (AVAudioSession logs a hang-risk
///   fault when activated on the main thread), once, and kept running until the view goes away.
/// - The render callback never touches `@Observable` state: it reads its parameters through a lock once
///   per buffer and keeps its own oscillator state, so the real-time thread never takes SwiftUI's locks.
@Observable
@MainActor
final class ToneSynth {

    // MARK: Internal

    /// 0…1 envelope, for the scope. Sampled from the audio thread 30× a second.
    private(set) var level: Double = 0

    var waveform = StudioView.Waveform.saw {
        didSet {
            let waveform = waveform
            params.withLock { $0.waveform = waveform }
        }
    }

    nonisolated static func sample(_ waveform: StudioView.Waveform, phase: Double) -> Double {
        let p = phase.truncatingRemainder(dividingBy: 2 * .pi)
        switch waveform {
        case .sine: return sin(p)
        case .saw: return (p / .pi) - 1
        case .square: return p < .pi ? 0.8 : -0.8
        }
    }

    func play(frequency: Double) {
        params.withLock {
            $0.frequency = frequency
            $0.targetLevel = 1
        }
        start()
    }

    func release() {
        params.withLock { $0.targetLevel = 0 }
    }

    /// Silences and tears the engine down; the view calls this when it disappears.
    func stop() {
        params.withLock {
            $0.targetLevel = 0
            $0.envelope = 0
        }
        level = 0
        meter?.invalidate()
        meter = nil
        engine.stop()
        engineState = .stopped
    }

    // MARK: Private

    /// What the audio thread reads (and the envelope it writes back), behind one lock taken once per buffer.
    private struct Params: Sendable {
        var waveform = StudioView.Waveform.saw
        var frequency = 440.0
        var targetLevel = 0.0
        var envelope = 0.0
    }

    private enum EngineState {
        case stopped
        case starting
        case running
    }

    /// Oscillator state owned by the audio thread alone.
    private final class Voice: @unchecked Sendable {
        var phase = 0.0
    }

    private let engine = AVAudioEngine()
    private let params = OSAllocatedUnfairLock(initialState: Params())
    private var node: AVAudioSourceNode?
    private var engineState = EngineState.stopped
    private var meter: Timer?

    private func start() {
        guard engineState == .stopped else { return }
        engineState = .starting
        if node == nil {
            node = makeSourceNode()
        }
        let engine = UncheckedSendable(engine)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            engine.value.prepare()
            let started = (try? engine.value.start()) != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                engineState = started ? .running : .stopped
                if started {
                    startMeter()
                }
            }
        }
    }

    private func makeSourceNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let sr = format.sampleRate
        let params = params
        let voice = Voice()
        // `@Sendable` keeps the block out of the main actor: it is formed here, on the main actor, but Core
        // Audio calls it on the render thread, and an isolated closure would trap on that call in Swift 6.
        let src = AVAudioSourceNode { @Sendable _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let attack = 1.0 / (0.02 * sr)
            let decay = 1.0 / (0.25 * sr)
            var p = params.withLock { $0 }
            for frame in 0..<Int(frameCount) {
                // Envelope
                if p.targetLevel > p.envelope {
                    p.envelope = min(1, p.envelope + attack)
                } else {
                    p.envelope = max(0, p.envelope - decay)
                }
                // Oscillator with a couple of harmonics rolled off for warmth
                let v = ToneSynth.sample(p.waveform, phase: voice.phase) * 0.7 + sin(voice.phase * 2) * 0.12
                voice.phase += 2 * .pi * p.frequency / sr
                if voice.phase > 2 * .pi {
                    voice.phase -= 2 * .pi
                }
                let sample = Float(v * p.envelope * 0.35)
                for buffer in ablPointer {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            let envelope = p.envelope
            params.withLock { $0.envelope = envelope }
            return noErr
        }
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: format)
        return src
    }

    private func startMeter() {
        meter?.invalidate()
        meter = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                level = params.withLock { $0.envelope }
            }
        }
    }

}

// MARK: - UncheckedSendable

/// Carries a non-`Sendable` framework object across a queue hop; `AVAudioEngine`'s start API is thread-safe.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    init(_ value: Value) {
        self.value = value
    }

    let value: Value
}
