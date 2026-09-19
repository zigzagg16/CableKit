import SwiftUI

/// User-facing strings the package ships, all from `Localizable.xcstrings` in the package bundle.
/// Only accessibility text so far; socket titles come from the host app.
enum CableStrings {
    static var socket: Text {
        Text("Socket", bundle: .module)
    }

    static func value(connected: Bool) -> Text {
        connected ? Text("Connected", bundle: .module) : Text("Not connected", bundle: .module)
    }

    static func hint(connected: Bool) -> Text {
        connected ? Text("Double tap to disconnect", bundle: .module) : Text("Double tap to connect", bundle: .module)
    }
}
