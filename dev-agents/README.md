# dev-agents

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/bug-ops/antigravity-plugins)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Stacks](https://img.shields.io/badge/stacks-Rust%20%7C%20TypeScript%20%7C%20Luau-orange)](#stack-profiles)

Language-agnostic development agents and workflows for **Google Antigravity**, with stack profiles for **Rust**, **TypeScript/JavaScript**, and **Luau/Lua** (including Roblox). Agents carry the engineering process — design, adversarial critique, implementation, testing, code review, security, CI/CD, debugging, and continuous improvement; the `stack` skill supplies the binding language rules for each role. Polyglot repositories load every matching profile.

## Features

- **15 specialist custom agents** (`agents/*.md`) — usable both as background subagents (`invoke_subagent`) and primary session agents (`agy --agent <name>` or Antigravity App agent selector)
- **22 workflow and protocol skills** (`skills/*/SKILL.md`) — progressively disclosed on demand or invoked explicitly via `/<skill-name>`
- **Stack profiles (`skills/stack/`)** — Rust (Edition 2024 + `rust-modern-apis` 1.89–1.100), TypeScript/JavaScript (Node.js, Bun, browser), and Luau/Lua (Roblox/Rojo/Wally/pesde, Lune, Lua 5.1–5.5/LuaJIT)
- **MCP-to-LSP code intelligence (`mcp_config.json`)** — bridges Antigravity to `rust-analyzer`, `typescript-language-server`, `luau-lsp`, and `lua-language-server` via [`mcpls`](https://github.com/bug-ops/mcpls)
- **PreToolUse safety guard (`hooks.json` + `scripts/guard.sh`)** — protects `.local/protected-tests`, checks package registries against slopsquatting, and provides best-effort read-only & lead-only commit protection

## Agents

| Agent | Model Tier | Role |
|-------|------------|------|
| `architect` | `pro` | Type-driven architecture, domain modeling, workspace boundaries, ADRs |
| `developer` | `inherit` | Idiomatic, type-safe implementation, incremental verification, regression-test-first fixes |
| `testing-engineer` | `inherit` | Acceptance tests (tests-first), unit/integration/property tests, mutation testing, redundancy audits |
| `performance-engineer` | `inherit` | CPU/memory profiling, flamegraphs, benchmarking, async/build optimization |
| `security-maintenance` | `pro` | Vulnerability assessment, dependency auditing, secure remediation |
| `code-reviewer` | `pro` | Two-pass code review, full check-suite verification, follow-up issue filing |
| `cicd-devops` | `flash` | GitHub Actions, SHA action pinning, cross-platform CI/CD, caching, release automation |
| `debugger` | `pro` | Systematic root-cause diagnosis, crash/async analysis, prevention protocol |
| `critic` | `pro` | Adversarial design & implementation critique, scope conformance (Dimension 9), follow-up assessment |
| `sdd-orchestrator` | `pro` | Full-cycle Spec-Driven Development: BRD/SRS/NFR → spec/plan/tasks → Obsidian knowledge base |
| `live-tester` | `flash` | Read-only live execution of built artifacts, verification contracts, coverage tracking |
| `tech-writer` | `flash` | User-facing documentation (README, API docs, mdBook) with progressive disclosure |
| `researcher` | `flash` | Read-only dependency monitoring, innovation research, competitive parity |
| `arch-analyst` | `pro` | Read-only architecture and code-quality audits (10 categories) |
| `security-analyst` | `pro` | Read-only vulnerability & attack-surface audits (11 categories) |

**Model tiers** apply when an agent runs as a subagent (`invoke_subagent`); as a primary agent (`agy --agent <name>`) it uses the session model.

- `pro` — gates and judgment-heavy roles whose mistakes propagate downstream: design (`architect`, `sdd-orchestrator`), adversarial and final review (`critic`, `code-reviewer`), root-cause analysis (`debugger`), and security/architecture audits.
- `inherit` — implementation roles (`developer`, `testing-engineer`, `performance-engineer`) follow the session model, so you choose the cost/quality trade-off (for example Orchestrator, or a fast model for routine work); their output always passes `pro` gates.
- `flash` — high-volume, procedure-driven roles (live execution, dependency/parity scans, CI config, documentation) guided by detailed skills and reviewed downstream. `sdd-orchestrator` is pinned to `pro` so specs spawned by `flash` agents do not inherit `flash`.

Reasoning effort cannot be set per agent: Antigravity custom-agent frontmatter has no `effort` field, and the session-level `--effort` / `/effort` setting is the only effort control.

## Skills

### Orchestration & Issue Lifecycle
- **`/team-develop`** — Classifies tasks into 10 chains (`new-feature`, `spec-driven`, `task-loop`, `bug-fix`, `refactoring`, `security`, `docs`, `dependency`, `performance`, `ci-cd`) and coordinates specialist subagents with mandatory `critic` / `impl-critic` and `code-reviewer` gates.
- **`/team-debug`** — Parallel root-cause investigation (`debugger` + conditional `live-tester`) → parallel security/arch/perf reviews → consolidated report → user chooses next steps.
- **`/continuous-improvement [testing|research|dependencies|parity|arch|security|full]`** — Read-only audit cycle (`live-tester`, `researcher`, `arch-analyst`, `security-analyst`) producing a cycle journal in `.local/testing/journal/ci-NNN.md`. Runs interactively, headless (`agy -p "/continuous-improvement full"`), or via `/schedule`.
- **`/solve-issue <n>[,<n>...][;<n>...]`** — Fetches GitHub issue(s), prepares branch/worktree, and drives `/team-develop`.
- **`/triage-and-solve`** — Triages unassigned issues by `P0`–`P4` labels and GitHub dependency relations, groups within a 4-point review budget, and launches `/solve-issue`.
- **`/init-project [--force]`** — Scaffolds `.local/`, `.agents/rules/` (`branching.md`, `commits-and-issues.md`, `continuous-improvement.md`), `.agents/skills/verify/SKILL.md`, and `.gitignore`.
- **`/release [patch|minor|major]`** — Version bump across manifests, lockfile refresh, changelog finalization, docs refresh, pre-release gates, and release PR.

### Protocols & Stack Profiles
- **`stack`** — Detects Rust, TypeScript/JavaScript, and Luau/Lua (including polyglot repos) and loads `toolchain.md` + per-role language rules.
- **`team-lead`** — Shared Antigravity subagent orchestration mechanics (`invoke_subagent`, `send_message`, `manage_subagents`, reactive wakeup).
- **`agent-handoff`** — Structured `.local/handoff/{TS}-{agent}.md` context-sharing protocol with compact frontmatter routing.
- **`github-issues`** — Shared GitHub issue mechanics (capability detection, issue types, relations, statuses, duplicate search, closing, attachments/artifacts) preloaded by `code-reviewer`, `live-tester`, `researcher`, `arch-analyst`, and `security-analyst`.
- **`rust-modern-apis`** — Stable Rust 1.89–1.100 API lookup table loaded automatically by the Rust profile.
- **`/arch-inspect`**, **`/security-audit`**, **`/live-testing`**, **`/research-protocol`** — Specialized audit protocols (when invoked directly, delegate to their dedicated background specialist).

### SDD, Docs & Utilities
- **`/sdd`**, **`/spec-from-stream`**, **`/obsidian-zettelkasten`** — Business requirements (BRD/SRS/NFR), EARS technical specs/plans/tasks, Delta Model, and Zettelkasten vaults.
- **`/readme-generator`**, **`/mdbook-tech-writer`**, **`/fast-yaml`** — README generation, mdBook authoring, and `fy` YAML validation/formatting.

## Stack Profiles

| Profile | Covers | Version Policy | Knowledge Skills |
|---|---|---|---|
| `rust` | Cargo workspaces, Edition 2024 | `rust-version` (MSRV) | `rust-modern-apis` |
| `typescript` | TypeScript & JavaScript (Node.js, Bun, browser; npm/pnpm/yarn/bun) | `engines.node`, `tsconfig` `target`/`lib` | — |
| `luau` | Luau on Roblox (Rojo, Wally/pesde, Rokit) & Lune; Lua 5.1–5.5 / LuaJIT | Live Roblox engine; Lune in `rokit.toml`; rockspec | — |

To add a language: add `skills/stack/references/<language>/` with `toolchain.md` and one file per role, then extend the detection table in `skills/stack/SKILL.md`.

## MCP-to-LSP Integration

Antigravity plugins expose external tools through `mcp_config.json`. This plugin registers `mcpls` via `${PLUGIN_ROOT}/scripts/mcpls-lsp.sh`, which generates a runtime `mcpls.toml` under `${PLUGIN_DATA}` pointing at:

- **Rust**: `scripts/rust-lsp.sh` (`rust-analyzer` with `clippy`, `buildScripts`, `procMacro`, `inlayHints`, and default-toolchain fallback)
- **TypeScript / JavaScript**: `typescript-language-server --stdio`
- **Luau (Roblox & standalone)**: `scripts/lua-lsp.sh luau` (`luau-lsp` with weekly cached Roblox `globalTypes.d.luau`)
- **Lua**: `scripts/lua-lsp.sh lua` (`lua-language-server`)

Install `mcpls` once on your machine (`cargo install mcpls`) and ensure the language servers for your stack are on `PATH`.

## Hooks

`hooks.json` registers a `PreToolUse` guard (`scripts/guard.sh`) matching file-editing tools (`edit_file`, `write_file`, `write_to_file`, `replace_file_content`, `multi_replace_file_content`) and `run_command`:

1. **Protected acceptance tests (deterministic)**: blocks edits to paths listed in `.local/protected-tests`.
2. **Slopsquatting dependency guard (deterministic)**: checks `cargo add`, `npm|pnpm|yarn|bun add|install|i`, and `wally|pesde add` against public registries (`crates.io`, `registry.npmjs.org`, `api.wally.run`, `registry.pesde.dev`) — denies non-existent packages and prompts (`decision: "ask"`) for young (`<30d`), low-download (`<100`), unverified, or hand-edited manifest packages. Respects alternate/private registries.
3. **Read-only role & lead-only commit guards (best-effort)**: enforced unconditionally by agent prompts and backed by `guard.sh` whenever role identity (`agentType` / `agent_type` / `DEV_AGENTS_ROLE`) is present in the hook environment.

## Installation

```bash
# Validate locally
agy plugin validate --strict ./dev-agents

# Install globally (shared across Antigravity CLI, App, and IDE extensions)
agy plugin install ./dev-agents

# Verify
agy plugin list --json
```
