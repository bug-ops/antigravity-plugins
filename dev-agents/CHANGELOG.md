# Changelog

All notable changes to the `dev-agents` plugin for Google Antigravity are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-22

### Added
- Native Google Antigravity plugin manifest (`plugin.json` matching `https://antigravity.google/schemas/v1/plugin.json`) and bundled square SVG logo (`assets/logo.svg`).
- 15 specialist custom agents (`architect`, `developer`, `testing-engineer`, `performance-engineer`, `security-maintenance`, `code-reviewer`, `cicd-devops`, `debugger`, `critic`, `sdd-orchestrator`, `live-tester`, `tech-writer`, `researcher`, `arch-analyst`, `security-analyst`) with `pro` model tier for deep-reasoning roles and `inherit` for execution roles.
- 21 workflow and protocol skills including Rust, TypeScript/JavaScript, and Luau/Lua (Roblox) stack profiles (`skills/stack/`), Rust 1.89–1.100 modern API reference (`rust-modern-apis`), file-based handoff protocol (`agent-handoff`), SDD pipeline (`sdd`, `spec-from-stream`, `obsidian-zettelkasten`), and multi-agent orchestrators (`team-lead`, `team-develop`, `team-debug`, `continuous-improvement`) powered by Antigravity native subagents (`invoke_subagent`, `send_message`, `manage_subagents`, `ask_question`).
- MCP-to-LSP bridge configuration (`mcp_config.json`) via `mcpls` with `scripts/mcpls-lsp.sh`, `scripts/rust-lsp.sh`, and `scripts/lua-lsp.sh` covering `rust-analyzer`, `typescript-language-server`, `luau-lsp`, and `lua-language-server`.
- Native Antigravity `PreToolUse` safety guard (`hooks.json` + `scripts/guard.sh`) enforcing `.local/protected-tests`, slopsquatting registry verification for Rust/npm/Wally/pesde packages, and best-effort read-only/lead-only commit guards.
- Project scaffolding skill (`init-project`) targeting `.agents/rules/`, `.agents/skills/verify/SKILL.md`, and `.local/`.
- DevContainer configuration (`.devcontainer/`), GitHub Actions validation workflow, offline hook and consistency tests, and `bench/` evaluation harness for `agy -p`.

[Unreleased]: https://github.com/bug-ops/antigravity-plugins/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bug-ops/antigravity-plugins/releases/tag/v1.0.0
