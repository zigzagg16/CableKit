import SwiftUI

// MARK: - SocketRowState

/// State of one socket row, for custom row content.
public struct SocketRowState: Equatable {
    /// All flags default to idle; mainly useful for previews and tests of custom row content.
    public init(isHovered: Bool = false, isConnected: Bool = false, isSeated: Bool = false, cableID: AnyHashable? = nil) {
        self.isHovered = isHovered
        self.isConnected = isConnected
        self.isSeated = isSeated
        self.cableID = cableID
    }

    /// The plug is hovering within snap range.
    public var isHovered: Bool
    /// The plug is connected (snapping, inserting or seated).
    public var isConnected: Bool
    /// The pin is fully seated.
    public var isSeated: Bool
    /// On a multi-cable board, the cable that is connected to (or hovering over) this socket.
    public var cableID: AnyHashable?
}

// MARK: - CablePatchView

/// A patch-bay style connector: a physical cable hangs from a source port on the left,
/// and can be dragged into any of the sockets on the right.
///
/// ```swift
/// CablePatchView(sockets: sockets, connection: $selected, sourceTitle: "Orders", sourceSystemImage: "cart")
/// ```
///
/// - `connection` is a two-way binding: set it to `nil` to eject, or to a socket id to animate the plug in.
/// - Tapping a socket, or a seated plug, connects / disconnects (this is also the VoiceOver path).
/// - Pass a ``CableConfiguration`` to change the look, physics, feedback and data animation; changes apply live.
/// - Pass `source:` for a custom device the cable comes out of, and `socketContent:` for custom row content.
/// - For any other arrangement (sockets in a ring, a grid, …) use ``CableBoard`` directly.
public struct CablePatchView<ID: Hashable, Source: View, RowContent: View>: View {

    // MARK: Lifecycle

    /// - Parameters:
    ///   - sockets: The sockets on the right, top to bottom.
    ///   - connection: The connected socket id, or `nil`.
    ///   - configuration: Look, physics, feedback and data animation.
    ///   - onEvent: Receives ``CableEvent``s.
    ///   - socketContent: Builds what sits to the right of the port artwork in each row (the port itself stays,
    ///     so the plug still lands on it). ``SocketRowContent`` is the default.
    ///   - source: The device the cable comes out of. Its trailing edge is where the cable is anchored.
    public init(
        sockets: [PlugSocket<ID>],
        connection: Binding<ID?>,
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableEvent<ID>) -> Void)? = nil,
        @ViewBuilder socketContent: @escaping (PlugSocket<ID>, SocketRowState) -> RowContent,
        @ViewBuilder source: () -> Source,
    ) {
        self.sockets = sockets
        _connection = connection
        config = configuration
        self.onEvent = onEvent
        self.socketContent = socketContent
        self.source = source()
    }

    // MARK: Public

    public var body: some View {
        CableBoard(sockets: sockets, connection: $connection, configuration: config, onEvent: onEvent) {
            HStack(alignment: .top, spacing: 0) {
                source.cableSource(edge: .trailing)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sockets) { socket in
                        SocketRow(socket: socket, content: socketContent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Private

    @Binding private var connection: ID?

    private let sockets: [PlugSocket<ID>]
    private let config: CableConfiguration
    private let source: Source
    private let socketContent: (PlugSocket<ID>, SocketRowState) -> RowContent
    private let onEvent: ((CableEvent<ID>) -> Void)?

}

extension CablePatchView where RowContent == SocketRowContent<ID> {
    /// A patch view with the default row content (title, subtitle and status LED) and a custom source device.
    public init(
        sockets: [PlugSocket<ID>],
        connection: Binding<ID?>,
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableEvent<ID>) -> Void)? = nil,
        @ViewBuilder source: () -> Source,
    ) {
        self.init(
            sockets: sockets,
            connection: connection,
            configuration: configuration,
            onEvent: onEvent,
            socketContent: { SocketRowContent(socket: $0, state: $1) },
            source: source,
        )
    }
}

extension CablePatchView where Source == SourcePortView {
    /// A patch view with the built-in ``SourcePortView`` as the source device and custom row content.
    public init(
        sockets: [PlugSocket<ID>],
        connection: Binding<ID?>,
        sourceTitle: String,
        sourceSystemImage: String = "square.and.arrow.up",
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableEvent<ID>) -> Void)? = nil,
        @ViewBuilder socketContent: @escaping (PlugSocket<ID>, SocketRowState) -> RowContent,
    ) {
        self.init(
            sockets: sockets,
            connection: connection,
            configuration: configuration,
            onEvent: onEvent,
            socketContent: socketContent,
        ) {
            SourcePortView(title: sourceTitle, systemImage: sourceSystemImage)
        }
    }
}

