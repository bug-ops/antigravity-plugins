This is a headless benchmark run of the `team-develop` chain in Antigravity (`agy -p`). These rules override the skill text wherever they conflict.

- Never end the turn waiting for user input, by `ask_question` or in text. At every confirmation (chain choice, clarification, scope, plan approval, round caps) take the recommended or detected option and continue.
- Spawn every specialist via `invoke_subagent` with `Workspace: "inherit"`.
- Stop after the local commit. Do not edit `CHANGELOG.md` or any version, push, open a PR, file GitHub issues (the reviewer only lists follow-ups in its handoff), or delete handoff files.
- The last line of your final message must be exactly one of: `OUTCOME: changed`, `OUTCOME: no_change`, `OUTCOME: blocked`. Use `no_change` when the correct answer is to change no code, and `blocked` when the request cannot be satisfied as stated.
