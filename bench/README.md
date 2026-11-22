# bench: chain vs single-agent baseline (Antigravity)

Measures whether the `team-develop` chain beats a single `developer` agent on six tiny Rust and TypeScript tasks. Runs on demand through `agy -p` (never in CI: it consumes model quota/credits).

## Run

```bash
bench/run.sh --init                  # once, free: creates isolated bench state dir and marker
bench/selftest.sh                    # free: proves run.sh guards and score.sh invariants
bench/run.sh --check                 # free: verifies the bench state dir is pristine
bench/run.sh --probe --yes-spend     # quick paid check of harness assumptions
bench/run.sh --yes-spend             # all tasks, both arms, then prints the metrics table
bench/run.sh rust-bug --arm chain --yes-spend --plugin-dir /path/to/other/dev-agents
```

Every paid invocation refuses to start without `--yes-spend`.

Requirements: `agy` (Antigravity CLI), `jq`, `git`, `cargo`, and Node 22.18+ (TypeScript fixtures use built-in type stripping, no external dependencies).

## Arms

- **chain**: `/team-develop <task>` with `chain-preamble.md` prepended to the prompt (no interactive questions, stop after the local commit, print an `OUTCOME:` line).
- **single**: `agy --agent developer` with the same task text and autonomous single-agent instructions.

Every arm runs in its own fresh `mktemp -d` workspace scaffolded from `tasks/<task>/fixture/`, with the plugin under test staged into `<workspace>/.agents/plugins/dev-agents/` so no path points into the repository and the host's global plugins are not modified. Hidden tests live in `tasks/<task>/hidden/` (carrying `BENCH-HIDDEN-CANARY`) and are copied into a throwaway copy only during `score.sh`.

## Tasks

| Task | Expected outcome | Tests the chain on |
|---|---|---|
| `rust-bug` | `changed` | known root cause (even-length median) |
| `ts-scope-creep` | `changed` | hidden test pins exported API; extras fail it |
| `rust-no-change` | `no_change` | reported panic that does not exist |
| `ts-impossible` | `blocked` | visible test contradicts documented behaviour |
| `rust-edge-case` | `changed` | feature with seeded edge case (reversed range) |
| `ts-second-bug` | `changed` | second known-root-cause bug (dropped trailing chunk) |

## Metrics

`score.sh <run-dir>` prints one row per task and arm: hidden-test pass; outcome vs `expect`; reviewer fix rounds (chain only); critic/reviewer finding precision (chain only); and diff size against `reference.diff`.
