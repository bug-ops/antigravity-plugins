---
name: team-develop
description: >-
  Orchestrate Rust, TypeScript, and Luau/Lua development using Antigravity
  specialist subagents: classify the task into one of ten chains, run mandatory
  architect/critic/validation/review gates, coordinate fix-review cycles via
  send_message, and commit/open a PR. Use when asked to start team development,
  implement a feature or bug fix with the full team, or run a spec-driven pipeline.
---

# Team Develop Orchestration

You act as **team lead**. Coordinate specialist subagents via `invoke_subagent` and `send_message` to deliver the task.

> You do NOT implement code yourself. ALL implementation is delegated. If you are about to write or edit a source file — STOP. Spawn the appropriate specialist agent. The only files the lead edits are the changelog, the version field of version manifests (release metadata), `.local/protected-tests` (Step 4.6), and `progress.json` (`task-loop` chain) — never source files or dependency sections of a manifest.

## Preflight

Run this single command via `run_command` before classifying or spawning:

```bash
printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null || echo not-a-git-repo)"
printf 'dirty=%s\n' "$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
for f in Cargo.toml tsconfig.json package.json; do
  printf '%s=%s\n' "$f" "$(test -f "$f" && echo present || echo missing)"
done
if test -f default.project.json -o -f wally.toml -o -f pesde.toml -o -f .luaurc -o -f .luarc.json -o -f selene.toml -o -f stylua.toml; then
  echo 'luau=present'
else
  echo 'luau=missing'
fi
```

Check the output before spawning anything. STOP and tell the user when:

