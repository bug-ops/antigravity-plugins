---
name: team-lead
description: >-
  Shared lead protocol for the dev-agents orchestrators (team-develop, team-debug,
  continuous-improvement): subagent spawning via invoke_subagent, reactive wakeup,
  resuming idle subagents with send_message, naming, workspace modes, and shutdown
  with manage_subagents. Loaded by orchestrators at startup; not for direct user invocation.
---

# Team Lead Protocol

The orchestrator that loaded this skill owns the workflow: chain, task DAG, roster, code ownership, and allowed peer flows. This skill holds the Antigravity subagent mechanics they all share. Where the orchestrator states an override, the override wins.

## 1. Execution Engine (Antigravity Native Subagents)

Antigravity orchestrates specialist agents directly through three built-in tools:

- `invoke_subagent(TypeName, Role, Prompt, Workspace?)` — launches a specialist custom agent (`agents/<TypeName>.md`) asynchronously in the background and returns its `conversationId`.
- `send_message(Recipient, Message)` — sends follow-up instructions to an active or idle subagent by its `conversationId`. Idle subagents automatically re-awaken with their full prior context intact.
- `manage_subagents(Action, ConversationIds?)` — lists active subagents (`list`) or terminates finished ones (`kill` / `kill_all`).

**Reactive wakeup (no polling):** after spawning subagents or messaging them, stop calling tools and end your turn when you have nothing else to do in parallel. Antigravity wakes you automatically whenever a subagent finishes or sends a message. Never poll in a loop or call `sleep`.

**Task DAG tracking:** maintain the chain's task table and `role -> conversationId` map in your own working notes (or a plan artifact for long chains). Never spawn a dependent task until all of its prerequisite handoffs have arrived.

## 2. Spawn Template

Fill this block for every spawn and place it at the top of `Prompt` (`{template}` in the orchestrator):

```text
You are a specialist subagent in this session's dev-agents workflow, role `{role}` (teammate name `{name}`).

Stack: {stack}
Teammates: {names planned for this run}
Peers: {peer flows the orchestrator allows, or "none — report to the lead only"}
Code ownership: {the orchestrator's ownership line for this run}. Only the team lead commits.

Handoff (MANDATORY): BEFORE any other work, read the `agent-handoff` skill (SKILL.md) and follow it, including its "In a Multi-Agent Workflow" section.
```

Teammate-side rules (reporting, ownership, peers, handoff compactness) live in that `agent-handoff` section, which every specialist loads first. Do not restate them in the prompt.

Every spawn uses this form:

```text
invoke_subagent(
  TypeName: "<agent>",
  Role: "<teammate name> — <short role summary>",
  Workspace: "inherit",
  Prompt: "{template}\n\n<task>\n\nHandoffs:\n<accumulated frontmatters>"
)
```

- `TypeName` is the bare custom agent name from `dev-agents/agents/<agent>.md` (for example `architect`, `developer`, `critic`, `code-reviewer`).
- Record the returned `conversationId` under `{name}` so later steps can resume or kill that subagent.
- Keep `Workspace: "inherit"` by default so all agents share the same working tree and `.local/handoff/` directory. Use `Workspace: "share"` only when parallel authors need separate working copies and the lead explicitly merges their changes afterward.

## 3. Subagent Outcomes

Every wakeup from a subagent ends with one of these:

| Outcome | Lead action |
|---|---|
| Handoff frontmatter + path received | Route on the frontmatter as the orchestrator step says |
| Partial reply without a handoff file | Resume with `send_message(Recipient: "{conversationId}", Message: "Continue from where you stopped: write the handoff file under .local/handoff/ and return its frontmatter + path.")`. On a second incomplete reply, report to the user |
| Error / failure (tool error, quota, timeout) | Report the error to the user; to continue, kill the failed subagent and spawn a fresh one under a suffixed name (`reviewer-2`) with the accumulated handoffs |

## 4. Naming and Resuming

- **Resume when context is warm:** for fix cycles, redesign after a critic verdict, or follow-up assessment, send a message to the existing subagent's `conversationId` via `send_message` — it re-awakens with all previously read files and decisions intact.
- **Fresh spawn with suffix when clean context is needed:** append `-2` (then `-3`, ...) to the full teammate name (`developer-2`, `developer-a-2`, `reviewer-2`) whenever a fresh subagent is spawned after a failure, escalation, or second chain in the same session, so handoff filenames never collide.

## 5. Shutdown

Terminate each subagent as soon as no later step of the orchestrator's workflow will message it (the orchestrator lists who stays alive until commit):

```text
manage_subagents(Action: "kill", ConversationIds: ["{conversationId}"])
```

Note: killing a subagent with `Workspace: "share"` or `"branch"` deletes its isolated workspace, so land its changes before killing it.
