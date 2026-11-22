---
name: team-debug
description: >-
  Debug Rust, TypeScript, and Luau/Lua issues using a multi-agent investigation
  team: debugger + conditional live-tester investigate root cause in parallel,
  security review always, architect and perf reviews conditionally, code-reviewer
  consolidates findings, and results are presented to the user. Use when asked to
  debug an issue, investigate a bug, find root cause, or analyze a production incident.
---

# Team Debug Orchestration

You act as **team lead** for a debugging investigation. Coordinate specialist subagents via `invoke_subagent` to diagnose the issue.

> You do NOT investigate or fix code yourself. ALL analysis is delegated. If you are about to read source files or edit code — STOP. Spawn the appropriate specialist agent.

## Step 0: Preflight

Run this single command via `run_command` before spawning anything:

```bash
printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null || echo not-a-git-repo)"
for f in Cargo.toml tsconfig.json package.json; do
  printf '%s=%s\n' "$f" "$(test -f "$f" && echo present || echo missing)"
done
if test -f default.project.json -o -f wally.toml -o -f pesde.toml -o -f .luaurc -o -f .luarc.json -o -f selene.toml -o -f stylua.toml; then
  echo 'luau=present'
else
  echo 'luau=missing'
fi
```

Check the output before spawning:

1. Current branch is `main`/`master` — ask the user or create a fix branch first if fixes may follow.
2. `Cargo.toml`, `tsconfig.json`, `package.json`, and `luau` are all `missing` — no supported stack at the root (for a monorepo with manifests in subdirectories, ask the user which stack to pass).

**Stack**: derive `{stack}` from the markers — `Cargo.toml` → `rust`; `tsconfig.json` or `package.json` → `typescript`; `luau=present` → `luau`; several → comma-separated (`rust,typescript`; a roblox-ts project is `typescript,luau`). Narrow it when the symptoms clearly sit in one language. Every spawn prompt carries `Stack: {stack}`, so subagents skip their own detection.

## Step 1: Load the Lead Protocol

Read `../team-lead/SKILL.md` and follow it: `invoke_subagent`, reactive wakeup, `send_message`, naming, and `manage_subagents` shutdown. Do not spawn anything before reading it. Every subagent here is report-only.

## Step 2: Plan the Investigation DAG

Track this execution DAG (every specialist runs in report-only mode):

| Stage | Task | Agent (`TypeName`) | Condition |
|---|---|---|---|
| 1 | `investigate` | `debugger` | Always |
| 1 | `live-test` | `live-tester` | Runtime symptoms (panics, uncaught exceptions, crashes, wrong output, flaky tests, integration failures, async deadlocks). Skip for pure compile-time/type/linker errors. |
| 2 | `review-arch` | `architect` | Symptoms mention recurring/systemic/regression-after-refactor/multiple-callers/wrong-abstraction/design-flaw, OR Stage 1 handoffs flag an architectural concern. |
| 2 | `review-security` | `security-maintenance` | Always |
| 2 | `review-perf` | `performance-engineer` | Symptoms or Stage 1 handoffs include latency/slow/timeout/memory-leak/CPU-spike/throughput/regression/benchmark-failure. |
| 3 | `consolidate` | `code-reviewer` | Always |

## Spawn Template

Every spawn prompt starts with the `team-lead` spawn template (`{template}` below), filled for this run:

- **Teammates**: the names this run spawns (`debugger`, and as applicable `live-tester`, `arch-reviewer`, `security`, `perf`, `reviewer`)
- **Peers**: `none — report to the lead only`
- **Code ownership**: `report-only — no subagent edits source`

## Step 3: Investigation Phase (parallel when live testing applies)

Spawn `debugger` unconditionally. If `live-test` applies, spawn `live-tester` in the same turn so both run in parallel:

```text
invoke_subagent(
  TypeName: "debugger",
  Role: "debugger — static root cause",
  Prompt: "{template}\n\nInvestigate symptoms via static analysis. Report root cause(s), affected files/lines, reproduction path, severity, perf-degradation flag. Do NOT apply fixes.\n\nSymptoms:\n{symptom-description}"
)
```

If live testing applies:

```text
invoke_subagent(
  TypeName: "live-tester",
  Role: "live-tester — runtime root cause",
  Prompt: "{template}\n\nAfter handoff setup: read the live-testing skill (SKILL.md) — it is the authoritative execution guide for this session.\n\nExecute the built artifact, reproduce reported symptoms, document repro steps, observed vs expected, anomalies. Do NOT fix.\n\nSymptoms:\n{symptom-description}"
)
```

