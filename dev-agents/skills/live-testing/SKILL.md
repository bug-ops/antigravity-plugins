---
name: live-testing
description: >-
  Live testing protocol for Rust, TypeScript, and Luau/Lua projects: sync,
  discover project structure, execute the built binary, CLI, server, or web app
  end-to-end, detect anomalies, track coverage, and file bug issues. Used by
  live-tester; invoked directly via /live-testing, delegates to live-tester.
---

# Live Testing Protocol

Execute live tests on the current project: run the real artifact, verify behavior end-to-end, detect regressions, and file issues for every anomaly found.

Default focus: `full` (all phases).

## Direct Invocation

This protocol is loaded by `live-tester` at startup. When invoked directly (`/live-testing`) in a session that is **not** `live-tester`, delegate it via `invoke_subagent` so findings — not tool noise — land in the conversation:

```text
invoke_subagent(
  TypeName: "live-tester",
  Role: "live-tester — live testing session",
  Prompt: "Read the live-testing skill (SKILL.md) and follow it end to end with focus: <focus>. Report findings and filed issue URLs; do not modify source files."
)
```

End your turn to wait for the subagent's report. If you **are** `live-tester`, continue with the protocol below.

## Mandatory Reading

Read all reference files before starting:

- [Testing Methodology](references/testing-methodology.md) — execution protocol, priority order, testing gate, journal, what to check after each session
- [Issue Management](../continuous-improvement/references/issue-management.md) — anomaly classification, P0-P4 labels, filing template
- [SDD Integration](../continuous-improvement/references/sdd-integration.md) — when and how to spawn `sdd-orchestrator` before filing

## Stack Profile

For each detected profile (`Stack:` line in your prompt, or `stack` skill detection), apply `../stack/references/<profile>/live-tester.md` together with `../stack/references/<profile>/toolchain.md`: manifest fields to read, build and run commands, log verbosity, crash signatures, benchmark and cleanup commands. Polyglot project: apply each profile to the components of its language.

## Project Verify Skill

If `.agents/skills/verify/SKILL.md` exists (created by `/init-project`), read it before Phase 2 and use its build, run, and test commands as the authoritative recipe. When a command there is wrong or a step is missing, never edit that tracked file: record the correction under `.local/testing/` and file an issue for it.

## Hard Rules

1. **NEVER modify source code** — not even one-liners; this covers sources, manifests, lockfiles, build and CI configs
2. **ALL findings become GitHub issues** — including symptoms without a known root cause; fixes happen in separate team sessions. This holds in standalone and `continuous-improvement` runs. In a `team-develop` or `team-debug` run (your prompt makes you a teammate there) file nothing and spawn no `sdd-orchestrator`: record each finding under Follow-ups in your handoff; the critic and the reviewer decide, and the reviewer files after the lead's or user's gate
3. **You MAY write ONLY to `.local/testing/`** — journal, coverage status, playbooks, debug logs, helper scripts — under the main repository root, even from a git worktree. Resolve that root once with `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` and use absolute paths: every `.local/testing/` path in this skill, its references, and the stack profile means `<main root>/.local/testing/`

## Phase 1: Sync

When the prompt carries a `Cycle mode:` line, the orchestrator has already synced and fixed the mode: skip this phase's sync command and the HEAD comparison, take the mode from that line, and never fetch, merge, or move the checkout. Otherwise run as one command (shell variables do not survive between Bash calls):

```bash
git fetch origin
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/$(git remote show origin | sed -n 's/.*HEAD branch: //p')")
old=$(git rev-parse HEAD)
if [ "$(git branch --show-current)" = "${default#origin/}" ]; then git merge --ff-only "$default"; fi
git log --oneline "$old..$default" | head -20
```

Never merge or pull the default branch into the current branch: this role must not change git history. On the default branch the checkout only fast-forwards; a failed fast-forward (diverged or dirty tree) is reported, not resolved. On any other branch (a fix branch in `team-debug`, a worktree) test the checkout as it is; the log lists the new default-branch commits (on the default branch, the ones just fast-forwarded; elsewhere, the ones the checkout lacks).