extension CablePatchView where Source == SourcePortView, RowContent == SocketRowContent<ID> {
    /// The simplest form: built-in source device and default rows.
    public init(
        sockets: [PlugSocket<ID>],
        connection: Binding<ID?>,
        sourceTitle: String,
        sourceSystemImage: String = "square.and.arrow.up",
        configuration: CableConfiguration = CableConfiguration(),
        onEvent: ((CableEvent<ID>) -> Void)? = nil,
    ) {
        self.init(
            sockets: sockets,
            connection: connection,
            sourceTitle: sourceTitle,
            sourceSystemImage: sourceSystemImage,
            configuration: configuration,
            onEvent: onEvent,
            socketContent: { SocketRowContent(socket: $0, state: $1) },
        )
    }
}

// MARK: - SourcePortView

/// Default "device" the cable comes out of.
public struct SourcePortView: View {

    // MARK: Lifecycle

    /// - Parameters:
    ///   - title: Caption under the icon.
    ///   - systemImage: SF Symbol shown on the device.
    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    // MARK: Public

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.deviceText)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.deviceText.opacity(0.8))
                .lineLimit(1)
            // The physical port the cable exits from
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: theme.devicePort, startPoint: .top, endPoint: .bottom))
                .frame(width: 34, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, -14)
        }
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(width: 88)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: theme.deviceGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(theme.shadowOpacity), radius: 10, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.deviceBorder, lineWidth: 1))
    }

    // MARK: Internal

    let title: String
    let systemImage: String

    // MARK: Private

    @Environment(\.colorScheme) private var scheme
    @Environment(\.cableTheme) private var environmentTheme

    private var theme: CableTheme {
        environmentTheme ?? .automatic(for: scheme)
    }

}

// MARK: - SocketRowContent

/// The default content of a ``CablePatchView`` row: title with icon, optional subtitle, and a status LED that
/// lights in the socket's tint when connected.
public struct SocketRowContent<ID: Hashable>: View {

    // MARK: Lifecycle

    public init(socket: PlugSocket<ID>, state: SocketRowState) {
        self.socket = socket
        self.state = state
    }

    // MARK: Public

    public var body: some View {
        let theme = environmentTheme ?? .automatic(for: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Label(socket.title, systemImage: socket.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let subtitle = socket.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.subtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        Spacer(minLength: 8)
        // Status LED
        Circle()
            .fill(state.isConnected ? socket.tint : theme.ledOff)
            .frame(width: 8, height: 8)
            .shadow(color: state.isConnected ? socket.tint.opacity(0.9) : .clear, radius: 5)
            .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: Private

    @Environment(\.cableTheme) private var environmentTheme
    @Environment(\.colorScheme) private var scheme

    private let socket: PlugSocket<ID>
    private let state: SocketRowState

}

// MARK: - SocketRow

/// One row of a ``CablePatchView``: the port artwork, the row content, and the card around them. The row is
/// one accessibility element (a button), so the port inside it doesn't announce separately.
struct SocketRow<ID: Hashable, Content: View>: View {

    // MARK: Internal

    let socket: PlugSocket<ID>
    let content: (PlugSocket<ID>, SocketRowState) -> Content

    var body: some View {
        let state = states[socket.id]
        let theme = environmentTheme ?? .automatic(for: scheme)
        HStack(spacing: 10) {
            CableSocketPortView(id: socket.id, tint: socket.tint, accessibilityLabel: Text(verbatim: socket.title))
            content(socket, state)
        }
        .padding(.vertical, 8)
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.cardFill)
                .shadow(color: theme.cardShadow, radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    state.isConnected
                        ? socket.tint
                            .opacity(0.9)
                        : (state.isHovered ? socket.tint.opacity(0.6) : theme.cardBorder),
                    lineWidth: state.isConnected || state.isHovered ? 1.5 : 1,
                )
        )
        .scaleEffect(1 + states.pulse(socket.id) * 0.03)
        .opacity(socket.isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { toggle(AnyHashable(socket.id)) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: socket.title))
        .accessibilityValue(CableStrings.value(connected: state.isConnected))
        .accessibilityHint(CableStrings.hint(connected: state.isConnected))
        .accessibilityAction { toggle(AnyHashable(socket.id)) }
        .animation(.spring(duration: 0.25), value: state.isHovered)
        .animation(.spring(duration: 0.3), value: state.isConnected)
    }

    // MARK: Private

    @Environment(\.cableSocketStates) private var states
    @Environment(\.cableTheme) private var environmentTheme
    @Environment(\.cableToggleSocket) private var toggle
    @Environment(\.colorScheme) private var scheme

}
