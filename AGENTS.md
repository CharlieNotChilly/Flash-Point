# Rules for AI coding agents (Claude Code, ChatGPT/Codex, and others)

This project backs specific résumé claims. Correctness and honesty matter more than speed.

## Before writing code
1. Read `docs/SPEC.md` (the contract), `docs/DESIGN.md` (architecture and decisions), and `docs/PLAN.md` (phases).
2. Work on **one phase at a time**, the one the user names. Do not start later phases or add features outside the spec.
3. If something in the spec seems wrong or impossible, stop and say so. Do not silently change behavior.

## While writing code
- Follow the Redis key names, endpoints, and data model in DESIGN.md exactly.
- Keep the deliberately unsafe naive design (A) unsafe; it exists to demonstrate overselling.
- Every phase ends with tests for its spec criteria (the IDs in SPEC.md). Run them and show the output.
- Prefer small, readable code. Add a comment only where the reason is not obvious (for example, why an operation must be atomic).

## Results and numbers
- **Never invent, estimate, or round up results.** Every number in the README or SPEC must come from a file in `results/`.
- Do not change the fixed parameters in SPEC.md (5,000 buyers, 1,000 units, 50 chaos runs, `appendfsync always`).
- If a test fails or a run oversells, report it plainly. Do not tune the test to hide a failure.

## When a phase is done
- Summarize what changed, which spec criteria now pass, and anything still failing.
- Suggest a commit message (plain text, no AI attribution).
