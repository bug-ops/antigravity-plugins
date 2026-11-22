#!/usr/bin/env bash
# Feeds synthetic Antigravity PreToolUse payloads (camelCase protojson) to dev-agents/scripts/guard.sh
# and checks allow / deny / ask decisions. Registry lookups use a stub curl (offline, deterministic).
set -euo pipefail

guard=$(cd "$(dirname "$0")/../.." && pwd -P)/dev-agents/scripts/guard.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
work=$(cd "$work" && pwd -P)
status=0

mkdir -p "$work/bin" "$work/config" "$work/artifacts" \
  "$work/repo/src" "$work/repo/.local" "$work/repo/tests" "$work/other/src" "$work/home" "$work/tmp"
git -C "$work/repo" init -q
git -C "$work/other" init -q
touch "$work/repo/src/a.rs" "$work/repo/tests/t.rs" "$work/other/src/b.rs" "$work/artifacts/plan.md"
printf 'tests/t.rs\n' >"$work/repo/.local/protected-tests"

cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=${*: -1}
[[ $1 == -q ]] || exit 7
args=("$@")
out=""
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ ${args[i]} == -o ]] && out=${args[i + 1]}
done
body='{}'
code=200
case $url in
  *zzz-neterr*) exit 6 ;;
  *zzz-missing*) body='' code=404 ;;
esac
printf '%s' "$body" >"$out"
printf '%s' "$code"
EOF
chmod +x "$work/bin/curl"

extra_env=()
repo=$work/repo

run() {
  env -u CARGO_HOME -u NPM_CONFIG_USERCONFIG -u DEV_AGENTS_ROLE "${extra_env[@]+"${extra_env[@]}"}" \
    PATH="$work/bin:$PATH" HOME="$work/home" TMPDIR="$work/tmp" \
    ANTIGRAVITY_CONFIG_DIR="$work/config" bash "$guard" <<<"$1"
}

payload() {
  jq -nc --arg tool "$1" --arg args "$2" --arg cwd "$3" --arg at "${4:-}" --arg cid "${5:-conv-1}" --arg art "$work/artifacts" '
    {
      toolCall: { name: $tool, args: ($args | fromjson) },
      cwd: $cwd,
      workspacePaths: [$cwd],
      artifactDirectoryPath: $art
    }
    + (if $cid != "-" then {conversationId: $cid} else {} end)
    + (if $at != "" then {agentType: $at} else {} end)'
}

decision() { jq -r '.decision // "invalid"' <<<"$1" 2>/dev/null || echo invalid; }

expect() {
  local want=$1 name=$2 out got
  out=$(run "$3")
  got=$(decision "$out")
  if [[ $got == "$want" ]]; then echo "ok   $name"; else
    echo "FAIL $name: expected $want, got $got: $out" >&2
    status=1
  fi
}

cli_file() { jq -nc --arg p "$1" '{Path: $p}'; }
ide_file() { jq -nc --arg p "$1" '{TargetFile: $p}'; }
cmd_in() { jq -nc --arg c "$1" '{CommandLine: $c}'; }

# Rule 1: Read-only role enforcement (CLI and IDE file-edit tools)
expect deny "R1 critic edit_file existing source" "$(payload edit_file "$(cli_file "$repo/src/a.rs")" "$repo" critic)"
expect deny "R1 code-reviewer replace_file_content existing source" "$(payload replace_file_content "$(ide_file "$repo/src/a.rs")" "$repo" code-reviewer)"
expect allow "R1 critic write_file under .local/" "$(payload write_file "$(cli_file "$repo/.local/handoff/x.md")" "$repo" critic)"
expect allow "R1 critic write_file inside artifactDirectoryPath" "$(payload write_file "$(cli_file "$work/artifacts/plan.md")" "$repo" critic)"
expect allow "R1 critic write_file new reproducer file" "$(payload write_file "$(cli_file "$repo/src/repro.rs")" "$repo" critic)"
expect allow "R1 developer edit_file existing source" "$(payload edit_file "$(cli_file "$repo/src/a.rs")" "$repo" developer)"
expect allow "R1 main session (no role) edit_file existing source" "$(payload edit_file "$(cli_file "$repo/src/a.rs")" "$repo")"

