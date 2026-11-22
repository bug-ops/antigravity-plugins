---
name: init-project
description: >-
  Initialize a Rust, TypeScript, Luau/Lua, or polyglot project for the
  dev-agents plugin: scaffold .local/ working directories, .agents/rules/
  project rules, testing knowledge base, a project verify skill, and .gitignore
  entries. Run once when starting a new project.
disable-model-invocation: true
---

# Initialize Project for dev-agents

Scaffold all directories, project rules, and knowledge base files required by the `dev-agents` plugin — agent handoffs, testing infrastructure, branching conventions, and a project `verify` skill. Works for Rust (`Cargo.toml`), TypeScript/JavaScript (`package.json`, `tsconfig.json`), Luau/Lua (Rojo, Wally, pesde, rockspec), and polyglot repositories.

Pass `--force` to regenerate `.agents/skills/verify/SKILL.md` and `.agents/rules/` files. Knowledge-base files under `.local/testing/` (coverage status, regressions, process notes, playbooks) are never overwritten.

## Steps

**1. Pre-flight checks**

- Stack detection is handled by `scripts/scaffold.sh`: it stops with an error when no Rust, TypeScript, or Luau/Lua marker exists at the root or one level down.
- An existing `.local/` is fine: the script creates only what is missing.

**2. Run scaffold script**

Execute `scripts/scaffold.sh` (located in this skill's directory; pass `--force` if requested):

```bash
bash "<path-to-this-skill>/scripts/scaffold.sh" [--force]
```

The script detects the stacks (`Detected stacks: ...` line), enumerates units (Cargo workspace crates, TypeScript workspace packages, Luau/Lua roots), creates `.local/handoff/`, `.local/testing/`, `.gitignore` entries (`.local/`), `.agents/rules/`, and `.agents/skills/verify/SKILL.md`.

**3. Apply the stack profiles**

For every detected stack, read `../stack/references/<profile>/init.md` (`rust`, `typescript`, `luau`) and `../stack/references/<profile>/toolchain.md`. Use them to review the generated files: correct the verify skill's run commands, unit names, and package manager where the scaffold guessed wrong, and add logical subsystems to `.local/testing/coverage-status.md`.

For every profile whose `init.md` has a `## Lint Baseline` section, audit the project against it and keep each gap as an unchecked item for the step 5 summary. Never edit manifests or lint configs.

**4. Create project rules**

For each rule template in `references/rules/`, create the corresponding file in `.agents/rules/` ONLY if it does not exist (or `--force`):

| Template | Target | Used by |
|----------|--------|---------|
| [branching.md](references/rules/branching.md) | `.agents/rules/branching.md` | `/solve-issue`, `/release` |
| [commits-and-issues.md](references/rules/commits-and-issues.md) | `.agents/rules/commits-and-issues.md` | `team-develop`, `code-reviewer`, `/solve-issue` |
| [continuous-improvement.md](references/rules/continuous-improvement.md) | `.agents/rules/continuous-improvement.md` | `live-tester`, `researcher`, `arch-analyst`, `security-analyst`, `/continuous-improvement` |

Read each template and write to the target path. While writing:
- Fill the pre-PR check block in `branching.md` with the full check suite from each detected profile's `toolchain.md` — or, when the project's CI workflow or `package.json` scripts define the checks, with those exact commands.
- Keep the example blocks for detected stacks only; drop the others.

**5. Print summary**

Report what was created (including detected stacks and units), the Lint Baseline gaps as a checklist, and next steps:
0. Review `.agents/skills/verify/SKILL.md` — it is the project's shared build/run/test recipe used by `live-tester` and `/verify`; fix run commands if the scaffold guessed wrong.
1. Edit `.agents/rules/branching.md` with project branching conventions.
2. Edit `.agents/rules/commits-and-issues.md` to confirm or customize commit types and issue labels.
3. Edit `.agents/rules/continuous-improvement.md` with test configs, subsystems, and reference projects.
4. Run `/continuous-improvement` to start the first CI cycle.
5. Use `/solve-issue <number>` to solve GitHub issues.

## References

- [File Templates](references/templates.md) — knowledge base file formats and entry templates
- [Branching Rules](references/rules/branching.md) — branch naming convention template
- [Commits and Issues](references/rules/commits-and-issues.md) — Conventional Commits format and issue filing protocol
- [CI Rules](references/rules/continuous-improvement.md) — continuous improvement cycle template
- Stack profiles: `../stack/references/<profile>/init.md` — per-language scaffold facts
