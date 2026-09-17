# Components

Shared primitives used by more than one cell. Anything used by exactly one cell
belongs in that cell's directory.

Expected early residents:

- **Thread** — the 1.3 px connector with nodes at its ends and a barely
  suggested curve, joining the floating shapes of an expanded cell. Threads are
  the decided silhouette; metaball soft-union is rejected. 1.3 px is exactly the
  critical-dimension case: round to the physical pixel under fractional scaling
  or the thread blurs or vanishes. Drawing animates via `ShapePath.dashOffset`.
- **Capsule** — the small regular shape an expanded panel is built from.
  Overshoot easing is appropriate here and not on large panels.
- **Indicator** — the shared base for vitals drawing: motion encodes a live
  value in its rate or extent, colour encodes state.
