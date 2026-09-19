# ``CableKit``

A physical patch cable for SwiftUI: drag a plug on a rope into a socket, with real physics,
haptics and sound.

## Overview

`CableKit` renders a cable hanging from a source device on the left and a column of sockets on the
right. The user drags the plug by its tip; the cable trails behind with rope physics, snaps
magnetically into a socket, slides its pin in with a click, and can be tugged or tapped back out.

```swift
import CableKit

struct ConnectView: View {
    @State private var connection: DataSource? = nil

    var body: some View {
        CablePatchView(
            sockets: [
                PlugSocket(id: .postgres, title: "Postgres", subtitle: "prod-db-01", systemImage: "cylinder.split.1x2", tint: .cyan),
                PlugSocket(id: .s3, title: "S3 Bucket", systemImage: "externaldrive", tint: .orange),
            ],
            connection: $connection,
            sourceTitle: "Orders",
            sourceSystemImage: "cart.fill"
        )
    }
}
```

`connection` is a two-way binding: the view updates it when the user plugs or unplugs, and you can
set it yourself to animate the plug in or eject it.

Everything is configurable through ``CableConfiguration`` (look, physics, feedback, data animation),
``CableTheme`` (colours), ``PlugStyle`` (connector artwork) and the ``CableHapticsProvider`` /
``CableSoundProvider`` protocols. The defaults are tuned to feel good out of the box.

## Topics

### Essentials

- ``CablePatchView``
- ``CableBoard``
- ``CableSocketPortView``
- ``PlugSocket``
- ``CableConfiguration``
- ``CableEvent``
- <doc:Customization>
- <doc:Physics>

### Look

- ``PlugStyle``
- ``PlugArt``
- ``CableStyle``
- ``CableTheme``
- ``SourcePortView``
- ``SocketRowState``

### Data traffic

- ``DataFlowStyle``
- ``DataFlowDirection``

### Feedback

- ``CableHapticsProvider``
- ``CableSoundProvider``
- ``DefaultCableHaptics``
- ``SynthesizedCableSounds``
- ``SilentCableFeedback``
