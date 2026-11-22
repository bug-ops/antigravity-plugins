---
name: research-protocol
description: >-
  Research and monitoring protocol for Rust, TypeScript, and Luau/Lua projects:
  dependency health, security advisories, competitive parity, innovation
  research, and issue filing. Loaded by researcher; invoked directly via
  /research-protocol, delegates to a background researcher.
---

# Research and Monitoring Protocol

Monitor the project's dependency health, track the competitive landscape, and surface new techniques that could benefit the project. File GitHub issues for every actionable finding.

Default focus: `full` (all phases).

## Direct Invocation

This protocol is loaded by `researcher` at startup. When invoked directly (`/research-protocol`) in a session that is **not** `researcher`, delegate it via `invoke_subagent` so findings — not tool noise — land in the conversation:

```text
invoke_subagent(
  TypeName: "researcher",
  Role: "researcher — research and monitoring session",
  Prompt: "Read the research-protocol skill (SKILL.md) and follow it end to end with focus: <focus>. Report findings and filed issue URLs; do not modify source files."
)
```

End your turn to wait for the subagent's report. If you **are** `researcher`, continue with the protocol below.

## Mandatory Reading

Read all reference files before starting:

- [Research Protocol](references/research-protocol.md) — research methodology, competitive parity, dependency monitoring
- [Issue Management](../continuous-improvement/references/issue-management.md) — anomaly classification, P0-P4 labels, filing template
- [SDD Integration](../continuous-improvement/references/sdd-integration.md) — when and how to spawn `sdd-orchestrator` before filing

## Stack Profile

For each detected profile (`Stack:` line in your prompt, or `stack` skill detection), apply `../stack/references/<profile>/researcher.md` together with `../stack/references/<profile>/toolchain.md`: outdated and advisory commands, registries and advisory databases, package health signals, ecosystem research topics, common vulnerability classes. Polyglot project: monitor every profile's dependency tree.

## Hard Rules

1. **NEVER modify source code** — not even dependency versions in a manifest or lockfile
2. **ALL findings become GitHub issues** — implementation happens in separate sessions
3. **You MAY write ONLY to `.local/testing/` and `.local/specs/`** — under the main repository root, even from a git worktree; resolve it once with `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` and use absolute paths

**Journal:** inside a cycle (`Cycle mode:` present) do not write the journal; list findings in the handoff. Standalone, use the journal per [Testing Methodology](../live-testing/references/testing-methodology.md#journal).

**Unchanged HEAD:** when the cycle prompt says HEAD is unchanged, run a delta check only. See [Research Protocol](references/research-protocol.md#delta-check-on-unchanged-head).

## Phase 1: Dependency Monitoring (`dependencies`, `full`)

Run the profile's version-drift and security-advisory commands for every detected profile.

Update priority and issue filing — see [Research Protocol](references/research-protocol.md#dependency-monitoring).

For security advisories: spawn `sdd-orchestrator` via `invoke_subagent` before filing (see [SDD Integration](../continuous-improvement/references/sdd-integration.md)). Major version bumps (P3/P4) and routine patch/minor updates: file directly.

## Phase 2: Research & Innovation (`research`, `full`)

Search for new techniques relevant to the project's domain:

- Architectural patterns, concurrency models, state machines
- Performance techniques: fewer copies and allocations, data layout, parallelism, startup time, artifact size
- Safety practices: compile-time and type-level guarantees, typestate, capability-based design
- Ecosystem evolution: new libraries, deprecated dependencies, emerging standards, language and runtime releases
- Tooling improvements: profiling, debugging, testing frameworks
- Plus the language-specific topics in the profile's `researcher.md`

Also treat dependency functionality coverage as a research question: does a major dependency offer capabilities the project does not use? See [Research Protocol](references/research-protocol.md#dependency-functionality-coverage).

For each finding:
1. Assess: impact on project quality vs implementation complexity
2. Spawn `sdd-orchestrator` to produce a spec when the SDD Integration threshold table says Yes (P1–P2 research and parity findings)
3. Check for duplicate issues before filing
4. File research issue with source links, implementation sketch, the spec content under `## Specification`, and a priority label at creation (see [Issue Management](../continuous-improvement/references/issue-management.md#priority-label-mandatory)); file it in the same pass as the spec

## Phase 3: Competitive Parity (`parity`, `full`)

Identify reference projects in the same domain, review their recent changelogs, and assess capability gaps. See [Research Protocol](references/research-protocol.md#competitive-parity-monitoring) for the full scan procedure.

Parity gap severity:
- **P1** — active incompatibility with a first-class integration target
- **P2** — meaningful capability that 2+ reference projects have and users would notice
- **P3** — useful feature, low urgency
- **P4** — cosmetic or niche difference

Update `.local/testing/playbooks/competitive-parity.md` after each scan.

## Optional Phases

When applicable to the project (see [Research Protocol](references/research-protocol.md)):

- **Competitor gap analysis** — `competitor-gap` label, exhaustion criterion, discovery of new competitors
- **CVE and vulnerability-class sweep** — monthly, separate from the parity scan; P0 if the class is unprotected

## Session Exit

Before finishing:

1. Append a methodology-only retrospective to `.local/testing/process-notes.md` (inside a cycle, put it in the handoff `## Retrospective` instead); a technique that proved effective becomes a playbook, a failed one is documented and dropped
2. Print a summary: dependency advisories found, research issues filed, parity gaps identified
3. Write handoff with **Research Results** section listing all filed issue URLs and spec paths
