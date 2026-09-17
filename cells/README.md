# Cells

One directory per cell. A cell is a unit of content with one domain: it has no
position of its own and no max width of its own, and takes what its tissue
grants.

Adding a new cell must cost **one config block**, never a structural change.
If a cell needs the layout engine changed, either the engine is wrong or the
cell is.

Suggested shape of a cell directory:

```
cells/vitals/
  Vitals.qml          the cell itself — visibility rule, domain options
  Contracted.qml      indicators only; no figures at rest
  Expanded.qml        grows from the cell's anchor point
  <Indicator>.qml     per-domain drawing
```

## Catalogue and build order

Phase 2 — the three that validate the system:

| Cell | Validates |
|---|---|
| `window_title` | conditional presence, elastic width |
| `workspaces` | vertical expansion — the first vertical orientation in the system |
| `vitals` | animated indicators, expansion, click-to-sort, kill confirmation |

Phase 3 — identity: `sinestesia`, `theme`, `utility`.
Phase 4 — replacement: `volume`, `connectivity`, `session`, `dock`, then
`notifications` last.
Phase 5 — `settings`. Phase 6 — `launcher`, alone.

Each cell's behaviour is specified in PRD §9. Read that section before starting
one; the open questions it flags are open on purpose.
