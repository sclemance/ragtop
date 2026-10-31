# Swipe geometry reuse

`Swipes.set_keys` validates and normalizes geometry before updating the active
layout. Identical coordinates and unit reuse that decoder's word-path index.
The guard is per decoder, so changing language cannot reuse another language's
index. Service coalesces geometry notifications in one event-loop turn and
flushes before a preview/final swipe; helper readiness forces a resend.

Verification: `bash tests/run swipe-geometry predictor` passes. Tests cover
identity/reordered mappings, real changes, malformed input, independent
languages, deferred notifications, request ordering and helper readiness.

On the development Intel N100, an installed 28,512-word English list took
204 ms to build once; 1,000 identical updates averaged 0.027 ms each. This
measures index handling, not touch-to-text latency. Prior repeated rebuilds
were 203–301 ms. Real geometry changes still incur the necessary rebuild.
