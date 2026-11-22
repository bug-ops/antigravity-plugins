#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(pwd)"

echo "========================================="
echo "Running post-create setup..."
echo "========================================="

echo "Updating Rust toolchain..."
rustup update stable
rustup default stable

echo ""
echo "Rust toolchain information:"
rustc --version
cargo --version
rustfmt --version
clippy-driver --version
mcpls --version || true

echo ""
echo "Configuring git..."
git config --global --add safe.directory "$WORKSPACE"

echo ""
echo "Setting up sccache..."
mkdir -p ~/.cache/sccache

echo ""
echo "Installing TypeScript tooling..."
npm install -g typescript typescript-language-server pnpm

echo ""
echo "Ensuring Antigravity config directory..."
mkdir -p ~/.gemini/config/plugins

if command -v agy >/dev/null 2>&1; then
  echo "Validating and installing dev-agents plugin with agy..."
  if [[ -f "$WORKSPACE/plugin.json" ]]; then
    agy plugin validate --strict "$WORKSPACE"
    agy plugin install "$WORKSPACE"
    agy plugin list
  else
    echo "Warning: plugin.json not found at $WORKSPACE/plugin.json"
  fi
else
  echo "Note: Antigravity CLI (agy) is not installed in the container yet."
  echo "Install it from https://antigravity.google/download and then run:"
  echo "  agy plugin validate --strict $WORKSPACE"
  echo "  agy plugin install $WORKSPACE"
fi

echo ""
echo "========================================="
echo "Development environment ready!"
echo "========================================="
echo "Workspace: $WORKSPACE"
echo "User: $(whoami)"
echo "MCP-LSP bridge: mcpls ($(command -v mcpls || echo 'not installed'))"
echo "LSP servers: rust-analyzer, typescript-language-server, luau-lsp, lua-language-server"
echo "========================================="