# Rule 2: Protected acceptance tests (role-agnostic, CLI & IDE tools)
expect deny "R2 protected test blocked for developer (edit_file)" "$(payload edit_file "$(cli_file "$repo/tests/t.rs")" "$repo" developer)"
expect deny "R2 protected test blocked for main session (replace_file_content)" "$(payload replace_file_content "$(ide_file "$repo/tests/t.rs")" "$repo")"
expect deny "R2 protected test blocked via relative path" "$(payload edit_file "$(cli_file "tests/t.rs")" "$repo")"
expect deny "R2 role cannot edit .local/protected-tests marker" "$(payload write_file "$(cli_file "$repo/.local/protected-tests")" "$repo" developer)"
expect allow "R2 lead (no role) may edit .local/protected-tests marker" "$(payload write_file "$(cli_file "$repo/.local/protected-tests")" "$repo")"
expect deny "R2 unresolvable .. after missing dir is denied when marker exists" "$(payload edit_file "$(cli_file "$repo/no-such-dir/../tests/t.rs")" "$repo")"

# Rule 3: Lead-only commits (best-effort when role is set via payload or env)
expect deny "R3 developer git commit denied" "$(payload run_command "$(cmd_in 'git commit -m test')" "$repo" developer)"
expect deny "R3 developer git push denied" "$(payload run_command "$(cmd_in 'git push origin main')" "$repo" developer)"
extra_env=(DEV_AGENTS_ROLE=developer)
expect deny "R3 DEV_AGENTS_ROLE env blocks git commit" "$(payload run_command "$(cmd_in 'git commit -m test')" "$repo")"
extra_env=()
expect allow "R3 main session git commit allowed" "$(payload run_command "$(cmd_in 'git commit -m test')" "$repo")"
expect allow "R3 developer git status allowed" "$(payload run_command "$(cmd_in 'git status')" "$repo" developer)"

# Rule 4: Slopsquatting registry checks
expect deny "R4 missing crate denied" "$(payload run_command "$(cmd_in 'cargo add zzz-missing-crate')" "$repo")"
expect allow "R4 existing crate allowed" "$(payload run_command "$(cmd_in 'cargo add serde')" "$repo")"
expect deny "R4 missing npm package denied" "$(payload run_command "$(cmd_in 'npm install zzz-missing-pkg')" "$repo")"
expect allow "R4 existing npm package allowed" "$(payload run_command "$(cmd_in 'pnpm add vitest')" "$repo")"
expect ask "R4 missing scoped npm package asks" "$(payload run_command "$(cmd_in 'npm install @priv/zzz-missing-pkg')" "$repo")"
expect ask "R4 network error asks instead of denying" "$(payload run_command "$(cmd_in 'cargo add zzz-neterr')" "$repo")"
expect allow "R4 path dependency skips registry check" "$(payload run_command "$(cmd_in 'cargo add --path ../foo zzz-missing-crate')" "$repo")"
expect ask "R4 hand-edited Cargo.toml missing crate asks" \
  "$(payload edit_file "$(jq -nc --arg p "$repo/Cargo.toml" --arg r $'[dependencies]\nzzz-missing-crate = "1.0"\n' '{Path:$p,Replacement:$r}')" "$repo")"

# Alternate registry bypass
mkdir -p "$repo/.cargo"
printf '[registries.corp]\nindex = "https://corp.invalid/index"\n' >"$repo/.cargo/config.toml"
expect allow "R4 alt cargo registry skips crates.io lookup" "$(payload run_command "$(cmd_in 'cargo add zzz-missing-crate')" "$repo")"
rm -rf "$repo/.cargo"

# Unknown tool passes cleanly
expect allow "unknown tool allowed" "$(payload read_file '{"Path":"/tmp/x"}' "$repo")"

exit "$status"
