# WaterClock

A rising-water countdown timer painted on the fullscreen overlay layer. Click
the bar widget and the water level climbs from the bottom of the screen to the
top over the configured duration — glance at the waterline to read time
remaining. Fully click-through: the water never blocks your mouse.

## Plugin

| Field | Value |
| --- | --- |
| ID | `celestiat/waterclock` |
| Entries | Bar widget: `toggle`; layer: `water` |

## Requirements

- Noctalia with plugin API level >= 36 (`[[layer]]` entry support).
- No external dependencies.

## Usage

1. Enable the plugin (Settings -> Plugins, or `noctalia msg plugins enable celestiat/waterclock`).
2. Add the **WaterClock** bar widget to a bar.
3. Click the droplet icon to start the timer: the water starts rising from the
   bottom of the screen and reaches the top exactly when the timer expires.
   Click again while running to stop and reset.
4. With no timer running, scroll the wheel over the widget to adjust this
   session's duration in one-minute steps (tooltip shows the current value).
5. The widget tooltip shows a live countdown; the icon turns into waves while
   running. When the timer completes, the water either stays full or hides,
   per the `end_action` setting.

Without a running timer the overlay shows a static idle waterline at
`Idle Water Level`, which makes the plugin double as a decorative water effect.

## Settings

All edited under Settings -> Plugins (gear icon). The overlay re-renders at the
configured frame rate, so setting changes are picked up within a second.

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `duration_min` | `int` 1-180 | `25` | Timer duration in minutes (scroll adjusts per-session override). |
| `end_action` | `select` | `stay` | What happens when the water reaches the top: `stay` (full screen) or `hide`. |
| `static_level` | `int` 0-100 | `45` | Water height (%) while no timer runs. |
| `color_surface` | `color` | `#3ec6e0` | Water tint just under the surface. |
| `color_deep` | `color` | `#032c54` | Water tint at the bottom (red-absorption gradient). |
| `fog_strength` | `int` 0-100 | `55` | Overall opacity of the water body. |
| `wave_amplitude` | `int` 0-40 | `8` | Vertical swing of the waterline in px. |
| `wave_length` | `int` 200-1500 | `640` | Wavelength in px. |
| `wave_speed` | `int` 0-100 | `35` | Animation speed of all water motion (0 = frozen). |
| `caustics_density` | `int` 0-30 | `12` | Number of light/dark caustic bands. |
| `caustics_strength` | `int` 0-100 | `55` | Caustic visibility. |
| `rays_density` | `int` 0-20 | `9` | Number of volumetric light shafts. |
| `rays_strength` | `int` 0-100 | `50` | Light shaft visibility. |
| `bubbles` | `bool` | `true` | Rising bubble trails. |
| `bubble_density` | `int` 0-60 | `18` | Number of bubble trails. |
| `sparkles` | `bool` | `true` | Twinkling specular dots along the waterline. |
| `render_fps` | `select` | `30` | Overlay animation frame rate cap (15/30/60). |
| `click_through` | `bool` | `true` | When off, the water surface captures the mouse instead of passing it through. |

Sizes are logical pixels; the overlay covers the whole physical screen
(`exclusive_zone = -1`), unaffected by bars or other reserved areas.

## IPC

```sh
noctalia msg plugin celestiat/waterclock:toggle all start   # start timer
noctalia msg plugin celestiat/waterclock:toggle all stop    # stop and reset
noctalia msg plugin celestiat/waterclock:toggle all set 45  # set session duration (minutes)
```

## Notes

- The water is a *stylized* overlay (tint, waterline, caustics, light shafts,
  bubbles): the plugin API cannot sample the compositor background, so content
  under the water is not refracted or blurred.
- Each animation frame generates a small SVG written to the plugin's own data
  directory (`pluginDataDir()`) and renders it via `ui.image`; two filenames
  alternate to defeat image caching. Nothing outside the plugin data directory
  is written. No network access, no spawned processes.
- Timer state lives in process-wide `noctalia.state`, so it survives widget
  rebuilds and is shared between the bar widget and the layer runtime.
- While the overlay is hidden there is zero cost: the layer runtime and
  surface are destroyed on hide.
- Multi-monitor: every output renders its own fullscreen water.
