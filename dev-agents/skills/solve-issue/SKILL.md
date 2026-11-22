---
name: solve-issue
description: >-
  Solve one GitHub issue or a group of issues in a single PR end-to-end: fetch
  the issues, create a feature branch (or git worktree), and orchestrate
  development via team-develop. Use when asked to solve issue #N, fix issue #N,
  or implement issues #N and #M together.
---

# Solve GitHub Issue

Solve one GitHub issue, or a group of issues in a single PR, end-to-end using the `team-develop` multi-agent workflow.

Accepts one issue number or a group spec in the format `/triage-and-solve` produces (`<n1>[,<n2>...][;<n3>...]`). Commas separate issues of one track in solve order (blockers first); semicolons separate independent tracks that parallel developers implement. A list without semicolons is a single track. Keep the order and tracks through every step.

## Step 0: Preflight

Run this single check via `run_command`:

```bash
printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null || echo not-a-git-repo)"
printf 'branching_rules=%s\n' "$(test -f .agents/rules/branching.md && echo present || echo absent)"
printf 'commit_rules=%s\n' "$(test -f .agents/rules/commits-and-issues.md && echo present || echo absent)"
```

## Steps

**1. Fetch issue data and assign**

Split the argument into tracks on semicolons and each track into issues on commas, trim spaces and leading `#`, and drop duplicates while keeping the first occurrence. For each number, in order:

```bash
gh issue view <number> --json number,title,body,labels,milestone,state,comments
```

A closed issue is dropped with a warning, and an empty track is dropped; if no open issue remains, stop and report. Assign every remaining issue to yourself:

```bash
gh issue edit <number> --add-assignee @me
```

Parse per issue:
- `number`, `title`, `body`, `comments` → passed to `team-develop` (specs too large for the issue body sit in the first comment, so comments travel with the issue)
- `labels` → detect `bug`/`fix` label to choose branch prefix (`fix/` vs `feat/`)
- `milestone` → extract milestone number `N` for `feat/mN/` branch names (if present)

For a group, detect **tracking parents**: an issue whose open sub-issues are all in the list (`gh api repos/{owner}/{repo}/issues/<number>/sub_issues --jq '[.[] | select(.state == "open") | .number]'`). A tracking parent is closed by the PR but not implemented separately.

**2. Determine branch name**

Branch naming convention:
- Bug/fix labels → `fix/<short-slug>` (max 30 chars)
- Feature / no label with milestone → `feat/m{N}/<feature-slug>` where `N` comes from the milestone number
- Feature / no label without milestone → `feat/issue-{number}/<feature-slug>`

Slug derivation: take the issue `title`, lowercase it, replace non-alphanumeric runs with `-`, trim leading/trailing dashes, truncate to 30 chars.

For a group, derive the name from the first issue of the first track that is not a tracking parent; use `fix/` only when every issue carries a `bug`/`fix` label, and `feat/m{N}/` only when every issue shares milestone `N`.

**Note**: If preflight showed `.agents/rules/branching.md` is present, read it and follow those conventions instead of the defaults above. If `.agents/rules/commits-and-issues.md` is present, read it for commit message format and issue filing rules.

**3. Sync the default branch and create the feature branch**

```bash
git fetch origin
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/$(git remote show origin | sed -n 's/.*HEAD branch: //p')")
```

Create an isolated worktree (when keeping the main checkout free) or check out the feature branch cleanly from `{default}`:

```bash
# Option A: switch directly on a clean checkout
git checkout -b <branch-name> "$default"

# Option B: isolated worktree (run subsequent commands inside the worktree path)
git worktree add -b <branch-name> "../worktrees/<slug>" "$default"
```

**4. Run the `team-develop` workflow**

Read `../team-develop/SKILL.md` and orchestrate development directly as team lead, passing the structured task brief:

Single issue:

```text
Implement GitHub issue #{number}: {title}

Issue body:
{body}

Issue comments:
{comments}

The PR body closes #{number}:
Closes #{number}

Working branch: {branch-name}

Follow project rules in AGENTS.md, GEMINI.md, and .agents/rules/ if they exist.
```

Group — one section per track, one subsection per implemented issue, in solve order:

```text
Implement GitHub issues in one branch and one PR. Tracks are independent: implement them with parallel developers, one developer per track, each owning only its track's files. Within a track, issues go in the listed order and each may build on the ones before it.

## Track 1: #{n1}, #{n2}

### Issue #{n1}: {title1}

{body1}

Comments:
{comments1}

### Issue #{n2}: {title2}

{body2}

Comments:
{comments2}

## Track 2: #{n3}

### Issue #{n3}: {title3}

{body3}

Comments:
{comments3}

Tracking parents closed by this PR, not implemented separately: #{p}

The PR body closes every issue above and every tracking parent, one closing keyword per line:
Closes #{n1}
Closes #{n2}
Closes #{n3}
Closes #{p}

Working branch: {branch-name}

Follow project rules in AGENTS.md, GEMINI.md, and .agents/rules/ if they exist.
```

Omit the tracking-parents line when there are none. With a single track, drop the track headings and the parallel-developers sentence.

## Notes

- If project-specific branching rules exist in `.agents/rules/branching.md`, follow them.
- After `team-develop` completes, follow any PR checklist defined in the project rules.
- `Closes #1, #2` on one line auto-closes only the first issue — put each closing keyword on its own line.