- Review new commits to identify what changed since the last session
- Examine changed files to understand scope
- Update `.local/testing/coverage-status.md` — add `Untested` rows for new features, reset rows of significantly changed components to `Untested`
- Record `git rev-parse HEAD` at session start (inside a cycle the `Cycle mode:` line already carries it); standalone, compare it with the `head:` of the last journal, and equal means unchanged-HEAD mode (see Phase 3)
- Prioritize testing changed functionality first
- Journal: inside a cycle (`Cycle mode:` present) do not write the journal, list findings in the handoff instead; standalone, create the next journal file per [Testing Methodology](references/testing-methodology.md#journal)

## Phase 2: Project Discovery

Before testing, understand the project:

1. Read the manifest(s) the profile names — workspace members, entry points and build targets, feature flags or build modes
2. Look for test configs: `.local/config/`, `tests/`, env files, and the profile's config locations
3. Identify executable entry points and supported interfaces (CLI, TUI, server/API, web UI, bots)
4. Note the flags, env vars, or build modes needed to reach the feature under test

## Phase 3: Live Testing

**Unit and integration tests alone are NOT sufficient.** This phase requires real execution of the built artifact with real I/O and real user-like interactions. See [Testing Methodology](references/testing-methodology.md) for the full execution guide.

**Priority order:**
1. New/changed functionality (from recent PRs) — highest probability of regressions
2. `Untested` or `Partial` components from `coverage-status.md`
3. Known-tricky scenarios from `regressions.md`
4. Cross-interface consistency (if project has multiple I/O modes)

**Long-running processes:** start a server or daemon under test via `run_command` with `IsDaemon: true` and `WaitMsBeforeAsync: 500`, inspect its output with `manage_task(Action: "status")`, and stop it with `manage_task(Action: "kill")` when the session ends.

**Unchanged HEAD:** never skip the session; follow [Testing Methodology](references/testing-methodology.md#unchanged-head).

**Optional checks** (benchmarks, live drift gate): see [Testing Methodology](references/testing-methodology.md#optional-checks).

**Testing gate:** When a large portion of components are Untested or Partial, testing takes priority over everything else. Do not proceed to Phase 4 until critical components are verified.

**After each test session, review:**
- Logs: WARN, ERROR, crashes (the profile's crash signatures), unexpected retries, timeouts
- Output correctness: expected vs actual behavior
- Resource usage: memory, CPU, latency, tokens if applicable
- Feature interactions: combinations that unit tests cannot cover

## Phase 4: Anomaly Detection and Issue Filing

For each anomaly found:

1. **Reproduce** — confirm the issue is consistent, not a one-off
2. **Document** — exact steps, config, relevant log excerpts
3. **Classify** — P0 (critical) to P4 (nice-to-have); see [Issue Management](../continuous-improvement/references/issue-management.md)
4. **Spec** — for a P0–P2 enhancement (never for a bug; not in team runs, Hard Rule 2): spawn `sdd-orchestrator` agent before filing; see [SDD Integration](../continuous-improvement/references/sdd-integration.md)
5. **Check duplicates** — `gh issue list --state open --limit 100 --json number,title,labels`
6. **File** (not in team runs, Hard Rule 2) — `gh issue create` with the literal `P0`-`P4` label set at creation (create the label if missing), a category label, reproduction steps, evidence; file the implementation issue in the same pass as the spec. A symptom without a root cause is still filed
7. **Record** — add the finding row (issue and spec together) to the handoff `## Findings` in a CI cycle, or append it to the standalone journal otherwise; update `coverage-status.md`

## Phase 5: Cross-Interface Consistency

If the project supports multiple interfaces (CLI, TUI, web, API, bots):

- Exercise the same scenario across all applicable interfaces
- Compare output content, formatting, behavior, state changes
- File issues when behavior diverges across interfaces

## Session Exit

Before finishing:

1. Update `.local/testing/coverage-status.md` for all components touched (rows in place, no cycle headers)
2. Run the [Process Self-Improvement Loop](references/testing-methodology.md#process-self-improvement-loop)
3. Print a summary: features tested, issues filed, coverage changes
4. Write handoff with **Testing Results** section listing all filed issue URLs
