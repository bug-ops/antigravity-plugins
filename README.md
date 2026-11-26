# Antigravity Plugins Collection

A curated collection of native plugins for **Google Antigravity** (Antigravity CLI, Antigravity App, Antigravity IDE, and IDE extensions), designed to extend development workflows with specialist subagents, reusable skills, MCP-LSP code intelligence, and lifecycle guard hooks.

## Available Plugins

### `dev-agents`

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](./dev-agents)
[![License](https://img.shields.io/badge/license-MIT-green)](./dev-agents/LICENSE)
[![Stacks](https://img.shields.io/badge/stacks-Rust%20%7C%20TypeScript%20%7C%20Luau-orange)](./dev-agents/README.md#stack-profiles)

Language-agnostic development agents and workflows covering the full software lifecycle, with stack profiles for **Rust**, **TypeScript/JavaScript**, and **Luau/Lua** (including Roblox). Agents carry the process; the `stack` skill detects the project's language and loads the matching rules (toolchain commands, idioms, anti-patterns, checklists). Polyglot repositories load every matching profile.

**Location**: [`./dev-agents`](./dev-agents)

**Key features**:
- **15 custom agents** (`pro` for design, review, debugging, and audit gates; `inherit` for implementation roles; `flash` for high-volume procedural roles) usable both as primary agents (`agy --agent <name>`) and background subagents (`invoke_subagent`)
- **22 productivity skills**:
  - `stack` — Stack detection and per-language reference loader (Rust, TypeScript, Luau/Lua)
  - `team-develop` — Multi-agent development orchestration across 10 task chains (`new-feature`, `spec-driven`, `task-loop`, `bug-fix`, `refactoring`, `security`, `docs`, `dependency`, `performance`, `ci-cd`) with mandatory critic and review gates
  - `team-debug` — Multi-agent root cause investigation (`debugger` + conditional `live-tester` → parallel security/arch/perf review → `code-reviewer` consolidation)
  - `team-lead` — Shared lead protocol for Antigravity native subagents (`invoke_subagent`, `send_message`, `manage_subagents`, reactive wakeup)
  - `agent-handoff` — Compact file-based inter-agent handoff protocol in `.local/handoff/`
  - `solve-issue` & `triage-and-solve` — Priority triage, dependency grouping, worktree/branch setup, and end-to-end GitHub issue resolution
  - `github-issues` — Shared GitHub issue mechanics: capability detection, types, relations, statuses, duplicate search, closing, artifacts
  - `continuous-improvement` — Read-only CI audit cycle (`live-tester` + `researcher` + `arch-analyst` + `security-analyst`), compatible with interactive sessions, `agy -p`, and `/schedule`
  - `live-testing`, `research-protocol`, `arch-inspect`, `security-audit` — Standalone and cycle audit protocols
  - `init-project` — Scaffolds `.local/`, `.agents/rules/`, and `.agents/skills/verify/SKILL.md`
  - `release`, `readme-generator`, `mdbook-tech-writer`, `obsidian-zettelkasten`, `sdd`, `spec-from-stream`, `fast-yaml`, `rust-modern-apis`
- **MCP-to-LSP code intelligence (`mcp_config.json`)** — connects Antigravity to [`mcpls`](https://github.com/bug-ops/mcpls) preconfigured for `rust-analyzer`, `typescript-language-server`, `luau-lsp`, and `lua-language-server`
- **Lifecycle guard hook (`hooks.json` + `scripts/guard.sh`)** — `PreToolUse` protection for `.local/protected-tests`, slopsquatting registry verification (`crates.io`, `npm`, `Wally`, `pesde`), and best-effort read-only / lead-only commit guards

[→ Read full plugin documentation](./dev-agents/README.md)

## Installation

### From a local clone (Antigravity CLI)

```bash
# Validate strictly before installing
agy plugin validate --strict ./dev-agents

# Install into ~/.gemini/config/plugins/dev-agents
agy plugin install ./dev-agents

# Verify discovered agents, skills, hooks, and MCP servers
agy plugin list --json
```

### From GitHub

```bash
agy plugin install https://github.com/bug-ops/antigravity-plugins/tree/main/dev-agents
```

### Workspace-scoped registration (`.agents/plugins.json`)

To share the plugin across a repository without global installation, register its path in `<workspace>/.agents/plugins.json`:

```json
{
  "entries": [
    { "path": "/path/to/antigravity-plugins" }
  ]
}
```

### Prerequisites

- [Google Antigravity](https://antigravity.google/download) (CLI `agy`, App, IDE, or IDE extension)
- `jq` and `bash` (for the `PreToolUse` guard hook)
- [`mcpls`](https://github.com/bug-ops/mcpls) on `PATH` (`cargo install mcpls`) for MCP-to-LSP code intelligence, plus the language servers for the stacks you use:
  - **Rust**: `rustup component add rust-analyzer`
  - **TypeScript/JavaScript**: `npm install -g typescript typescript-language-server`
  - **Luau / Roblox**: `luau-lsp` (and tools pinned in `rokit.toml`); **Lua**: `lua-language-server`

## Usage

```bash
# Launch Antigravity CLI
agy

# List installed agents or start directly as a specialist agent
agy agents
agy --agent architect

# Invoke skills directly in chat
/init-project
/team-develop Add rate limiting to the HTTP API
/team-debug Service times out under concurrent load
/continuous-improvement full
```

## Repository Structure

```text
antigravity-plugins/
├── README.md                      # This file
├── AGENTS.md                      # Contributor & agent guidelines
├── .gitignore
├── .github/
│   ├── workflows/validate.yml     # CI: validation, consistency, hook tests, bench selftest
│   └── scripts/                   # Automated verification scripts
├── bench/                         # On-demand benchmark harness for `agy -p` (see bench/README.md)
└── dev-agents/                    # Native Antigravity plugin
    ├── plugin.json                # Antigravity v1 plugin manifest
    ├── README.md                  # Marketplace & user documentation
    ├── CHANGELOG.md               # Release notes (Keep a Changelog)
    ├── LICENSE                    # MIT
    ├── assets/logo.svg            # Square 128x128 plugin icon
    ├── mcp_config.json            # mcpls MCP-to-LSP server entry
    ├── hooks.json                 # PreToolUse guard hook definition
    ├── scripts/                   # guard.sh, mcpls-lsp.sh, rust-lsp.sh, lua-lsp.sh (0755)
    ├── .devcontainer/             # Containerized dev environment
    ├── agents/                    # 15 custom agent definitions (<name>.md)
    └── skills/                    # 22 skills + stack/references/{rust,typescript,luau}/
```

## Validation & Testing

```bash
agy plugin validate --strict --json ./dev-agents
bash .github/scripts/check-consistency.sh
bash .github/scripts/test-hooks.sh
bash .github/scripts/test-hooks-rules.sh
bash .github/scripts/test-docs-acceptance.sh
bash bench/selftest.sh
```

## License

MIT