End your turn to wait for both handoff frontmatters + paths. Each must contain: root cause hypothesis, affected files/lines, repro, severity, performance flag.

**No-change outcome.** A `debugger` handoff with `status: no_change_needed` (the code behaves as intended; its `## Evidence` section holds the reproduction attempt) ends the investigation only when no `live-tester` was spawned or its handoff did not reproduce the symptoms: runtime evidence wins. Then skip Steps 4 and 5, terminate idle subagents via `manage_subagents`, and present the evidence to the user in place of the Step 6 report, with no fixes proposed. When `live-tester` reproduced the symptoms, treat the debugger's handoff as a diverging diagnosis and pass both to the reviewer in Step 5.

After receiving Stage 1 handoffs, terminate `debugger` and `live-tester` (`manage_subagents`) and finalize whether `review-arch` and `review-perf` apply.

## Step 4: Parallel Review

Spawn all applicable reviewers in a single turn, passing the Stage 1 handoff frontmatters + paths:

- If `review-arch` is active: `invoke_subagent(TypeName: "architect", Role: "arch-reviewer — architectural review", ...)` — assess whether this is a deeper design defect or a local bug, reconcile static vs runtime conclusions, report only.
- Always: `invoke_subagent(TypeName: "security-maintenance", Role: "security — security review", ...)` — review data exposure, privilege escalation, memory safety, dependency vulnerabilities, report only.
- If `review-perf` is active: `invoke_subagent(TypeName: "performance-engineer", Role: "perf — performance review", ...)` — review hot paths, allocations, async bottlenecks using runtime evidence where available, report only.

End your turn and wait for all active reviewers. Terminate them via `manage_subagents` once their handoffs arrive.

## Step 5: Consolidation

Spawn `code-reviewer` with all accumulated handoff frontmatters + paths:

```text
invoke_subagent(
  TypeName: "code-reviewer",
  Role: "reviewer — consolidate debug findings",
  Prompt: "{template}\n\nConsolidate findings into a unified fix scope:\n- Cross-reference static vs runtime evidence (defer to runtime if they diverge)\n- Prioritize: critical (must fix now) vs follow-up (file as issues)\n- Triage every Follow-ups entry in the handoffs (sources and issue format per your Follow-up Sources and Filing sections) but do NOT file yet — list them in Follow-up Issues; the user decides on filing\n- Exact files and line ranges to change\n- Flag security findings\n- Note architectural issues warranting a separate /team-develop cycle\n- Verdict: 'fixes_required' or 'no_fixes_needed'\n\nHandoffs:\n{all accumulated frontmatters}"
)
```

Wait for `reviewer`'s handoff. Keep `reviewer` alive until the user answers Step 6.

## Step 6: Present Results

Compile a structured report. Do NOT apply fixes, create issues, or commit automatically:

```markdown
## Debug Investigation Complete

### Root Cause
{from debugger, refined by reviewers}

### Critical Fixes Required
{must-fix items with files/line ranges}

### Follow-up Issues
{from the reviewer's Follow-up Issues section: architectural / security / perf concerns and every agent follow-up — not critical now}

### Recommendation
- Fix critical items via /team-develop or manual patch
- Create GitHub issue per follow-up item
- Group into an epic if 3+ related issues exist
```

Use `ask_question` to let the user choose next steps:
1. `(Recommended) File follow-up GitHub issues and launch /team-develop for critical fixes`
2. `Launch /team-develop for critical fixes only`
3. `File GitHub issues for follow-up items only`
4. `Stop here (report only)`

Wait for the user's answer. When the user chooses to file follow-ups, resume `reviewer` via `send_message(Recipient: "{reviewer_conversationId}", Message: "...")` to file them per its Filing Follow-up Issues protocol, wait for the issue URLs, and report them.

## Step 7: Shutdown

Terminate `reviewer` (and any remaining subagent) via `manage_subagents(Action: "kill", ...)` once the user has answered Step 6 and any requested filing is complete.

## Handoff Accumulation

Pass inline frontmatter to each subsequent agent — no file reads for routing:

```text
After investigation: [debugger, (live-tester)]
After parallel:      [debugger, (live-tester), (arch-reviewer), security, (perf)]
Reviewer gets all of the above.
```
