# Reduced Workflow Chains

Reduced chains reuse Preflight, Step 0 classification, the `team-lead` spawn protocol, handoff accumulation, follow-up routing (Step 7), fix-review cycle (Step 8), commit (Step 9), and shutdown (Step 10) from [../SKILL.md](../SKILL.md). Any reduced chain with a `developer` step runs the Step 3 `{spec}` lookup and adds `acceptance-tests` (Step 4.6) when a `{spec}` exists.

**Mandatory critic gate**: every chain in which `developer` edits code (`new-feature`, `bug-fix`, `refactoring`, `security`, `dependency`, `performance`, `task-loop`) MUST run `impl-critic` (`critic`, report-only) after `developer` and before `reviewer`, with a `Requirement source:` line and Scope gate + Follow-up assessment. Chains without a `developer` phase (`docs`, `ci-cd`, `spec-driven`) are exempt.

## Workflow: Bug Fix

`debugger → developer → parallel(tester, impl-critic, conditional live-tester) → reviewer → commit`.

1. Spawn `debugger` (`diagnose`). `no_change_needed` ends the chain. Skip `diagnose` if the task already states exact root cause and fix.
2. If the project has a runnable surface, spawn `live-tester` to write the bug verification contract (Step 4.6); spawn `developer` with debugger handoff.
3. Parallel report-only validation: `tester` (verify regression test fails without fix & passes with it), `impl-critic` (mandatory), and resume `live-tester` if active.
4. `reviewer` → Step 8 fix cycle → Step 9 commit → Step 10 shutdown.

## Workflow: Refactoring

`architect (lite, skip if concrete) → developer → parallel(tester, impl-critic) → reviewer → commit`.

1. Spawn `architect` for refactor plan (skip if exact renames/moves/extractions are already specified).
2. Spawn `developer` to apply refactor.
3. Parallel report-only validation: `tester` (confirm existing suite passes with no behavioral drift) and `impl-critic` (confirm behavior preserved, flag semantic drift — mandatory).
4. `reviewer` → Step 8 → Step 9 → Step 10.

## Workflow: Security

`security-maintenance → developer → impl-critic → reviewer → commit`.

1. Spawn `security-maintenance` (`audit`, include advisory IDs/links; skip if exact CVE/fix is already given).
2. Spawn `developer` to apply fixes per security handoff.
3. Spawn `impl-critic` (mandatory: incomplete mitigation, new attack surface, edge cases).
4. `reviewer` → Step 8 → Step 9 → Step 10.

## Workflow: Documentation

`tech-writer → reviewer → commit`.

1. Spawn `tech-writer` (`writer`) to edit docs/doc comments (`Code ownership: only writer edits docs and doc comments`). If new Rust doctests are added, also run `testing-engineer`.
2. Spawn `code-reviewer` (`reviewer`) to verify accuracy and run the profile's doc gate.
3. Step 8 fix cycle routes to `writer` → Step 9 → Step 10.

## Workflow: Dependency Bump

`developer → parallel(security-maintenance, tester, impl-critic) → reviewer → commit`.

1. Spawn `developer` to bump manifest, refresh lockfile, and fix compile/type errors.
2. Parallel validation: `security-maintenance` (advisories/yanked/licenses), `testing-engineer` (full suite), and `impl-critic` (API-breakage adapters — mandatory).
3. `reviewer` → Step 8 → Step 9 → Step 10. Escalate major semver-breaking bumps to `refactoring`.

## Workflow: Performance

`perf → developer → parallel(perf verify, tester, impl-critic) → reviewer → commit`.

1. Spawn `performance-engineer` (`perf`) to profile baseline and propose optimization plan.
2. Spawn `developer` to implement optimization.
3. Resume `perf` via `send_message` to re-measure (`verify`), and spawn `testing-engineer` + `impl-critic` (mandatory) in parallel. If `verify` shows no gain or regression, return to `developer` or escalate to `refactoring`.
4. `reviewer` → Step 8 → Step 9 (commit body MUST include before/after numbers) → Step 10.

## Workflow: CI/CD

`cicd-devops → reviewer → commit`.

1. Spawn `cicd-devops` (`cicd`, `Code ownership: only cicd edits workflows and tooling config`).
2. Spawn `code-reviewer` (`reviewer`) to review YAML/config diff (validate YAML with `fy lint`).
3. Step 8 fix cycle routes to `cicd` → Step 9 → Step 10. Escalate to `refactoring` if source edits are needed.

## Workflow: Spec-Driven

`clarify → architect → critic → sdd-orchestrator → reviewer → commit-spec → follow-up issue`. Design-only; no source edits.

`Code ownership: no source files are edited in this chain; only sdd-orchestrator writes, and only spec artifacts under specs/{feature-slug}/. Only the team lead commits and opens issues.`

0. Run Step 2.5 (Clarify) and pass answers to `architect` and `sdd-orchestrator`.
1. Spawn `architect` (design plan only — no code). Skip `architect → critic` only if user already has an approved RFC/plan and explicitly asks to turn it into a spec.
2. Spawn `critic` (mandatory plan gate, same verdict loop as Step 4).
3. Spawn `sdd-orchestrator` in Non-Interactive Mode to write `specs/{feature-slug}/` (`spec.md`, `plan.md` with Contracts, `tasks.md`; BRD/SRS/NFR only when requested or new system; delta file per `sdd` Delta Model if capability spec exists).
4. Spawn `code-reviewer` (`reviewer`) to audit completeness, traceability, testability, links, and YAML validity.
5. Step 8 fix cycle routes to `sdd-orchestrator` (if scope is fundamentally broken, loop back to `architect` → `critic` → `sdd-orchestrator`).
6. Commit and PR `specs/{feature-slug}/` only (`spec({feature-slug}): add specification`), then open a follow-up implementation issue via `gh issue create` (using `--type Feature` when the repository has types, per [github-issues](../../github-issues/SKILL.md)) linking the spec PR and recommending `/solve-issue` (`new-feature` chain).
7. Terminate all subagents via `manage_subagents`.
