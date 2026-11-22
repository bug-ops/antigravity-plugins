---
name: continuous-improvement
description: >-
  Orchestrate a read-only continuous improvement cycle: spawn live-tester for
  live testing, researcher for dependency monitoring and parity, arch-analyst
  for architecture and code quality, and security-analyst for vulnerability
  scanning. Aggregates findings into a cycle journal. Works interactively,
  headless (agy -p), and via /schedule.
---

# Continuous Improvement Orchestrator

Run a continuous improvement cycle for the current Rust, TypeScript, or Luau/Lua project by coordinating four read-only specialist subagents via `invoke_subagent`:

- **`live-tester`** — executes the built artifact live, detects anomalies and regressions, tracks coverage, files bug issues
- **`researcher`** — monitors dependency health, researches new techniques, tracks competitive parity, files research and dependency issues
- **`arch-analyst`** — audits existing codebase for type system anti-patterns, DRY violations, architectural debt, API naming issues, and async concurrency problems; files improvement issues
- **`security-analyst`** — scans existing codebase for vulnerabilities: dependency advisories, unsafe/escape-hatch code, exposed secrets, injection, crypto misuse, auth, crash-DoS, and supply-chain risk; files security issues

| Focus value | Agents spawned |
|-------------|----------------|
| `testing` | `live-tester` only |
| `dependencies` | `researcher` only (deps phase) |
| `research` | `researcher` only (research phase) |
| `parity` | `researcher` only (parity phase) |
| `arch` | `arch-analyst` only |
| `security` | `security-analyst` only |
| `full` (default) | `live-tester` + `researcher` + `arch-analyst` + `security-analyst` in parallel |

## Hard Rules

1. **NEVER modify source code** in this orchestrator session — delegate all analysis to specialist subagents.
2. **NEVER run live tests, research, or security scans directly** — spawn the appropriate agent.
3. All spawned agents are read-only with respect to source code; they only write under `.local/`.
4. CI sessions never fix anything: every finding, including a symptom without a known root cause, becomes an issue, and fixes run in a separate `/team-develop` session.
5. The orchestrator is the single writer of the cycle journal and `process-notes.md`, the single filer of the cross-agent `testing-infra` issue, and the single collector of `follow_ups`; spawned agents report all of it in their handoffs.
6. `.local/testing/` artifacts live under the **main repository root**, even when the cycle runs from a git worktree; handoffs stay in the current directory's `.local/handoff/`.

## Step 0: Preflight, Sync, and Cycle Journal

Run this single preflight command via `run_command`:

```bash
main_root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" 2>/dev/null || pwd)
printf 'main_root=%s\n' "$main_root"
for f in Cargo.toml tsconfig.json package.json; do
  printf '%s=%s\n' "$f" "$(test -f "$f" && echo present || echo missing)"
done
if test -f default.project.json -o -f wally.toml -o -f pesde.toml -o -f .luaurc -o -f .luarc.json -o -f selene.toml -o -f stylua.toml; then
  echo 'luau=present'
else
  echo 'luau=missing'
fi
printf 'ci_rules=%s\n' "$(test -f .agents/rules/continuous-improvement.md && echo present || echo absent)"
last_journal=$(ls "$main_root/.local/testing/journal/" "$main_root/.local/testing/journal/archive/" 2>/dev/null | grep -E '^ci-[0-9]{3}\.md$' | sort | tail -1 || true)
printf 'last_journal=%s\n' "${last_journal:-none}"
```

STOP if `Cargo.toml`, `tsconfig.json`, `package.json`, and `luau` are all `missing` (for a monorepo with manifests in subdirectories, ask the user which stack to pass).

**Stack**: derive `{stack}` from the markers — `Cargo.toml` → `rust`; `tsconfig.json` or `package.json` → `typescript`; `luau=present` → `luau`; several → comma-separated (`rust,typescript`). Record it in the cycle journal header and pass it in every spawn prompt.

Read `../team-lead/SKILL.md` for spawn, outcome, and shutdown rules. If `.agents/rules/continuous-improvement.md` is present, read it and pass its contents to every spawned agent as project-specific overrides.

