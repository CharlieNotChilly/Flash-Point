# Flashpoint

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

_Filled in during phase 1._

```sh
docker compose up
bin/load_test flashpoint
bin/chaos --runs 50
```

## Project docs

- [docs/SPEC.md](docs/SPEC.md): acceptance criteria
- [docs/DESIGN.md](docs/DESIGN.md): architecture and decisions
- [docs/PLAN.md](docs/PLAN.md): build phases
