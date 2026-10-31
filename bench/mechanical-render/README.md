# Mechanical renderer comparison

The change loads only the currently selected opaque or transparent surface
construction. Previously both Shapes existed, including their paths and live
bindings, even when one was invisible. Curves, control points, gradients,
opacity, strokes, press deformation and lighting are unchanged.

## Reproduce

From a graphical session with Qt6 development files, a C++ compiler,
`dbus-run-session` and Pillow:

```sh
python3 bench/mechanical-render/compare.py --reference 0ad719b --mode both
```

This compares the baseline revision to the current working tree. It uses a
unique temporary HOME/runtime/config/cache/data directory and private D-Bus.
No keyboard input, live Service, compositor rules or user settings are changed.
`--mode visual` or `--mode timing` selects one part. Raw output and snapshots
remain in the printed temporary directory. GPU screenshots may take a few
minutes on a small system.

## Visual fidelity

All **32 before/after images were pixel-identical** on the development Intel
GPU (zero tolerance). Each has 144 caps covering the four materials, three
sizes, narrow/ordinary/wide shapes, normal/latched/locked states, pressed and
resting caps, drawn icons and corner glyphs. Cases vary backlight, shine-through,
light/dark shell colors and static/frozen ripple states. Tested device scale
factors: 1 and 1.25. Ripple properties are frozen at deterministic phases;
there is no wall-clock frame matching. An image was also inspected to confirm
that actual keycaps rendered. This excludes native compositor blur, whose
configuration is unchanged. See `visual-results.json`.

## Performance

Two interleaved before/after trials, Intel N100 / Mesa ADL-N OpenGL. Same
80-key, 1280×360 board, six visual presses/sec, two-second warmup and about
eight seconds per phase. 100% CPU means one core. Full raw results, including
GPU activity and RSS, are in `measured-results.json`.

| Trial | Mode | CPU ms/frame before → after | GUI ms/frame before → after | Frames/sec before → after |
| --- | --- | --- | --- | --- |
| 1 | Static | 49.27 → 45.09 | 4.16 → 3.83 | 12.1 → 11.9 |
| 2 | Static | 39.17 → 36.99 | 3.61 → 2.70 | 12.0 → 12.0 |
| 1 | Ripple | 52.22 → 42.89 | 17.11 → 12.96 | 26.1 → 37.6 |
| 2 | Ripple | 42.95 → 41.38 | 13.38 → 12.07 | 41.1 → 43.5 |

Static rendering CPU/frame improved about 6–8%; animated about 4–18%, with
GUI-thread CPU/frame down about 10–24% in animated trials. Idle remained zero
redraws and zero measured GPU render activity. Peak RSS was slightly lower
in both pairs. Material changes recreate the active surface once.

These are short local trials under variable desktop/memory load. Higher
animation throughput also consumed more total CPU/GPU time per second; this
is **not a claim of lower animated power consumption**, 60 fps, or measured
touch-to-text latency. Static ~12 frames/sec is expected: only press/release
changes redraw. Native compositor blur, battery and thermal endurance were
not measured. Lighting Effects off remains the strongest responsiveness
control. Existing theme/material regression tests also pass.
