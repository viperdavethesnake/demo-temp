# Ground truth — generator-side documentation

The data Symphony scanned is synthetic, produced by the **PanzuraDemo v4.1.0** generator. The generator team maintains authoritative documentation that explains *why* each pattern exists, what storyline it's meant to surface, and what *not* to claim about it on stage.

Do not duplicate that material here. Read it from source so updates flow through automatically.

## Authoritative source

On the demo host (`PANZURA-SYM02`):

```
C:\Users\Administrator\Documents\pan-demo-data\docs\demo-dataset\
├── README.md                       (index — start here)
├── dataset-snapshot.md             (actual counts, distributions, sample paths)
├── demo-narrative-and-widgets.md   (9 demo storylines + suggested widgets + sample SQL)
└── build-recipe-and-caveats.md     (how the data was made + don't-say list for stage)
```

## Designer fast-path

1. Start with `demo-narrative-and-widgets.md` — **this is the source of truth for what the dashboards should prove**. It lists nine storylines, each with a hook, metric, data source column, suggested widget, and sample query.
2. Cross-reference `dataset-snapshot.md` for exact numbers (file counts, byte totals, distributions). Every number in the Grafana dashboards should roughly match these — tolerances under `findings.md` in this pack.
3. Consult `build-recipe-and-caveats.md` before publishing anything externally — some claims are off-limits (synthetic timestamps aren't real customer history; file contents are random bytes; "Deadbeat Corp" is a demo narrative, not a real acquisition).

## What our ClickHouse data confirmed from the spec

Every ground-truth number we could verify matched. See `exports/docs/findings.md` for the full cross-validation table — ownership split (55/25/10/5/5), 2019 bulge at 9.62%, IT at 14.81 TiB, 69.5% dormant by last_accessed, all within rounding.

The key implication: **the scan is faithful**. If a dashboard shows a number that disagrees with the generator spec, it's a dashboard bug, not a data quality issue.