1. Current branch is `main`/`master` — create a feature branch first.
2. `dirty` is not `0` — the working tree must be clean (a `task-loop` resume may carry `progress.json` and the `in_progress` task's files: list them to the user and continue).
3. `Cargo.toml`, `tsconfig.json`, `package.json`, and `luau` are all `missing` — no supported stack at root (for monorepos with manifests in subdirectories, ask the user which stack to pass).

**Stack**: derive `{stack}` from the markers — `Cargo.toml` → `rust`; `tsconfig.json` or `package.json` → `typescript`; `luau=present` → `luau`; several → comma-separated (`rust,typescript`; a roblox-ts project is `typescript,luau`). Narrow it when the task clearly touches one language only. State it next to the detected chain in Step 0; every spawn prompt carries `Stack: {stack}`, so subagents skip their own detection.

> For complex features that need a written spec before any code: pick the `spec-driven` chain in Step 0 — `team-develop` runs the SDD pipeline end-to-end (`architect → critic → sdd-orchestrator → reviewer → follow-up issue`) and produces a versioned spec under `specs/{feature-slug}/`. Run `/sdd` standalone only outside a team. Existing spec sources, in order: a committed package under `specs/`, a `## Specification` section in the issue body (continuous-improvement findings), or a local draft under `.local/specs/`.

## Step 0: Classify Task

Before any subagent spawns, classify the task and confirm with the user. Never default silently to the full pipeline.

| Signal in task text | Type | Pipeline |
|---|---|---|
| "fix", "bug", "broken", "panic", "regression", crash, stack trace, `file:line` reference | `bug-fix` | [Workflow: Bug Fix](#workflow-bug-fix) |
| "refactor", "rename", "extract", "restructure", "cleanup", "move module" (behavior preserved) | `refactoring` | [Workflow: Refactoring](#workflow-refactoring) |
| "vulnerability", "CVE", "RUSTSEC", "GHSA", "npm audit", "audit", "unsafe review", credential leak | `security` | [Workflow: Security](#workflow-security) |
| "docs", "README", "mdBook", "doc comment", "rustdoc", "TSDoc", "user guide", "API reference" | `docs` | [Workflow: Documentation](#workflow-documentation) |
| "bump", "update dependency", `cargo update`, `npm update`, `pnpm update`, `wally install`, `pesde update`, lockfile changes | `dependency` | [Workflow: Dependency Bump](#workflow-dependency-bump) |
| "optimize", "speed up", "reduce allocations", "profile", "benchmark", "hot path", latency/throughput numbers | `performance` | [Workflow: Performance](#workflow-performance) |
| "CI", "GitHub Actions", "workflow", `justfile`, `clippy.toml`, `rustfmt.toml`, `.cargo/config.toml`, `eslint.config.*`, `tsconfig.json`, `biome.json`, `selene.toml`, `stylua.toml`, `rokit.toml` | `ci-cd` | [Workflow: CI/CD](#workflow-cicd) |
| "implement", "add", "build", "design", new module/crate/package, greenfield | `new-feature` | Full pipeline (Steps 1–10 below) |
| "implement the tasks of", "task by task", "one task per session", a `tasks.md` or `specs/{slug}/` path to implement | `task-loop` | [Workflow: Task Loop](#workflow-task-loop) |
| "spec", "specification", "design doc", "RFC", "proposal", "BRD", "SRS", "NFR", "blueprint", "feasibility", "design only", "spec only", "draft a spec" | `spec-driven` | [Workflow: Spec-Driven](#workflow-spec-driven) |
| Task already lists concrete required changes (file paths, exact edits) | reduce one level | Skip the lead agent (`architect`/`debugger`/`security`/`perf`) — start from `developer` in the matching chain |
| Ambiguous / multiple signals | see rules below | — |

State the detected type, stack, and matching pipeline, then **wait for confirmation** via `ask_question` (putting the detected chain first with `(Recommended)`, plus runner-up if any, plus `new-feature` unless already listed). In headless runs where `ask_question` is unavailable, ask in text or follow benchmark overrides.

### Mixed-Signal Rule

1. **Identify the goal verb** — the outcome, not the means. "Refactor parser to fix panic" → `bug-fix`; "Update tokio to patch RUSTSEC-..." → `security`.
2. **Tie on goal verb** → pick the heavier chain: `docs < ci-cd < dependency < bug-fix < refactoring < performance < security < new-feature`.
3. **`task-loop`** applies only when implementing an approved spec/`tasks.md` task by task.
4. **`spec-driven`** applies when the user asks for a spec/RFC/design doc, or scope outgrows a single implementation pass.
5. **Still ambiguous** → offer candidates via `ask_question`.

### Escalation Rule

If a specialist reports a finding that breaks the chosen chain's assumptions (e.g. debugger finds an architectural defect, refactoring breaks behavior, perf requires structural change, or architect cannot collapse design into one pass), STOP the chain:

1. Terminate idle subagents via `manage_subagents(Action: "kill", ...)`. Re-spawned chains use `-2` suffixes on teammate names per `team-lead`.
2. Summarize the finding to the user.
3. Propose upgrading/downgrading the chain and wait for confirmation via `ask_question` before spawning again.

### No-Change Outcome

A `no_change_needed` handoff (from `architect` or `debugger`, with `## Evidence`) stops the chain immediately. Terminate any active subagents, report the evidence to the user, and create no commits or PR.

## Step 1: Load the Lead Protocol

Read `../team-lead/SKILL.md` and follow it for `invoke_subagent`, reactive wakeup, `send_message`, naming, workspace modes, and `manage_subagents` shutdown.

## Step 2: Task Graph (New Feature)

Track these stages and their dependencies in your lead checklist:

| Stage | Task | Owner (`TypeName`) | Blocked by |
|---|---|---|---|
| 1 | `plan` | `architect` | — |
| 2 | `critique` | `critic` | `plan` |
| 3 | `approve-plan` | team-lead (`ask_question`) | `critique` |
| 4 | `acceptance-tests` | `tester` (`testing-engineer`) | `approve-plan` |
| 4 | `verify-contract` | `live-tester` (if runnable surface) | `approve-plan` |
| 5 | `implement` | `developer` (or `developer-a`, `developer-b`, ...) | `acceptance-tests` |
| 6 | `validate-tests` | `tester` (`testing-engineer`) | `implement` |
| 6 | `validate-live` | `live-tester` (if `verify-contract`) | `implement`, `verify-contract` |
| 6 | `validate-perf` | `perf` (`performance-engineer`) | `implement` |
| 6 | `validate-security` | `security` (`security-maintenance`) | `implement` |
| 6 | `validate-critique` | `impl-critic` (`critic`, MANDATORY) | `implement` |
| 7 | `review` | `reviewer` (`code-reviewer`) | all Stage 6 validators |
| 8 | `fix-issues` / `re-review` | `developer` ↔ `reviewer` | `review` |
| 8.5 | `sync-spec` | `sdd-orchestrator` (if committed `specs/`) | `re-review` |
| 9 | `commit` | team-lead | `re-review`, `sync-spec` |

Skip optional stages (`approve-plan` when exact changes were given, `verify-contract`/`validate-live` for libraries with no runnable surface, `sync-spec` when no committed `specs/` package applies).

## Spawn Template & Ownership

Every spawn prompt starts with the `team-lead` spawn template (`{template}`), filled for this run:

- **Teammates**: the names this chain spawns (`architect, critic, developer, tester, perf, security, impl-critic, reviewer`, plus `live-tester` and `sdd-orchestrator` when active; `developer-a, developer-b, ...` for parallel tracks).
- **Peers**: `developer → architect: approval request for an addition beyond the plan; anything widening requested scope goes to the lead` (chains without an architect: `none — report to the lead only`).
- **Code ownership** by chain:
  - `only developer edits source` (new-feature, bug-fix, refactoring, security, dependency, performance; parallel developers edit only their assigned track's files; dependency manifests/lockfiles belong to one named track).
  - `only writer edits docs and doc comments` (`docs`).
  - `only cicd edits workflows and tooling config` (`ci-cd`).
  - `spec-driven` has its own ownership line below.
  - Step 8.5: `sdd-orchestrator edits only the files of the spec package`.

**Fix routing**: messages to "the developer" go to the owning `developer` / `developer-{track}` (or `writer`, `cicd`, `sdd-orchestrator` in their chains) via `send_message` using its stored `conversationId`.

| Agent (`TypeName`) | Teammate name |
|---|---|
| `architect`, `debugger`, `sdd-orchestrator`, `live-tester` | same as `TypeName` |
| `developer` | `developer`; `developer-a`, `developer-b`, ... for parallel tracks |
| `critic` | `critic` on a plan, `impl-critic` on an implementation |
| `testing-engineer` | `tester` |
| `performance-engineer` | `perf` |
| `security-maintenance` | `security` |
| `code-reviewer` | `reviewer` |
| `tech-writer` | `writer` |
| `cicd-devops` | `cicd` |

On every handoff with `follow_ups > 0`, record its path in your follow-up list for Step 7.

## Step 2.5: Clarify (`new-feature` and `spec-driven`)

Before spawning `architect`, scan the task and `{spec}` for high-impact gaps across scope boundaries, data/state, error behavior, NFR targets, integrations, and acceptance. Ask at most four multiple-choice questions in one `ask_question` call (recommended option first). Skip when no gap ranks high or exact changes are already given. Pass answers in `Clarifications:`.

## Step 3: Architect

Look for a matching spec in `specs/`, the issue body (`## Specification`), or `.local/specs/`. Record it as `{spec}` (if found) and pass it in every later `Requirement source:` and developer prompt.

```text
invoke_subagent(
  TypeName: "architect",
  Role: "architect — design architecture",
  Prompt: "{template}\n\nDesign architecture for: {feature-description}\n\nSpec: {spec}\n\nClarifications: {answers from Step 2.5, or none}"
)
```

Wait for the handoff frontmatter + path. A `no_change_needed` status ends the chain (No-Change Outcome).

## Step 4: Critic (MANDATORY)

```text
invoke_subagent(
  TypeName: "critic",
  Role: "critic — adversarial architecture critique",
  Prompt: "{template}\n\nCritique the architecture, including plan scope against the request (dimension 9), and assess the Follow-ups entries in the handoffs. Report findings — do NOT write code.\n\nRequirement source: {feature-description, issue numbers, spec path}\n\nHandoffs:\n{accumulated frontmatters}"
)
```

Wait for `critic`. First settle scope: every item marked `needs user approval` or `obtain user approval` goes to the user via `ask_question` (keep or drop). Then check `verdict`:
- `critical` or `significant` → resume `architect` via `send_message` with the critic handoff and user scope decisions for redesign, then resume `critic` via `send_message` to re-run critique. At most 3 critique rounds; if round 3 still returns `critical`/`significant`, ask the user via `ask_question` (continue, accept as is, or stop).
- `approved` or `minor` → send any user scope decisions to `architect` to record in the plan, then proceed to Step 4.5.

**Evidence check** (here, in Step 6 for `impl-critic`, and in Step 8 for `reviewer`): before relaying a CRITICAL or SIGNIFICANT correctness finding about existing code, verify its `evidence` field by re-running the stated command or reproducer. Without valid evidence, ask the author once via `send_message` to supply evidence or withdraw; otherwise demote to Question for Authors.

## Step 4.5: Plan Approval (`new-feature`)

After the critic gate passes and scope is settled, show the user a one-screen summary (goal, approach, files, contracts, out of scope, risks, architect's size estimate) and confirm via `ask_question`: `(Recommended) Approve`, `Adjust` (routes back to `architect` + re-runs `critic`), or `Stop`. If the architect's estimate exceeds the 4-point review budget (per `triage-and-solve`), offer splitting into stacked PRs as an extra option. Skip when the task already lists exact changes.

## Step 4.6: Acceptance Tests and Verification Contract (`new-feature`, or any developer chain with `{spec}`)

Spawn `testing-engineer` (`tester`), and in parallel `live-tester` when the project has a runnable surface (CLI, server, web app, Roblox Open Cloud probes):

- **Acceptance tests (`tester`)**:
  `Code ownership: tester creates and edits only the acceptance test files it lists; developers edit source. Only the team lead commits.`
  Prompt: tests-first mode from acceptance criteria and plan Contracts, dedicated test files only (no in-module tests), list every test with its expected failure reason.
- **Stubs**: when tests target a new public API that does not compile yet, spawn/resume the owning `developer` for stub-only empty signatures (`todo!()`, `throw new Error("not implemented")`, etc.), then `send_message` `tester` to confirm each test compiles and fails for its listed reason.
- **Protect tests**: the lead commits the acceptance tests + stubs locally (must pass format/lint; never pushed red) and writes `.local/protected-tests` listing the dedicated test files (one repo-relative path per line; never list stubs). The plugin's `PreToolUse` hook (`scripts/guard.sh`) blocks edits to listed paths automatically. Delete `.local/protected-tests` when the chain ends (commit, stop, or escalation).
- **Verification contract (`live-tester`)**: writes `.local/testing/contracts/{slug}.md` with runnable scenarios and pass criteria (skip for pure libraries).

## Step 5: Developer(s)

Decide whether implementation splits into independent subtasks (separate modules/packages, no shared mutable state, no cross-task type dependencies, testable in isolation) or follows tracks supplied by `/solve-issue`:

- **Independent tracks**: spawn `developer-a`, `developer-b`, ... in parallel (using `Workspace: "inherit"` with strict non-overlapping file ownership; dependency manifests/lockfiles belong to one named track; changelog & version fields stay with the lead). Pass `Protected tests: <paths>` in every prompt. Wait for all parallel developers and accumulate handoffs.
- **Dependent / single track**: spawn `developer` (or resume via `send_message` if already spawned for Step 4.6 stubs) with plan, `{spec}`, and protected test paths. Wait for handoff.

## Step 6: Parallel Validation (spawn all simultaneously)

Launch all validators in a single turn (resume `tester` and `live-tester` via `send_message` if spawned in Step 4.6, otherwise `invoke_subagent`):

1. `tester` (`testing-engineer`) — validate test coverage & run redundancy audit (report only).
2. `perf` (`performance-engineer`) — analyze performance (report only).
3. `security` (`security-maintenance`) — security audit (report only).
4. `impl-critic` (`critic`, MANDATORY) — two-pass implementation critique (first diff vs requirement source, then handoffs for deviations/scope conformance dimension 9 + follow-up assessment).
5. `live-tester` (if `verify-contract` exists) — execute the contract in `.local/testing/contracts/` against the built artifact.

Wait for ALL validator handoffs. A failed contract criterion blocks review. Apply the Evidence check (Step 4) to `impl-critic`.

- **Follow-up assessment**: if any sibling validator had `follow_ups > 0`, `send_message` those paths to `impl-critic` for Follow-up Assessment and wait for its update.
- **Scope gate**: read `impl-critic`'s Scope Ledger. Route `obtain user approval` to `ask_question`, `obtain architect approval` to `architect` via `send_message` (or user if no architect). Message each owning developer to remove rejected/unapproved items and record approved ones under `Deviations`. Skip when `No untraced items`.

## Step 7: Code Review

```text
invoke_subagent(
  TypeName: "code-reviewer",
  Role: "reviewer — final code review and issue triage",
  Prompt: "{template}\n\nReview implementation. Triage every follow-up and every new TODO/FIXME/HACK/XXX marker in the diff, and file the issues (your Follow-up Sources and Filing sections).\n\nRequirement source: {feature-description, issue numbers, spec path}\nFirst pass: review the diff against the requirement source only, and write your findings down before reading any handoff.\nSecond pass: read the handoffs only to filter your findings against scope and recorded deviations.\n\nFollow-ups to triage: {handoff paths with follow_ups > 0, or none}\nCritic follow-up assessments: {critic and impl-critic handoff paths}\n\nHandoffs:\n{all accumulated frontmatters}"
)
```

Wait for `reviewer`'s handoff and apply the Evidence check (Step 4) to CRITICAL/IMPORTANT correctness findings. Private security findings go to the user, never a public issue.

## Step 8: Fix-Review Cycle

Check `verdict` in `reviewer`'s frontmatter:
- CRITICAL and IMPORTANT block approval.
- Out-of-scope SUGGESTION/NITPICK are filed by `reviewer` and open no round.
- In-scope SUGGESTION is fixed or declined with a one-line reason under `Declined Suggestions`.
- In-scope NITPICK never opens a fix round alone (formatter/linter fixes it before commit).

If `verdict: changes_requested`, `send_message` findings (and any filed issue numbers for `TODO(#N)` markers) to the owning developer. Wait for the new handoff. When the fix diff changes logic, `send_message` the fix diff to `impl-critic`, `tester`, and (if active) `live-tester` to re-verify, then `send_message` `reviewer` for re-review (checking only previous findings and the fix diff). Repeat up to 3 rounds; if still `changes_requested`, ask the user via `ask_question` (continue, accept, or stop).

## Step 8.5: Spec Sync (when `{spec}` is a committed `specs/` package)

After `reviewer` approves, spawn/resume `sdd-orchestrator` with all approved `Deviations`, Scope Ledger approvals, and completed tasks. It applies the delta per `sdd`'s Delta Model, archives it under `changes/archive/`, and checks off completed tasks in `tasks.md`.

## Step 9: Commit and PR

Only after `reviewer` approves and Step 8.5 finishes. Delete `.local/protected-tests` if present. If approved handoff lists formatter-fixable NITPICKs, have the developer run the formatter/linter first (no re-review). Read `.agents/rules/commits-and-issues.md` if present.

Verify the full check suite (or `.agents/skills/verify/SKILL.md` "Before a commit") has passed on the exact final diff, then commit, push, and open the PR:

```bash
git add <explicit paths>
git commit -m "$(cat <<'EOF'
type(scope): description

Body if needed.
EOF
)"
git push -u origin {branch}
gh pr create --title "..." --body "..."
```

Close each solved GitHub issue with its own `Closes #{number}` line, list filed follow-up issues under `Follow-up issues`, and link each back with `gh issue comment N --body "Found while working on #<PR>"`.

## Step 10: Shutdown

Terminate finished subagents with `manage_subagents(Action: "kill", ...)` as soon as no later step needs them. Keep `architect`, `developer`(s)/chain owners, `impl-critic`, `tester`, active `live-tester`, and `reviewer` alive until commit; keep plan `critic` alive until Step 4.5 approval. After commit, terminate all remaining subagents.

## Handoff Accumulation

Pass inline frontmatter to each subsequent agent — no file reads for routing:

```text
After architect:    [architect]
After critic:       [architect, critic]
After developer(s): [architect, critic, developer-a, developer-b, ...]
After validators:   [architect, critic, developer(s), tester, perf, security, impl-critic]
Reviewer gets all of the above.
```

## Workflow Templates (Reduced Chains)

When Step 0 classifies the task into a reduced chain (`bug-fix`, `refactoring`, `security`, `docs`, `dependency`, `performance`, `ci-cd`, or `spec-driven`), read [chains.md](references/chains.md) before spawning anything. Every chain in which `developer` edits code enforces the mandatory `impl-critic` gate before review.

### Workflow: Task Loop

`lead (smoke test) → tester (acceptance tests) → developer-t{NNN} → lead (checks, commit, progress.json) → per group: (tester, impl-critic, reviewer)`. Implements an approved `specs/{slug}/tasks.md` one task per fresh developer subagent. Read [task-loop.md](references/task-loop.md) before spawning anything in this chain.
