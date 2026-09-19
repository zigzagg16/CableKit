# Customization

Change the plug, the cable, the colours, the sounds, the haptics and the socket rows.

## Overview

All customization goes through ``CableConfiguration`` plus a few protocols and view builders.
Configuration changes apply live — you can switch plug styles while the cable is plugged in.

## Plug style

Pick a built-in connector or design your own. Each ``PlugStyle`` bundles the plug's dimensions,
a drawing closure and a socket view, so the socket always matches the plug.

```swift
config.plugStyle = .ethernet      // .audioJack (default), .europlug, .usbC, .banana, .ethernet, .magSafe
```

To create one, draw in *plug space*: the origin is the end of the rope (the boot), `+x` points toward
the tip, `+y` is down, and the tip is at `length`. ``PlugArt`` provides boots, metals, pins and
shadows so a custom plug is a few lines:

```swift
let stubby = PlugStyle(
    id: "stubby", displayName: "Stubby",
    length: 48, insertTravel: 10, socketFaceOffset: 8,
    draw: { ctx, plug in
        let boot = CGRect(x: -4, y: -6, width: 18, height: 12)
        let body = Path(roundedRect: CGRect(x: 12, y: -9, width: 24, height: 18), cornerRadius: 4)
        let pin = PlugArt.pin(from: 34, to: 48, halfHeight: 3, clip: plug.clip)
        PlugArt.dropShadow(&ctx, [Path(roundedRect: boot, cornerRadius: 4), body, pin ?? Path()])
        PlugArt.boot(&ctx, rect: boot, plug: plug)
        ctx.fill(body, with: PlugArt.metal(-9, 9))
        if let pin { ctx.fill(pin, with: PlugArt.gold) }
    },
    socket: { s in
        ZStack {
            Circle().fill(s.bezel).frame(width: 30, height: 30)
            Circle().fill(s.hole).frame(width: 14, height: 14)
            s.cover(Circle(), size: CGSize(width: 14, height: 14), fill: PlugArt.goldFace)
            s.ring(Circle(), size: CGSize(width: 30, height: 30))
        }
    }
)
```

`plug.clip` is the local x past which the pins are inside the socket; pass it to ``PlugArt/pin(from:to:halfHeight:clip:)``
and the pin disappears as it slides in. In the socket closure, ``SocketContext/cover(_:size:fill:)`` closes the hole
when seated and ``SocketContext/ring(_:size:)`` lights up on hover / connection.

## Cable

``CableStyle`` controls the jacket; set it through `config.cable`.


```swift
config.cable.color = .mint
config.cable.width = 14
config.cable.stretchedColor = .yellow     // tint toward this at full stretch (nil = none)
config.cable.highlight = 0                // matte cable
```

For anything else, supply a renderer and draw the path yourself:

```swift
config.cable.renderer = { ctx, cable in
    ctx.stroke(cable.path, with: .color(.black), style: StrokeStyle(lineWidth: cable.width + 2, lineCap: .round))
    ctx.stroke(cable.path, with: .color(.yellow), style: StrokeStyle(lineWidth: cable.width, lineCap: .round, dash: [12, 12]))
}
```

## Theme

``CableTheme`` holds every colour that isn't cable or plug artwork: cards, text, LEDs, the source
device, socket bezels and holes, shadow opacity. `.light` and `.dark` are the defaults, chosen from the
system appearance when `config.theme` is `nil`.

```swift
var theme = CableTheme.dark
theme.cardFill = Color(red: 0.16, green: 0.12, blue: 0.10)
theme.deviceGradient = [.orange, .red]
config.theme = theme                       // one view
ContentView().cableTheme(theme)            // whole hierarchy
```

Custom `source` views can read `@Environment(\.cableTheme)` to match.

## Free layout with CableBoard

``CablePatchView`` is a ``CableBoard`` with a fixed layout. For anything else, use the board and
mark your own views:

```swift
CableBoard(sockets: sockets, connection: $connection) {
    ZStack {
        Hub().cableSource(edge: .center)
        ForEach(sockets) { s in
            Bubble(s).overlay(alignment: .bottom) { CableSocketPortView(id: s.id, tint: s.tint) }
                .offset(x: cos(s.angle) * 140, y: sin(s.angle) * 140)
        }
    }
}
```

`cableSource(edge:)` sets where the cable leaves the source (`.trailing` by default; `.center` for a
hub). ``CableSocketPortView`` draws the receptacle for the current plug style, lights up, and
connects on tap; any view can do the same through `@Environment(\.cableSocketStates)` and
`@Environment(\.cableToggleSocket)`.

Set each socket's `entryAngle` to choose which way the plug comes in — `.zero` from the left (default),
`.degrees(180)` from the right, `.degrees(90)` from above, or a radial angle for a ring. The socket
artwork rotates with it and the cable aligns itself to enter straight. Leave ~70 pt of room on the
entry side for the plug body.

## Source device and socket rows

The left-hand device is any view; its trailing edge is where the cable is anchored:

```swift
CablePatchView(sockets: sockets, connection: $connection) {
    MyDeviceCard()
}
```

Replace the text and LED inside each socket row (the port artwork stays, so the plug still lands
on it):

```swift
CablePatchView(sockets: sockets, connection: $connection, sourceTitle: "Orders",
               socketContent: { socket, state in
    HStack {
        Text(socket.title).bold()
        Spacer()
        if state.isSeated { Image(systemName: "checkmark.circle.fill") }
    }
})

```

## Sounds and haptics

The defaults are ``SynthesizedCableSounds`` (procedural, no assets) and ``DefaultCableHaptics``
(CoreHaptics with a `UIFeedbackGenerator` fallback). Replace either by conforming to
``CableSoundProvider`` / ``CableHapticsProvider``:

```swift
final class SampledSounds: CableSoundProvider {
    func plugIn() { play("click") }
    func unplug() { play("pop") }
    func insert() { play("slide-in") }
    func eject() { play("slide-out") }
    func hover() { play("tick") }
    func creak(level: CGFloat) { play("creak", volume: Float(level)) }
    func drop(velocity: CGFloat) { play("thud", volume: Float(min(velocity / 40, 1))) }
}

config.sounds = SampledSounds()
config.haptics = SilentCableFeedback()     // haptics off, sounds on
```

`config.soundEnabled` and `config.hapticsEnabled` are master switches on top of whatever provider is set.

## Data traffic

While the plug is seated, a pattern travels inside the cable:

```swift
config.dataFlow = .morse("SYNC OK")       // or .bits (default), .none
config.dataFlowDirection = .toSocket      // default is .toSource (data pulled in)
config.dataFlowSpeed = 200
config.dataFlowColor = .cyan
config.dataFlowGlow = 2.5
```

## Sparks

Electric arcs between the socket and the pin, with crackle and haptics. `SparkTrigger` picks when:

```swift
config.spark = .both        // .none, .plugIn, .unplug (default), .both
config.sparkColor = .purple
config.sparkDuration = 0.5  // the big arcs; approach flickers are shorter
```

- `.plugIn` — as the pin nears a socket, small arcs jump the gap intermittently (more often and
  brighter the closer it gets), then a zap as it starts sliding in.
- `.unplug` — a flickering bolt as the plug is pulled out.

Custom feedback providers can implement `spark()` and `crackle(intensity:)` (both have no-op
defaults) to add their own sounds or haptics.

## Events

```swift
CablePatchView(sockets: sockets, connection: $connection, sourceTitle: "Orders") { event in
    switch event {
    case .plugged(let id): analytics.log("connected", id)
    case .stretched(let tension) where tension > 0.9: showHint("Careful!")
    default: break
    }
}
```
