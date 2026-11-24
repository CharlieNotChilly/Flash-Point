# Checkout load results

| Design | Oversold units | Attempts/s | Full-checkout p99 (ms) | Run evidence |
|---|---:|---:|---:|---|
| naive | — | — | — | Unmeasured |
| locked | 0 | 1059.99 | 4588 | [k6](locked-20261124T053416409569Z.json) · [invariant](locked-20261124T053416409569Z.txt) |
| flashpoint | 0 | 1034.98 | 4696 | [k6](flashpoint-20261124T053433336768Z.json) · [invariant](flashpoint-20261124T053433336768Z.txt) |

Flashpoint throughput divided by locked throughput was **0.9×** (rounded down).

Rates use the interval from the first checkout start to the last checkout response. Displayed rates are truncated to two decimals.
