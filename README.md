# Flashpoint

[![CI](https://github.com/CharlieNotChilly/Flash-Point/actions/workflows/ci.yml/badge.svg)](https://github.com/CharlieNotChilly/Flash-Point/actions/workflows/ci.yml)

A flash-sale checkout engine that never oversells. Thousands of buyers race for limited stock; Flashpoint reserves stock atomically in Redis with expiring holds and idempotency keys, writes orders through a queue, and proves it with load and chaos tests against a naive design and a Postgres row-lock design.

**Stack:** Ruby on Rails, Redis (Lua), PostgreSQL, Sidekiq, k6

## Results

All numbers come from files in [`results/`](results/). Hardware: _[fill in CPU, RAM, OS]_. App, databases, and k6 run on the same machine, so compare designs relative to each other.

### Load test: 5,000 concurrent buyers, 1,000 units, one attempt each

| Design | Oversold units | Throughput (checkouts/s) | p99 checkout (ms) |
|---|---|---|---|
| A. Naive (read, check, write) | | | |
| B. Postgres row lock | 0 | | |
| C. Flashpoint | 0 | | |

Flashpoint throughput vs. row lock: **_×_**

### Chaos: 50 runs, killing Sidekiq or Redis mid-sale

| Runs | Sidekiq kills | Redis kills | Invariant failures | Lost orders | Duplicate orders |
|---|---|---|---|---|---|
| 50 | | | | | |

## How it works

See [docs/DESIGN.md](docs/DESIGN.md) for the architecture, data model, Redis keys, and design decisions.

## Running it

From the repository root, start Docker Desktop or Docker Engine and run:

```sh
docker compose up --build -d --wait
curl -fsS http://localhost:3000/up
docker compose exec web bin/rails runner 'p Product.pluck(:sku, :initial_stock, :stock)'
docker compose logs --tail=5 sweeper
```

On first boot, Rails prepares PostgreSQL and seeds `FLASH-1`. Subsequent boots preserve stock and orders. Sidekiq connects to Redis and the sweeper logs a heartbeat every second. To change Puma concurrency, set `WEB_CONCURRENCY` and `RAILS_MAX_THREADS` when starting Compose.

On a freshly seeded stack, run `test/phase_one_smoke.sh` to check Rails, the seed, Redis durability, Sidekiq registration, and sweeper activity.

Run `docker compose down` to stop the stack. PostgreSQL and Redis store their data in named volumes.

## PostgreSQL checkout baselines

Both endpoints accept a JSON body such as `{"sku":"FLASH-1","qty":1}`. A purchase returns `201` with an `order_id`. Insufficient stock returns `409` with `{"error":"SOLD_OUT"}`.

- **Design A** (`POST /naive/checkout`) reads stock without locking the row and writes the balance calculated in Ruby. Concurrent buyers can both read the same balance.
- **Design B** (`POST /locked/checkout`) reads the product with `SELECT ... FOR UPDATE`. PostgreSQL holds the row lock until the stock update and order insert commit together.

Run the request specs against the test database:

```sh
docker compose exec -e RAILS_ENV=test web bin/rails db:prepare
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Between runs, `docker compose exec web bin/rails checkout:reset` deletes development orders for designs A and B and restores each product’s stock to its initial value.

Run `bin/load_test locked` and `bin/load_test flashpoint` sequentially from the host. Each command starts a fresh local Compose project, runs k6, checks persisted orders against successful HTTP checkouts, and removes its temporary containers and volumes. The Flashpoint invariant waits for confirmed orders to drain. Raw k6 summaries and inventory checks share a timestamp in `results/load/`. Run `bin/summarize_load` to regenerate `results/load/summary.md` from the most recent saved evidence for each design.

## Redis reservations

After rebuilding Compose, run `docker compose exec web bin/rails db:seed` once for an existing installation. The seed initializes the Redis allocation for `FLASH-1` and preserves an existing balance. The PostgreSQL and Redis allocations belong to separate benchmark designs.

`POST /reserve` accepts `sku` and a positive integer `qty` and returns a hold ID and an expiry in Unix epoch milliseconds. `HOLD_TTL_SECONDS` controls the reservation lifetime (default 60 seconds). Send the hold ID as `hold_id` to `POST /confirm` or `POST /release`. Confirmation at or after the deadline returns `410 HOLD_EXPIRED`. A successful confirmation adds the hold to `confirmed:pending`. Release restores stock for a held reservation exactly once. The sweeper returns expired stock every second. Sidekiq writes confirmed orders to PostgreSQL and removes their pending entries after commit. The sweeper re-enqueues confirmations that have been pending for more than five seconds. On startup, the web service rebuilds a missing Redis stock balance before Puma accepts requests.

After traffic stops, run `docker compose exec web bin/check_invariant flashpoint` to wait for pending writes and check Redis stock, active holds, and committed Flashpoint orders. The default invocation still checks the PostgreSQL checkout baselines.

Use one `Idempotency-Key` header value per checkout attempt. Send the same key on reserve, confirm, and retries of either request. Repeated reserves return the original hold ID and deadline (or the original sold-out response). Repeated confirmations return the same pending response. Replaying a released reservation returns its original receipt and leaves the stock available.

## Project docs

- [docs/SPEC.md](docs/SPEC.md): acceptance criteria
- [docs/DESIGN.md](docs/DESIGN.md): architecture and decisions
- [docs/PLAN.md](docs/PLAN.md): build phases
