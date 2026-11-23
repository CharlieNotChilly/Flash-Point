# Flashpoint Design

## Problem

In a flash sale, thousands of buyers try to buy limited stock in the same second. A naive checkout does:

```
stock = read(product.stock)
if stock >= qty:
    write(product.stock = stock - qty)
    create order
```

Two buyers can both read `stock = 1`, both pass the check, and both buy. The store oversells. Flashpoint compares three designs and proves the third is correct, fast, and survives crashes.

| Design | How it works | Expected result |
|---|---|---|
| **A. Naive** | Read, check, write; no locking | Oversells |
| **B. Row lock** | `SELECT ... FOR UPDATE` on the product row in a transaction | Correct, but buyers queue on one row |
| **C. Flashpoint** | Atomic Redis Lua reservations, expiring holds, idempotency keys, queue-backed order writes | Correct and faster than B |

## Architecture (design C)

```
k6 (5,000 virtual buyers)
        │
        ▼
Rails API (Puma: several workers × threads)
  POST /reserve  ──► Redis Lua reserve.lua   (check + decrement + create hold, atomic)
  POST /confirm  ──► Redis Lua confirm.lua   (validate hold, mark confirmed, add to confirmed:pending)
                       └─► enqueue Sidekiq PersistOrderJob
  POST /release  ──► Redis Lua release.lua   (return stock, delete hold)

Sidekiq: PersistOrderJob ──► PostgreSQL orders (unique idempotency_key), then SREM confirmed:pending
Sweeper process (every 1 s):
  - expire.lua: return stock for holds past their expiry
  - reconcile: re-enqueue PersistOrderJob for any hold in confirmed:pending older than 5 s

Redis: AOF on, appendfsync always (durable before replying)
```

## Data model

### PostgreSQL

| Table | Columns |
|---|---|
| `products` | `id`, `sku` (unique), `name`, `initial_stock`, `stock` (used only by designs A and B) |
| `orders` | `id`, `product_id`, `quantity`, `idempotency_key` (**unique**), `hold_id` (unique), `design` (`naive`/`locked`/`flashpoint`), `created_at` |

### Redis keys

| Key | Type | Purpose |
|---|---|---|
| `stock:{sku}` | integer | Units available to reserve |
| `hold:{hold_id}` | hash: `sku`, `qty`, `idem_key`, `state` (`held`/`confirmed`) | One reservation |
| `holds:expiry:{sku}` | sorted set: member `hold_id`, score = expiry epoch ms | Lets the sweeper find expired holds |
| `idem:{key}` | string → `hold_id` | Returns the original result for a retried request |
| `confirmed:pending` | sorted set: member `hold_id`, score = confirm time | Confirmed but not yet written to Postgres |

## Key decisions (be ready to defend these)

1. **Redis Lua over `WATCH/MULTI`.** A Lua script runs atomically and can branch ("only decrement if enough stock"). `WATCH/MULTI` aborts and retries under contention, which collapses under thousands of buyers.
2. **Redis over a Postgres row lock.** A row lock serializes every buyer on one row and holds a database connection while waiting. Redis does the check-and-decrement in microseconds in memory.
3. **Expiry by sorted-set score, not key TTL.** If a hold key silently expired, its stock would be lost. The sweeper reads the sorted set and returns stock atomically in `expire.lua`.
4. **`appendfsync always`.** Every write is on disk before Redis replies, so killing Redis can't lose a reservation or confirmation. It costs throughput; the alternative `everysec` can lose up to one second of writes.
5. **Reconciler for lost Sidekiq jobs.** Free Sidekiq loses a job that's in progress when its worker is killed. Every confirmed hold sits in `confirmed:pending` until its order is committed, and the sweeper re-enqueues any that are older than 5 seconds. `PersistOrderJob` is idempotent thanks to the unique `idempotency_key` and `hold_id`, so a job that runs twice still writes one order.
6. **Startup reconciliation.** On boot, if `stock:{sku}` is missing, rebuild it as `initial_stock - orders - active holds` before accepting traffic.

## Correctness invariant

After k6 finishes and `confirmed:pending` is empty:

```
initial_stock = stock:{sku} + sum(qty of active holds) + sum(qty of orders in Postgres)
count(orders) = count(distinct idempotency_key)
```

`bin/check_invariant` checks both and exits non-zero on failure. Every load and chaos run ends with it.

## API

| Endpoint | Body / headers | Response |
|---|---|---|
| `POST /reserve` | `sku`, `qty`; header `Idempotency-Key` | `201 {hold_id, expires_at}` or `409 SOLD_OUT` |
| `POST /confirm` | `hold_id`; header `Idempotency-Key` | `202 {status: "pending"}` or `410 HOLD_EXPIRED` |
| `POST /release` | `hold_id` | `204` |
| `GET /products/:sku` | | `{stock, held, sold}` |
| `POST /naive/checkout` | `sku`, `qty` | Design A |
| `POST /locked/checkout` | `sku`, `qty` | Design B |

## Interview questions

1. Why not just lock the row in Postgres? (Use your measured B vs. C numbers.)
2. Why a Lua script instead of `MULTI/EXEC`?
3. What happens if Redis crashes after a reservation but before the order is written?
4. What if a Sidekiq job runs twice, or never runs?
5. Why sorted-set expiry instead of key TTL?
6. How would you scale to 100× buyers or many products? (Shard by SKU, Redis Cluster with hash tags, split hot-SKU stock into buckets, partitioned queues.)
7. What does `appendfsync always` cost you, and when would you pick `everysec`?
8. What was the hardest bug? (Keep notes as you build.)
