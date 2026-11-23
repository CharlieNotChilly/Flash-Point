# Flashpoint Build Plan

Work **one phase at a time**. Give the AI the phase prompt, check the "done when" line yourself, commit, then move on. Phases 4, 6, and 8 contain the real engineering: read and understand that code before continuing.

Spec IDs (F1.1, F2.3, …) refer to [SPEC.md](SPEC.md).

| # | Phase | Done when | Covers |
|---|---|---|---|
| 1 | Skeleton | `docker compose up` runs Rails, Postgres, Redis (AOF, `appendfsync always`), Sidekiq, and the sweeper; seed creates one product with 1,000 units | — |
| 2 | Designs A and B | `/naive/checkout` and `/locked/checkout` work for one buyer; request specs pass | F2.1 |
| 3 | Invariant + k6 | `bin/check_invariant` works; `load/checkout.js` runs 5,000 VUs × 1 attempt against A and B; A oversells | F2.2, F2.3 |
| 4 | Lua reservations | `reserve.lua`, `confirm.lua`, `release.lua` with Ruby wrappers and endpoints; unit and concurrency tests pass | F1.1, F1.3, F1.5 |
| 5 | Idempotency | Sequential and concurrent duplicate-key tests pass | F1.4 |
| 6 | Order writer, expiry, reconciler | `PersistOrderJob`, `expire.lua`, sweeper loop with reconcile, startup reconciliation; tests pass | F1.2, F3.4 |
| 7 | Load test C | k6 against Flashpoint: 0 oversold; results for A, B, C saved | F2.4–F2.7 |
| 8 | Chaos | `bin/chaos --runs 50` passes all 50 with the required kill mix; summary saved | F3.1–F3.5 |
| 9 | CI | GitHub Actions: unit tests, invariant test, small k6 smoke run (e.g., 200 VUs) | — |
| 10 | Write-up | README results tables filled from `results/`; architecture diagram; 60-second demo video | — |

At the end of **phase 6**, the early-stage bullets in SPEC.md are true. At the end of **phase 8**, the full bullets can be filled from `results/`.

---

## Phase prompts

Start every session with: *"Read AGENTS.md, docs/SPEC.md, and docs/DESIGN.md first. We are on phase N."*

### Phase 1: Skeleton
```
Create a Rails 8 API-only app named flashpoint with PostgreSQL, Redis, and
Sidekiq, all running via Docker Compose. Redis must use AOF with
appendfsync always (pass the config in docker-compose.yml). Add services:
web (Puma, 4 workers x 5 threads, configurable via env), sidekiq, sweeper
(a long-running Ruby process, bin/sweeper, that for now just logs every
second), postgres, redis. Add Product (sku unique, name, initial_stock,
stock) and Order (product_id, quantity, idempotency_key unique, hold_id
unique nullable, design string). Seed one product sku=FLASH-1 with
initial_stock=1000 and stock=1000. No authentication, no UI. Add a README
section on how to run it.
```

### Phase 2: Designs A and B
```
Add POST /naive/checkout: read product.stock, if stock >= qty set
stock = stock - qty using the value read in Ruby (deliberately not atomic),
then create an Order with design=naive and a generated idempotency key.
Add POST /locked/checkout: same logic inside a transaction using
Product.lock.find (SELECT ... FOR UPDATE), design=locked. Return 201 on
success and 409 SOLD_OUT otherwise. Add request specs for one buyer each.
Add a rake task to reset stock and delete orders for a fresh test run.
```

### Phase 3: Invariant and k6
```
Write bin/check_invariant that, for sku FLASH-1, prints initial_stock,
remaining stock, active hold qty (0 for designs A and B), and order qty, and
exits non-zero if initial_stock != remaining + holds + orders or if any
idempotency_key repeats. Also print oversold = max(0, order_qty - initial_stock).
Write load/checkout.js for k6: scenario per-vu-iterations with vus=5000,
iterations=1, all starting together; env DESIGN=naive|locked|flashpoint.
For naive and locked, one POST to the design's endpoint. Record a custom
Trend metric checkout_duration for the full checkout. Save the summary with
--summary-export to results/load/<design>-<timestamp>.json.
Write bin/load_test DESIGN that resets data, runs k6, waits for the queue
to drain (later phases), and runs check_invariant, saving its output next
to the k6 summary.
```
Check: run it for `naive`. If oversold is 0, increase Puma concurrency until it oversells; record the setting in the README.

