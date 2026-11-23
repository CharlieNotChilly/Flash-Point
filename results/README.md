# Results

Every number on the résumé and in the README must trace to a file here. Commit these files.

```
results/
  environment.md            CPU, RAM, OS, Docker resources, Puma workers/threads
  load/
    naive-<timestamp>.json      k6 summary export
    naive-<timestamp>.txt       bin/check_invariant output
    locked-...                  same for design B
    flashpoint-...              same for design C
    summary.md                  table produced by bin/summarize_load
  chaos/
    summary.json                per-run target, timings, invariant result
    summary.md                  totals: runs, kills per target, failures
```

## Where each résumé number comes from

| Résumé value | Source |
|---|---|
| `[X]` naive oversold units | `load/summary.md`, design A row |
| `[Y]×` throughput | `load/summary.md`, flashpoint ÷ locked |
| `[Z] ms` p99 | `load/summary.md`, design C row |
| 0 oversold (Flashpoint) | `load/flashpoint-*.txt` invariant output |
| 50 chaos runs, 0 lost/duplicate | `chaos/summary.md` |

Rules: don't edit result files by hand, don't delete failed runs, and use the latest complete set (for chaos, 50 consecutive runs).
