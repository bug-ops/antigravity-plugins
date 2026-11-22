---
trigger: model_decision
description: Project-specific continuous improvement configuration (test commands, subsystems, reference projects, security scope)
---

# Continuous Improvement

Project-specific instructions for the continuous improvement cycle.
This file is passed to `live-tester`, `researcher`, `arch-analyst`, and `security-analyst` by `/continuous-improvement`.
Customize the sections below for this project.

## Test Configuration

```bash
# Rust
cargo run --features <flags> -- <args>
```

```bash
# TypeScript (use the project's package manager and scripts)
pnpm run build && node dist/<entry>.js <args>
```

```bash
# Luau / Roblox (server-side probes in a TEST experience; ids and key come from the environment)
rojo build test.project.json -o .local/testing/test.rbxl
rbxcloud luau execute -u "$TEST_UNIVERSE_ID" -i "$TEST_PLACE_ID" -f .local/testing/scripts/<probe>.luau
# Lune tools: lune run <script> <args>
```

For debug output:

```bash
# Rust
RUST_LOG=debug cargo run --features <flags> -- <args> 2>.local/testing/debug/session.log
```

```bash
# TypeScript
NODE_OPTIONS=--enable-source-maps DEBUG=* node dist/<entry>.js <args> 2>.local/testing/debug/session.log
```

```bash
# Luau
lune run <script> <args> > .local/testing/debug/session.log 2>&1
```

## Project Subsystems

<!-- List logical subsystems to track in .local/testing/coverage-status.md -->

## Interfaces

<!-- List supported I/O interfaces for cross-interface consistency testing -->

## Critical Paths

<!-- Features that MUST be live-tested before any PR touching them -->

## Environment Setup

<!-- Required external dependencies for live testing -->

## Reference Projects

<!-- Format: Name — Stack — What to watch -->

## Security Scope

<!-- Trust boundaries, accepted risks, and sensitive assets -->

## Testing Notes

<!-- Known limitations or permanent blockers -->