Determine the next cycle number from `last_journal`: `none` means `001`; otherwise increment by one. Create `<main_root>/.local/testing/journal/` if it does not exist. A legacy `coverage.md` or `journal.md` is migrated by `live-tester` per [Testing Methodology](../live-testing/references/testing-methodology.md#coverage-status-file).

### Cycle start

Before spawning, sync and decide the cycle mode:

1. Sync per [Phase 1: Sync](../live-testing/SKILL.md#phase-1-sync) — fetch, fast-forward only when on the default branch, never merge it into another branch — and read the new commits.
2. Record `git rev-parse HEAD` as `{head}` and read the previous HEAD from the last journal's `head:` frontmatter or the last handoff.
3. Equal HEADs mean **unchanged-HEAD mode**: the cycle is never skipped. Pass the mode and both SHAs to every agent in its prompt.

| Role | Unchanged-HEAD behavior |
|---|---|
| `live-tester` | Tests the stalest `Untested`/`Partial` rows and `Tested` rows whose dependencies moved |
| `arch-analyst`, `security-analyst` | Audit the modules least recently covered, found in the `Modules audited` lines of prior `journal/ci-*.md` entries for that role |
| `researcher` | Delta check only |

A re-verification with zero findings is a valid cycle outcome.

### Agent outcomes

The `team-lead` outcomes table applies with two overrides: a partial result gets one `Continue` message via `send_message`, then you record what arrived; a failure is recorded in the journal under that agent's section and never re-spawned automatically.

Create the journal at `<main_root>/.local/testing/journal/ci-NNN.md` (`{journal-path}`, absolute path so worktrees never lose it):

```markdown
---
cycle: NNN
date: YYYY-MM-DD
head: <git sha>
stack: <stack>
focus: <focus>
engine: subagents
---

## Continuous Improvement Cycle NNN — YYYY-MM-DD

### Playbooks

- [Testing playbooks](../playbooks/)
- [Competitive parity](../playbooks/competitive-parity.md)
- [Regression scenarios](../regressions.md)

### Findings

| # | Type | Title | Priority | Issue | Spec |
|---|------|-------|----------|-------|------|

### Live Testing

_(populated by the orchestrator from live-tester's handoff)_

### Research & Monitoring

_(populated by the orchestrator from researcher's handoff)_

### Architecture & Code Quality

_(populated by the orchestrator from arch-analyst's handoff)_

### Security Audit

_(populated by the orchestrator from security-analyst's handoff)_

### Next Cycle Priorities

_(populated after cycle completes)_
```

## Spawn Template

Every spawn prompt starts with the `team-lead` spawn template (`{template}` below), filled for this cycle — `Teammates:` the agents spawned in this cycle, `Peers: none — report to the lead only`, `Code ownership: read-only — write only under .local/, never to tracked files` — followed by this block:

```text
Cycle journal: {journal-path}
Cycle mode: HEAD {changed|unchanged} (previous {previous-sha}, current {head}). The orchestrator has already synced and detected the mode: skip your protocol's sync and HEAD-mode detection, and do not fetch, merge, or move the checkout. Follow the Unchanged HEAD rules in your protocol when unchanged; never skip the cycle.
Journal: do NOT write {journal-path} or process-notes.md; the orchestrator is their only writer. List each finding in your handoff under `## Findings` as `<type> | <title> | <P0-P4> | #<issue> | <spec-path or —>` (issue number and spec path together), the modules you covered under `## Modules audited`, and your methodology-only retrospective under `## Retrospective`. Follow the Priority Label rules of your protocol.
Issues: file the issues of your own findings only. Do not file `testing-infra` issues; put them under Follow-ups.
Specs: allocate the spec directory number atomically (mkdir loop in SDD Integration) and leave MOC-specs.md to the orchestrator.
Report: include file paths and issue URLs.
```

## Step 1: Spawn Agents

Spawn all applicable agents in a **single turn** via parallel `invoke_subagent` calls:

- **`live-tester`** (when focus is `testing` or `full`):
  `invoke_subagent(TypeName: "live-tester", Role: "live-tester — live testing cycle", Prompt: "{template}\n\nRun the live-testing skill for this project.\nFocus: <testing | full>.\nRead the handoff chain for context on what changed recently.\nProject-specific rules: <paste .agents/rules/continuous-improvement.md if present>\nWrite your handoff with a Testing Results section listing all findings and filed issue URLs.")`
- **`researcher`** (when focus is `research`, `dependencies`, `parity`, or `full`):
  `invoke_subagent(TypeName: "researcher", Role: "researcher — research and monitoring cycle", Prompt: "{template}\n\nRun the research-protocol skill for this project.\nFocus: <research | dependencies | parity | full>.\n<When focus is full: security advisories (RUSTSEC, GHSA, CVE) belong to security-analyst; do not scan or file them, and skip the CVE sweep. Keep version-drift and release monitoring.>\nRead the handoff chain for context on what changed recently.\nProject-specific rules: <paste .agents/rules/continuous-improvement.md if present>\nWrite your handoff with a Research Results section listing all findings and filed issue URLs and spec paths.")`
- **`arch-analyst`** (when focus is `arch` or `full`):
  `invoke_subagent(TypeName: "arch-analyst", Role: "arch-analyst — architecture and code quality audit", Prompt: "{template}\n\nRun a full architecture and code quality audit of this project.\nThis is a READ-ONLY analysis pass — do NOT modify source files. Use the arch-inspect skill checklist.\nExplicitly cover DRY, type safety, modern APIs (per the stack profile) and version-policy impact (MSRV, engines/target) every cycle, including unchanged-HEAD cycles; do not report zero findings by default.\nProject-specific rules: <paste .agents/rules/continuous-improvement.md if present>\nWrite your handoff with an Architecture Review section listing all findings and filed issue URLs.")`
- **`security-analyst`** (when focus is `security` or `full`):
  `invoke_subagent(TypeName: "security-analyst", Role: "security-analyst — vulnerability and security audit", Prompt: "{template}\n\nRun a full vulnerability and security-hardening audit of this project.\nThis is a READ-ONLY analysis pass — do NOT modify source files, manifests, or lockfiles. Use the security-audit skill checklist (run the dependency scanners first, then the code-pattern categories).\nProject-specific rules: <paste .agents/rules/continuous-improvement.md if present>\nWrite your handoff with a Security Review section listing all findings, severities, and filed issue URLs.")`

End your turn and wait for all spawned subagents to report back with their handoff frontmatter + path. Apply the Agent outcomes rules to partial or failed results.

## Step 2: Shutdown Completed Agents

Terminate completed subagents via `manage_subagents(Action: "kill", ConversationIds: [...])`.

## Step 3: Complete Cycle Summary

Aggregate results from the agent handoffs and complete the remaining sections of `{journal-path}`. Number the Findings table once, here, from the rows each handoff lists under `## Findings`; every agent section also ends with a `Modules audited:` line copied from the handoff. Collect the `Follow-ups` of every handoff with `follow_ups` above 0 as well: file each one that carries evidence, following the filing rules of [Issue Management](references/issue-management.md) (duplicate check, `P0`-`P4` and category labels at creation), and record it as a Findings row.

Then close the cycle (the orchestrator touches only `.local/` and issue labels, never source code):

1. Append the merged retrospective (the only write to `process-notes.md` in the cycle) to `<main_root>/.local/testing/process-notes.md` per the [Process Self-Improvement Loop](../live-testing/references/testing-methodology.md#process-self-improvement-loop).
2. If a bug category recurs three or more times across cycle journals, list it under Next Cycle Priorities and file one `testing-infra` issue yourself proposing a structural fix or automated regression test. For an API-misuse category ("called API X where Y was required"), the first-choice structural fix is making the wrong call impossible; in Rust, a `disallowed-methods` / `disallowed-types` entry in `clippy.toml` whose `reason` names the bug and the replacement, for example `{ path = "saphyr_parser::Parser::new", reason = "unbounded scanner lookahead (#563); parse through fast_yaml_core::NormalizedInput::scanner" }` (other profiles keep the regression test). Merge in the `testing-infra` Follow-ups of the handoffs. The agents never file it; the orchestrator is its single filer.
3. Add one `<main_root>/.local/specs/MOC-specs.md` entry for every spec path in the Findings rows (the sdd subagents leave the file alone inside a cycle; spec rules in [SDD Integration](references/sdd-integration.md)).
4. Run the label spot-check from [Issue Management](references/issue-management.md#priority-label-mandatory); the orchestrator may add a missing `P0`-`P4` label with `gh issue edit`.

Report `{journal-path}` and a brief cycle summary to the user.
