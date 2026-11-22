---
name: agent-handoff
description: >-
  File-based handoff protocol for the dev-agents multi-agent system. Subagents
  communicate via Markdown+frontmatter files in .local/handoff/. Always read
  at agent startup before doing work.
---

# Agent Handoff Protocol

Subagents work in isolated contexts. This protocol enables compact, structured communication via Markdown + YAML frontmatter files in `.local/handoff/`.

## File Path

`.local/handoff/{TS}-{agent}.md`, where `{TS}` is a `YYYY-MM-DDTHH-MM-SS` timestamp taken when you write the file, and `{agent}` is your teammate name (`developer-a`, `impl-critic`) when your prompt specifies one, otherwise your role suffix. Parallel agents of one role then never share a filename. The role suffix also selects your Output schema (`{role}`):

`architect` · `developer` · `testing` · `performance` · `security` · `review` · `cicd` · `debug` · `critic` · `live-tester` · `researcher` · `arch-analyst` · `security-analyst` · `tech-writer` · `sdd-orchestrator`

## On Startup

1. Read `references/{role}.md` relative to this skill directory for your Output schema. Exception: `arch-analyst` and `security-analyst` take their Output schema from their audit skill (`../arch-inspect/SKILL.md` / `../security-audit/SKILL.md`) — skip this read.
2. Parent handoff frontmatter arrives inline in your task prompt — that is routing metadata. Read a full handoff body only when you need detailed context (using your file-read tool on `.local/handoff/{id}.md`).
3. For grandparent+ chains, read only the YAML frontmatter block (lines between the first two `---` markers) rather than the full body.

## Before Finishing

1. Run `date +%Y-%m-%dT%H-%M-%S && mkdir -p .local/handoff` in one command; `{HANDOFF_ID}` is that timestamp, a dash, and `{agent}`.
2. Write `.local/handoff/{HANDOFF_ID}.md` using the literal path:

~~~markdown
---
id: {HANDOFF_ID}
parent: {parent-id | [id1, id2] | null}
agent: {agent}
status: {completed | blocked | needs_discussion | no_change_needed}
verdict: {reviewer and critic only, values in your Output schema; omit for every other agent}
summary: "One sentence: what was done + key artifact"
next_agent: {suffix | null}
next_task: "Short imperative task, or empty"
follow_ups: {number of Follow-ups entries, 0 when none}
---

## Context
Stack: {profiles and reference files read, per the stack skill — e.g. `rust (toolchain, developer)`; omit for agents that do not load stack}
{<=2 sentences: constraints or decisions the next agent cannot get from the frontmatter chain. Do NOT restate the task or parent summaries.}

## Output
{Per references/{role}.md schema.}
~~~

Frontmatter uses flat scalars only; the only allowed array is `parent: [id1, id2]` when parallel work converges on one agent.

`no_change_needed` is returned only by the `architect` and the `debugger`, when the request is already satisfied or the code behaves as intended. Its `## Evidence` section holds the reproduction attempt (command and output) or the code (`file:line`) that already satisfies the request. The lead stops the chain and reports the evidence to the user.

Conditional sections: `## Blockers` if `status: blocked`; `## Acceptance Criteria` if `next_task` needs more than one line; `## Follow-ups` if `follow_ups` is above 0; `## Evidence` if `status: no_change_needed`. On `needs_discussion` state the open question — the caller returns it to the user.

### Follow-ups

Work outside this task's scope that must not be lost: a defect you found, a capability the code needs but the task does not cover, tech debt, or a `TODO` marker you placed in code. Every `TODO`/`FIXME` you add has an entry. One entry per item:

`F1` — `defect | enhancement | tech-debt | todo | security` — `file:line` — what is wrong or missing — evidence (failing input, command, log line) — expected vs. actual (defects) — why it is outside this task — suggested priority `P0`–`P4`

In `team-develop` and `team-debug` runs you never file issues yourself: the lead collects every handoff with `follow_ups` above 0, the critic checks each entry against the evidence and the declared architecture, plan, and spec, and the reviewer files the confirmed ones (in `team-debug`, which has no critic, the reviewer checks them and files after the user approves). Record only what you can back with evidence or a reference — an unsupported entry is rejected. Agents with their own filing protocol (`live-tester`, `researcher`, `arch-analyst`, `security-analyst`) keep it only in standalone and `continuous-improvement` runs. An item that blocks your own task is not a follow-up — hand off with `status: blocked`. Additions the critic asked to remove are not follow-ups unless the user chose to keep the idea for later.

3. Return frontmatter + path to the caller — the parent routes without reading the file. Include the block below in your final response (or `send_message` to the parent if explicitly given a parent conversation ID):

~~~markdown
## Handoff
**File:** `.local/handoff/{HANDOFF_ID}.md`
**Frontmatter:**
```yaml
{the frontmatter block above}
```
~~~

## In a Multi-Agent Workflow

When your prompt places you in a `dev-agents` orchestrated workflow, its `Teammates:`, `Peers:`, and `Code ownership:` lines govern your actions:

- **Report**: end your turn with the Handoff block above so the lead wakes automatically with your frontmatter and file path (and use `send_message` only when addressing a peer whose `conversationId` the lead provided).
- **Ownership**: edit only what the `Code ownership:` line allows; everything else is a finding in your handoff. Only the lead commits. The prompt rule always applies; the plugin's `PreToolUse` hook backs `.local/protected-tests`, dependency checks, and (where role identity is present) read-only/commit rules.
- **Peers**: message another specialist only for the flows the `Peers:` line names and only when the lead supplies its `conversationId`. Results, blockers, scope questions, and anything that changes the plan go to the lead.
- **Idle/Resume**: after you finish your turn, you may be re-awakened later with a follow-up message (fix cycle, redesign, re-review) carrying your full prior context. Write a new timestamped handoff file for each round.

## Compactness Rules

Every handoff body is re-read by downstream agents — each extra line costs tokens on every read:

- Never restate the task, parent summaries, or anything the frontmatter chain already carries.
- Never list what `git diff` shows: no function/test name listings, no code snippets. Counts + paths + one-line descriptions. Exception: debugger — the fix snippet IS the payload.
- Omit empty or inapplicable sections entirely. No decorative estimates or filler prose.
- Aim for <=40 lines of body; never pad.
