# Flashpoint Spec (the contract)

This file turns each résumé bullet into acceptance criteria. **The code must satisfy every criterion before the matching bullet goes on a résumé.** If the code and this spec disagree, fix the code or change the bullet. Never leave them out of sync.

## Résumé bullets

```latex
\resumeProjectHeading
  {Flashpoint -- Flash-Sale Checkout Engine}{Ruby on Rails, Redis, PostgreSQL, Sidekiq, k6}
\resumeItemListStart
  \resumeItem{Built a flash-sale checkout engine that reserves stock atomically with \textbf{Redis Lua} scripts, expiring holds, and idempotency keys, so concurrent buyers can never oversell.}
  \resumeItem{Load-tested \textbf{5,000} concurrent buyers on 1,000 units: a naive read-check-write design oversold \textbf{[X]} units, Flashpoint \textbf{0}, at \textbf{[Y]$\times$} the throughput of Postgres row locking and \textbf{[Z] ms} p99.}
  \resumeItem{Verified \textbf{0} lost or duplicate orders across \textbf{50} chaos runs that killed Sidekiq workers and Redis mid-sale, using durable Redis persistence, a queue-backed order writer, and an end-to-end stock invariant check.}
\resumeItemListEnd
```

`[X]`, `[Y]`, `[Z]` are **measured**, never chosen. Fill them only from files in `results/`.

**Early-stage version** (true once bullet 1 criteria pass; use if applying before load and chaos tests are done):

```latex
\resumeItem{Built a flash-sale checkout engine that reserves stock atomically with \textbf{Redis Lua} scripts, expiring holds, and idempotency keys, so concurrent buyers can never oversell.}
\resumeItem{Persisted confirmed orders through a \textbf{Sidekiq} queue into PostgreSQL, with a unique idempotency constraint and an end-to-end stock invariant check.}
```

## Fixed parameters (do not change without changing the bullets)

| Parameter | Value |
|---|---|
| Stock per test | **1,000** units of one product |
| Concurrent buyers | **5,000** k6 virtual users, each making **exactly one** checkout attempt, all starting together |
| Quantity per attempt | 1 |
| Chaos runs | **50** |
| Chaos targets | Sidekiq worker and Redis (both must be killed across the 50 runs) |
| Redis durability | AOF on, `appendfsync always` |
| Hardware | One machine for app, databases, and k6; record CPU and RAM in `results/` |

## Bullet 1: atomic reservations

| ID | Criterion | How it is verified |
|---|---|---|
| F1.1 | Reserving stock is one Redis Lua script that checks `stock >= qty`, decrements, and creates the hold in a single atomic call | Code review of `reserve.lua`; spec test |
| F1.2 | Holds expire after a configurable TTL (default 60 s) and their stock is returned | Test: reserve, never confirm, advance time or wait, stock is restored |
| F1.3 | Confirming an expired hold fails with `HOLD_EXPIRED` and creates no order | Test |
| F1.4 | The same `Idempotency-Key` sent twice (sequentially **and** concurrently) produces exactly one hold and at most one order, and returns the same response | Test |
| F1.5 | Many threads reserving against small stock never drive stock below 0 | Concurrency test: 50 threads, stock 10 → exactly 10 holds |

## Bullet 2: load test

| ID | Criterion | How it is verified |
|---|---|---|
| F2.1 | Three designs exist: **A naive** (read, check, write, no lock), **B row lock** (`SELECT ... FOR UPDATE`), **C Flashpoint** | Endpoints exist; README describes each |
| F2.2 | One k6 script runs all three designs with the fixed parameters above | `load/checkout.js` with a `DESIGN` env var |
| F2.3 | Naive design oversells (`orders > 1,000`) under the test. If it reports 0, the app is not running concurrently; fix Puma workers/threads before recording anything | `bin/check_invariant` output for A |
| F2.4 | B and C oversell **0** | `bin/check_invariant` for B and C |
| F2.5 | **Throughput** = 5,000 checkout attempts ÷ wall-clock seconds from first request to last response. `[Y]` = throughput(C) ÷ throughput(B), rounded down to one decimal | k6 summary JSON for B and C |
| F2.6 | **p99** = 99th percentile of one buyer's full checkout (C: reserve + confirm; B: single request), from k6. `[Z]` is C's p99 in ms | k6 summary JSON for C |
| F2.7 | Raw k6 JSON for every run is saved in `results/load/` | Files exist |

## Bullet 3: chaos

| ID | Criterion | How it is verified |
|---|---|---|
| F3.1 | `bin/chaos` starts a Flashpoint load run, kills a random target (Sidekiq or Redis) at a random time, restarts it, waits for k6 and the queue to drain, then runs the invariant | Script exists |
| F3.2 | Across the 50 runs, Sidekiq is killed at least 15 times and Redis at least 15 times | Chaos summary |
| F3.3 | Invariant passes on **all 50** runs: `initial_stock = remaining_stock + active_hold_qty + order_qty`, and `count(orders) = count(distinct idempotency_key)` | `results/chaos/summary.json` |
| F3.4 | Orders that were confirmed but never written (for example, because Sidekiq was killed mid-job) are re-enqueued by the reconciler and written exactly once | Covered by F3.3; unit test for the reconciler |
| F3.5 | If any run fails, fix the bug and rerun **all 50**. Never report "0" from a partial set | Single summary file covering 50 consecutive runs |

## Stack line

Only list technologies the repo actually uses: Ruby on Rails, Redis, PostgreSQL, Sidekiq, k6.
