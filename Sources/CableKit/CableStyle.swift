import SwiftUI

// MARK: - CableStyle

/// How the cable itself is drawn.
///
/// The default renderer draws a shaded tube (dark rim, jacket, two highlights) with a drop shadow.
/// Set ``renderer`` to replace it entirely; the closure receives the smoothed path and everything
/// the default uses, so you can draw a striped cable, a rope, a glowing wire…
public struct CableStyle: Equatable, Sendable {

    // MARK: Lifecycle

    /// A round tube. Every parameter matches the property of the same name; the defaults are the orange
    /// cable the demo starts with.
    public init(
        color: Color = Color(red: 0.98, green: 0.45, blue: 0.18),
        width: CGFloat = 11,
        stretchedColor: Color? = nil,
        stretchThinning: CGFloat = 0.22,
        rimShade: CGFloat = 0.55,
        highlight: CGFloat = 0.32,
        shadowOpacity: Double? = nil,
        renderer: Renderer? = nil,
        dataFlowPath: DataFlowPath? = nil,
    ) {
        self.color = color
        self.width = width
        self.stretchedColor = stretchedColor
        self.stretchThinning = stretchThinning
        self.rimShade = rimShade
        self.highlight = highlight
        self.shadowOpacity = shadowOpacity
        self.renderer = renderer
        self.dataFlowPath = dataFlowPath
    }

    // MARK: Public

    /// Draws the whole cable. Called once per frame with the canvas context and everything the default
    /// renderer would have used.
    public typealias Renderer = @Sendable (_ context: inout GraphicsContext, _ cable: CableDrawingContext) -> Void
    /// Supplies the path the data traffic animates along, for renderers that draw off the centreline.
    public typealias DataFlowPath = @Sendable (_ cable: CableDrawingContext) -> Path

    /// Main jacket colour.
    public var color: Color
    /// Diameter in points.
    public var width: CGFloat
    /// Optional colour the jacket shifts toward at full stretch. `nil` keeps ``color``.
    public var stretchedColor: Color?
    /// How much thinner the cable gets at full stretch (0…1 fraction of ``width``).
    public var stretchThinning: CGFloat
    /// Darkening of the outer rim, 0…1.
    public var rimShade: CGFloat
    /// Opacity of the top highlight, 0…1. 0 disables both highlight passes.
    public var highlight: CGFloat
    /// Drop shadow under the cable and plug. `nil` = follow the theme's `shadowOpacity`.
    public var shadowOpacity: Double?
    /// Custom renderer. When set, only it is called (the plug is still drawn afterwards).
    public var renderer: Renderer?
    /// Path the data traffic runs along. `nil` uses the cable's centreline; a renderer that
    /// draws the cable off-centre (see ``coiled(color:width:coilRadius:pitch:leadLength:)``) supplies its own.
    public var dataFlowPath: DataFlowPath?

    /// Custom renderers and data paths are compared by presence only.
    public static func ==(lhs: CableStyle, rhs: CableStyle) -> Bool {
        lhs.color == rhs.color && lhs.width == rhs.width && lhs.stretchedColor == rhs.stretchedColor
            && lhs.stretchThinning == rhs.stretchThinning && lhs.rimShade == rhs.rimShade
            && lhs.highlight == rhs.highlight && lhs.shadowOpacity == rhs.shadowOpacity
            && (lhs.renderer == nil) == (rhs.renderer == nil)
            && (lhs.dataFlowPath == nil) == (rhs.dataFlowPath == nil)
    }

}

// MARK: - CableDrawingContext

/// What a ``CableStyle/Renderer`` receives.
public struct CableDrawingContext {

    // MARK: Lifecycle

    /// Assembled by the canvas each frame; public so custom renderers can be exercised in tests and previews.
    public init(
        path: Path,

        points: [CGPoint],
        stretch: CGFloat,
        style: CableStyle,
        theme: CableTheme,
        width: CGFloat,
        jacket: Color,
        environment: EnvironmentValues = EnvironmentValues(),
    ) {
        self.path = path
        self.points = points
        self.stretch = stretch
        self.style = style
        self.theme = theme
        self.width = width
        self.jacket = jacket
        self.environment = environment
    }

    // MARK: Public

    /// Smoothed path from the source port to the plug's boot.
    public var path: Path
    /// Rope points the path was built from (source → plug).
    public var points: [CGPoint]
    /// Tension past rest length, 0…1.
    public var stretch: CGFloat
    /// The style being rendered.
    public var style: CableStyle
    /// Resolved theme.
    public var theme: CableTheme
    /// Effective line width after stretch thinning.
    public var width: CGFloat
    /// Jacket colour after stretch tinting.
    public var jacket: Color
    /// The environment the cable is drawn in; pass it to ``PlugArt/darken(_:by:in:)`` and friends so
    /// dynamic colours resolve for the current appearance.
    public var environment: EnvironmentValues

}
