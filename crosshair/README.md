# Crosshair

A click-through fullscreen aiming crosshair rendered on the Wayland overlay
layer, toggled from a bar widget. Every part — color, outline, center dot,
inner and outer line sets, and screen offset — is configurable in Settings, so
you can dial in a CS/Valorant/Apex-style reticle for any game.

## Plugin

| Field | Value |
| --- | --- |
| ID | `celestiat/crosshair` |
| Entries | Bar widget: `toggle`; layer: `overlay` |

## Requirements

- Noctalia with plugin API level >= 36 (`[[layer]]` entry support).
- No external dependencies. Requires a compositor supporting
  `zwlr-layer-shell-v1` (all Noctalia setups do).

## Usage

1. Enable the plugin (Settings -> Plugins, or `noctalia msg plugins enable celestiat/crosshair`).
2. Add the **Crosshair** bar widget to a bar (Add-widget picker).
3. Click the widget icon to toggle the crosshair. While on, the icon is tinted
   with the configured crosshair color.

The crosshair is drawn on the `overlay` layer, anchored to all four edges with
`exclusive_zone = -1`, so its center is the physical screen center — matching
fullscreen games regardless of bar layout. The surface has an empty input
region (`click_through = true`): the mouse passes through everywhere and
nothing below is disturbed. On multi-monitor setups every output shows its own
centered crosshair.

## Settings

Edited under Settings -> Plugins (gear icon). Changes apply live while the
crosshair is visible (polled at ~120 ms from the layer's frame tick).

### Crosshair Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `color` | `color` | `#00E676` | Fill color of every crosshair part. |
| `outline` | `bool` | `false` | Draw a black outline around every part. |
| `outline_pct` | `int` 0-100 | `60` | Outline opacity (%). |
| `outline_thickness` | `int` px | `1` | Outline grows this many px beyond each part. |
| `offset_x` | `int` px | `0` | Shift the whole reticle horizontally (right positive). Calibrate against your game's own center rounding. |
| `offset_y` | `int` px | `0` | Shift the whole reticle vertically (down positive). |

### Center Crosshair

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `center_enabled` | `bool` | `true` | Show the center element. |
| `center_shape` | `select` | `cross` | `cross` / `dot` / `ring` / `x`. |
| `center_pct` | `int` 0-100 | `100` | Center element opacity (%). |
| `center_thickness` | `int` px | `2` | Drives both line width and overall size of the center element (cross/x arm length = 3t, dot diameter = 2t, ring radius = 2t). |

### Inner Crosshair

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `inner_enabled` | `bool` | `true` | Show the four inner tick lines. |
| `inner_pct` | `int` 0-100 | `100` | Opacity (%). |
| `inner_length` | `int` px | `6` | Line length. |
| `inner_thickness` | `int` px | `2` | Line width. |
| `inner_offset` | `int` px | `6` | Gap between each line's near end and the center. |

### Outer Crosshair

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `outer_enabled` | `bool` | `false` | Show the four outer tick lines. |
| `outer_pct` | `int` 0-100 | `100` | Opacity (%). |
| `outer_length` | `int` px | `14` | Line length. |
| `outer_thickness` | `int` px | `2` | Line width. |
| `outer_offset` | `int` px | `20` | Gap between each line's near end and the center. |

All sizes are logical pixels and scale with display scaling.

## Notes

- The layer entry generates the reticle as an SVG written into the plugin's own
  data directory (`pluginDataDir()`), then renders it with `ui.image`. Two
  file names are alternated so the image loader never shows a stale cached
  bitmap; nothing outside the plugin data directory is ever written.
- Live refresh uses `layer.setNeedsFrameTick` and a ~120 ms config-signature
  poll because the host currently does not notify layer runtimes of setting
  changes. The polling callback only builds a small string; rendering happens
  only when something actually changed. Hiding the crosshair destroys the
  layer runtime entirely, so there is zero cost while it is off.
- The toggle widget persists its shown-state in process-wide `noctalia.state`,
  so bar/widget rebuilds (e.g. after changing settings) keep the icon and the
  overlay in sync.
- The overlay surface is fullscreen but fully click-through; if a compositor
  bug ever traps input, disabling the plugin removes the surface immediately.