### Phase 4: Lua reservations
```
Implement Redis Lua scripts with the keys in docs/DESIGN.md:
reserve.lua: if stock:{sku} >= qty, DECRBY, create hold:{hold_id} hash with
state=held, ZADD holds:expiry:{sku} with expiry = now + TTL; else return
SOLD_OUT. confirm.lua: if the hold is missing or its expiry score is in the
past, return HOLD_EXPIRED; else set state=confirmed, ZREM from the expiry
set, ZADD confirmed:pending with score = now. release.lua: if the hold is
held, INCRBY stock and delete the hold. Load scripts once and call with
EVALSHA, falling back to EVAL on NOSCRIPT. Pass time in from Ruby as an
argument so tests can control it. Add POST /reserve, /confirm, /release.
Add specs for each script, including 50 threads reserving against stock 10
(exactly 10 holds succeed).
```

### Phase 5: Idempotency
```
Require an Idempotency-Key header on /reserve and /confirm. In reserve.lua,
check idem:{key} first and return the existing hold if present; set it
atomically in the same script. Make /confirm return the same response for a
repeated key. Add specs: same key twice sequentially, and 20 concurrent
requests with the same key, each producing exactly one hold.
```

### Phase 6: Order writer, expiry, reconciler
```
Add PersistOrderJob(hold_id): read the hold, insert an Order with the hold's
idempotency_key and hold_id (design=flashpoint) using insert-or-ignore on the
unique keys, then ZREM hold_id from confirmed:pending only after the
transaction commits. /confirm enqueues this job.
Add expire.lua: for holds in holds:expiry:{sku} with score <= now, return
their qty to stock and delete them, atomically.
Make bin/sweeper loop every second: run expire.lua, then re-enqueue
PersistOrderJob for every member of confirmed:pending with score older than
5 seconds. Add startup reconciliation: if stock:{sku} is missing, set it to
initial_stock - orders - active holds. Add specs for the job's idempotency,
expiry returning stock, and the reconciler re-enqueuing a lost job.
Update check_invariant to include active hold qty and to wait until
confirmed:pending is empty (with a timeout) before checking.
```

### Phase 7: Load test design C
```
Extend load/checkout.js for DESIGN=flashpoint: each VU sends /reserve then
/confirm with its own idempotency key; checkout_duration covers both calls.
Run bin/load_test for naive, locked, and flashpoint on the same machine.
Write bin/summarize_load that reads the saved JSON and prints, per design:
oversold units, throughput = 5000 / wall-clock seconds, and p99 of
checkout_duration; and the ratio throughput(flashpoint) / throughput(locked).
Save the table to results/load/summary.md.
```

### Phase 8: Chaos
```
Write bin/chaos --runs N: for each run, reset data, start a flashpoint k6
run in the background, wait a random 1-5 seconds, kill a random target
(sidekiq or redis) with docker compose kill, restart it after a random 1-3
seconds, wait for k6 to finish and confirmed:pending to drain, then run
check_invariant. Record each run's target, timings, and result. Guarantee
at least 15 kills of each target across the runs. At the end write
results/chaos/summary.json and summary.md with totals, and exit non-zero if
any run failed.
```
If any run fails: find the bug, fix it, and rerun all 50.

### Phase 9: CI
```
Add GitHub Actions: run RSpec (with Postgres and Redis services), then a
smoke load test with 200 VUs against flashpoint followed by
check_invariant. Add the status badge to the README.
```

### Phase 10: Write-up
Fill the README results tables from `results/load/summary.md` and `results/chaos/summary.md`, add the architecture diagram from DESIGN.md, and record a 60-second demo showing a load run and a chaos run. Then fill `[X]`, `[Y]`, `[Z]` in SPEC.md from the same files.
