---
name: triage-and-solve
description: >-
  Triage open GitHub issues by priority (P0-P4 labels first, category labels as
  fallback) and blocked-by/sub-issue relations, group compatible issues into a
  single PR sized by review budget, then solve via /solve-issue. Use when asked
  to triage issues, pick the next issue, or prioritize open work.
disable-model-invocation: true
---

# Triage and Solve

Triage open GitHub issues by priority and relations, group dependent and compatible ones into a single PR whose diff stays reviewable, then solve the highest-priority group via `/solve-issue`.

## Steps

**1. Fetch unassigned open issues**

Read [github-issues](../github-issues/SKILL.md) first for the relation/type fields below and the older-`gh` fallback.

```bash
gh issue list --state open --limit 100 --search "no:assignee" --json number,title,body,labels,milestone,assignees,issueType,parent,subIssues,blockedBy,blocking
```

Only unassigned issues are eligible for triage. As a safety check, skip any result where `assignees` is non-empty.

**2. Sort by priority**

Assign each issue its own priority score in two tiers; step 3 refines it into the effective score used for selection.

**Tier 1 — explicit `P0`-`P4` labels (authoritative).** Check whether the project uses P-labels: any fetched issue carrying a `P0`-`P4` label means it does. When present, the P-label is the primary metric — score equals the P-number (`P0`=0, `P1`=1, `P2`=2, `P3`=3, `P4`=4).

Every issue with a P-label outranks every issue without one. Within the same P-level, break ties with the Tier 2 table (e.g., `P1` + `bug` before `P1` + `enhancement`).

**Tier 2 — category labels (fallback).** For issues without a P-label, and for projects that do not use P-labels at all:

| Label | Score |
|-------|-------|
| `critical` | 5 |
| `high` | 6 |
| `bug` / `fix` | 7 |
| `enhancement` | 8 |
| no priority label | 9 |
| `research` | 10 |

If an issue has multiple labels, use the lowest (highest priority) score within its tier — with one exception: `research` overrides other category labels. An issue type counts as its category label when the label is missing: `Bug` as `bug`, `Feature` as `enhancement`.

**Research goes to the tail.** `research` issues are real work and stay in the queue — never drop them — but they always sort to the end unless given an explicit P-label (Tier 1 wins).

**3. Load issue relations**

The step 1 result already carries each issue's authoritative GitHub relations: `blockedBy`, `blocking`, and `subIssues` as `{nodes: [{number, state, title, url}], totalCount}`, and `parent` as an issue or null.

Then fetch full details including comments: `gh issue view <number> --json number,title,body,labels,comments`. Analyze the body **and all comments**. Collect text references ("depends on #N", "blocked by #N", "part of #N", "after #N lands"); any without a matching GitHub relation is a **missing relation**, created in step 7.

Classify every blocker:

| Blocker state | Effect on the blocked issue |
|---------------|-----------------------------|
| closed | satisfied — ignore the edge |
| open, unassigned, in this repository | prerequisite — must land in the same group or an earlier one |
| open, assigned, or in another repository | external — the blocked issue and everything depending on it sit out this pass |

A blocker in the step 1 list is open and unassigned; for any other open blocker, its `url` names the repository and `gh issue view <url> --json state,assignees` checks assignment.

A dependency cycle is a triage defect: report it and exclude its issues from selection.

**Effective score.** Propagate priority along relations until stable:
- A blocker takes the best (lowest) score among itself and the issues it blocks, transitively.
- A parent with open sub-issues is triaged through them; each sub-issue takes the better of its own and its parent's score.

**4. Detect project subsystems**

1. Rust: `[workspace] members` in root `Cargo.toml`.
2. TypeScript: workspace packages from `pnpm-workspace.yaml` or `workspaces` in `package.json`.
3. Luau/Lua: each Rojo project file (`*.project.json`) or Wally/pesde package; inside one Roblox place, top-level `src/` folders (`server`, `client`, `shared`).
4. Polyglot repos: combine the lists.
5. Otherwise treat the project as a single unit.

**5. Estimate change volume**

Locate the code each candidate changes (search for paths, symbols, error messages, config keys, or query LSP references via `mcpls`) and estimate files touched, changed lines, call-site ripple, and subsystems touched:

| Class | Points | Typical shape |
|-------|--------|---------------|
| S | 1 | up to ~50 lines in 1–2 files of one module |
| M | 2 | up to ~200 lines in a few files of one subsystem |
| L | 4 | up to ~500 lines, or an interface change rippling through its call sites |
| XL | — | beyond L, or 3+ subsystems — always its own group; propose splitting into sub-issues |

Raise the class by one when the change rewrites most of an existing module. An issue whose scope cannot be located in code is at least M.

**Review budget per group: 4 points across at most two cohesive subsystems.** Estimate the group by the union of its changes.

**6. Select the highest-priority group**

1. **Leader** — lowest effective score not blocked by an external blocker or cycle.
2. **Prerequisite closure** — add every open in-repo blocker transitively; if it exceeds budget, cut in topological order taking deepest prerequisites first.
3. **Fill** — while budget allows, add in effective-score order: issues whose open blockers are already in the group, open sibling sub-issues, issues sharing files/subsystem, then independent issues (each becomes its own track).
4. **Order** — topological order (blockers first), ties by effective score.
5. **Tracks** — split into independent tracks for parallel developers. Merge tracks that share a relation or estimated file; changelog/version manifests stay with the lead, dependency manifests/lockfiles belong to one named track.

When a group closes all open sub-issues of a parent, list the parent last as a tracking parent.

Print a summary table showing candidates, selected group, rationale, tracks, missing relations, and remaining chain.

**7. Confirm before proceeding**

Use `ask_question` with the recommended option first:
- Question 1 (`Group`): `"Solve <issues> in one PR?"` with options:
  - `(Recommended) Solve group — <tracks>, <N> points`
  - `Leader chain only — drop the fill issues` (omit if no fill issues)
  - `Next group — skip this group and show the next candidate`
  - `Cancel — stop without solving anything`
- Question 2 (`Relations`, only when missing relations exist): `"Create the missing relations on GitHub?"` with options:
  - `(Recommended) Create all — <list>`
  - `Skip — leave them as text references`

When `Create all` is chosen, create real GitHub relationships:

```bash
gh issue edit <blocked> --add-blocked-by <blocker>
gh issue edit <parent> --add-sub-issue <child>
```

**8. Launch `/solve-issue`**

Read `../solve-issue/SKILL.md` and run it with the group's issue spec: commas separate issues of one track in solve order, semicolons separate tracks, tracking parents go last in the track of their sub-issues (for example `57,42;64`).

## Notes

- Skip issues labeled `wontfix` or `duplicate`.
- Never drop `research` issues — keep them at the tail unless prioritized via P-labels.
- Break equal-priority ties by most recent activity.
- GitHub relations are authoritative; text references become real relations once confirmed.
