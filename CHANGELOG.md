# Changelog

## 1.0.0 — 2026-09-19

First release.

- `CablePatchView`: a device-on-the-left, sockets-on-the-right patch bay in one line.
- `CableBoard`: any layout — mark a source and sockets anywhere in ordinary SwiftUI; any number of
  cables per board, sockets that take one plug at a time and can restrict plug styles.
- Verlet rope physics with a rigid plug, take-up reel, elasticity, stretch limit, floor and walls,
  optional tilt gravity.
- Nine plug styles with matching sockets; round, coiled, ribbon and neon cables; custom renderers.
- Core Haptics patterns and synthesized sounds (no assets), both replaceable through protocols.
- Electric sparks, bit and Morse data traffic, light and dark themes.
- Swift 6 language mode, `@MainActor` throughout, VoiceOver, Reduce Motion, localized strings.
