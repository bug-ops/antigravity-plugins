#!/usr/bin/env bash
# Machine-checkable doc-level acceptance tests plus scaffold.sh & mcpls-lsp.sh smoke tests.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
status=0
plugin=dev-agents
rust=$plugin/skills/stack/references/rust

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then echo "ok   $name"; else
    echo "FAIL $name" >&2
    status=1
  fi
}
has() { grep -qF -- "$2" "$1"; }

# Rust lint baseline & #[expect] invariants
stray_allow() { [[ -z $(grep -rn --include='*.md' '#\[allow(' "$rust" | grep -vE "^$rust/(critic|arch-inspect)\.md:") ]]; }
check "no #[allow( exception example in rust references" stray_allow
check "init.md has Lint Baseline section" grep -q '^## Lint Baseline' "$rust/init.md"
check "toolchain.md has Lint Policy section" grep -q '^## Lint Policy' "$rust/toolchain.md"
for f in toolchain architect arch-inspect security-audit security; do
  check "$f.md links to init.md#lint-baseline" has "$rust/$f.md" 'init.md#lint-baseline'
done
check "init-project audits Lint Baseline" has "$plugin/skills/init-project/SKILL.md" 'Lint Baseline'
check "developer.md exception form is #[expect]" has "$rust/developer.md" '#[expect('

# Structural API ban (disallowed-methods)
ci_item() { awk '/^2\. If a bug category recurs/{p=1;print;next} p&&/^[0-9]+\. /{exit} p' "$plugin/skills/continuous-improvement/SKILL.md"; }
ci_has() { ci_item | grep -qF -- "$1"; }
check "continuous-improvement step 2 names disallowed-methods" ci_has disallowed-methods
check "continuous-improvement step 2 carries fast-yaml example" ci_has 'saphyr_parser::Parser::new'
check "reviewer.md asks disallowed-methods question" has "$rust/reviewer.md" 'disallowed-methods'
check "developer.md exception is #[expect(clippy::disallowed_methods" has "$rust/developer.md" '#[expect(clippy::disallowed_methods'
check "Lint Policy covers disallowed-methods" has "$rust/toolchain.md" 'disallowed-methods'

# Read-only roles own-reproducer exception
for a in code-reviewer critic arch-analyst security-analyst; do
  check "$a states own-reproducer exception" has "$plugin/agents/$a.md" 'except a reproducer you created in this session'
done

# Stryker never installed implicitly
check "typescript testing.md guards Stryker with --no-install" has "$plugin/skills/stack/references/typescript/testing.md" 'npx --no-install stryker --version'

# Bench hidden test canaries
canary_missing() { [[ -n $(ls -d bench/tasks/*/hidden 2>/dev/null) && -z $(grep -rL 'BENCH-HIDDEN-CANARY' bench/tasks/*/hidden) ]]; }
check "every bench hidden file has BENCH-HIDDEN-CANARY" canary_missing
canary_edges() {
  local f n=0
  while IFS= read -r f; do
    n=$((n + 1))
    head -n 3 "$f" | grep -qF BENCH-HIDDEN-CANARY || return 1
    tail -n 3 "$f" | grep -qF BENCH-HIDDEN-CANARY || return 1
  done < <(find bench/tasks -path '*/hidden/*' -type f)
  ((n > 0))
}
check "canary is within first 3 and last 3 lines of every hidden file" canary_edges

# scaffold.sh smoke test on Rust + TypeScript + Luau fixture
scaffold_smoke() {
  local tmp rc=0
  tmp=$(mktemp -d)
  printf '[package]\nname = "demo"\nversion = "0.1.0"\nedition = "2024"\n' >"$tmp/Cargo.toml"
  printf '{"name":"demo-ui","scripts":{"test":"vitest run"}}\n' >"$tmp/package.json"
  printf '{"name":"demo-game"}\n' >"$tmp/default.project.json"
  if (cd "$tmp" && bash "$OLDPWD/$plugin/skills/init-project/scripts/scaffold.sh") &&
    [[ -d "$tmp/.local/handoff" ]] &&
    [[ -d "$tmp/.agents/rules" ]] &&
    [[ -f "$tmp/.agents/skills/verify/SKILL.md" ]] &&
    [[ -f "$tmp/.local/testing/coverage-status.md" ]] &&
    grep -qF '.local/' "$tmp/.gitignore" &&
    ! grep -qF '.claude/' "$tmp/.gitignore"; then
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}
check "scaffold.sh creates .local/, .agents/rules/, and .agents/skills/verify/SKILL.md" scaffold_smoke

# mcpls-lsp.sh dry-run config generation smoke test
mcpls_smoke() {
  local tmp cfg rc=0
  tmp=$(mktemp -d)
  mkdir -p "$tmp/bin" "$tmp/data"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/mcpls"
  chmod +x "$tmp/bin/mcpls"
  if cfg=$(PATH="$tmp/bin:$PATH" PLUGIN_ROOT="$PWD/$plugin" PLUGIN_DATA="$tmp/data" DEV_AGENTS_MCPLS_DRY_RUN=1 \
      bash "$plugin/scripts/mcpls-lsp.sh") &&
    [[ -f $cfg ]] &&
    grep -qF 'rust-analyzer' "$cfg" &&
    grep -qF 'typescript-language-server' "$cfg" &&
    grep -qF 'luau-lsp' "$cfg" &&
    grep -qF 'lua-language-server' "$cfg" &&
    grep -qF "$PWD/$plugin/scripts/rust-lsp.sh" "$cfg" &&
    grep -qF "$PWD/$plugin/scripts/lua-lsp.sh" "$cfg"; then
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}
check "mcpls-lsp.sh generates valid mcpls.toml for Rust, TS, Luau, and Lua" mcpls_smoke

exit "$status"
