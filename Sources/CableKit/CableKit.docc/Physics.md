# Physics and feel

How the cable moves, and the knobs that change it.

## Overview

The cable is a Verlet rope: a chain of points joined by distance constraints, integrated at the
display refresh rate and solved with a handful of relaxation passes per frame. The plug is a rigid
body attached to the rope's end, with its own gravity and collisions, so a dropped plug lands and lies
on the floor like an object. When nothing moves, the simulation sleeps.

## Length and slack

- `restLength` — `nil` (default) sizes the cable so it can reach every socket and, when hanging,
  `hangFraction` of the way down the view. Set a value to fix it.
- `hangFraction` — 1 lets a free-hanging plug rest on the floor; 0.7 makes it dangle 70% of the way
  down. The full length is still paid out while dragging or plugged in, and the cable retracts to the
  hang length when dropped.
- `autoSlack` / `slack` — a take-up reel keeps the cable only `slack` points longer than the distance
  it spans, so it sags gently when plugged in and follows cleanly when dragged instead of whipping
  around. While hanging it only pays out, never reels in.
- `maxStretch` — how far past rest length the plug can be pulled before it stops following the
  finger (1.22 = 22%). Tension between rest and max drives the stretch haptic and creak.
- `elasticity` — 0 is an inextensible rope, 1 a bungee. Higher values stretch further when pulled by
  hand and bounce back with less damping. Only a finger pulling counts as load: the cable never
  stretches under its own weight or when swinging with the device.

## Motion

- `gravity` — points / s². `gravityFollowsDevice` rotates it with the phone's tilt via Core Motion.
- `damping` — per-frame velocity retention when free; `dragDamping` while the plug is held.
- `segmentCount` — rope resolution.

## Snapping

- `snapRadius` — distance from a socket at which the magnet starts pulling and the ring lights up.
- `hoverSwitchMargin` / `hoverSwitchDelay` — hysteresis so that sitting between two sockets doesn't
  flicker: another socket must be markedly closer, for a moment, to take over.
- `unplugDistance` — how far a seated plug must be tugged before it pops out. A tap ejects it too.
- `plugHitRadius` — touch target around the plug body.
- `cableGrabEnabled` / `cableHitRadius` — touching the cable anywhere along its length pins that point
  to the finger; the rest of the rope (and the plug) keep their physics, and the point keeps the
  finger's velocity when released, so the cable can be flicked. Works while plugged in too.
  With `cableGrabStretchFeedback` the cable creaks and the tension haptic ramps as you stretch it
  beyond its length (the jacket also thins), exactly like pulling the plug taut.

## Sequence of a connection

1. **Drag** — the finger holds the tip; body and cable trail behind.
2. **Hover** — inside `snapRadius` the plug is pulled toward the socket mouth and levelled.
3. **Snap** — on release, a damped spring carries the tip to the socket face.
4. **Insert** — the pin slides in over ~110 ms (slide sound), then seats (click, haptic, ring pulse,
   socket closes).
5. **Seated** — the data animation runs; the cable sags with its slack.
6. **Eject** — a tug past `unplugDistance` or a tap slides the pin out (slide + pop) and the drag continues.
