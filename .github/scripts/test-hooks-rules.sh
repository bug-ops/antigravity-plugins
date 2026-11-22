#!/usr/bin/env bash
# Tokenizer edge cases, maturity prompts (ask), conversation-scoped jq prompt, and read-only own-file exemption
# for dev-agents/scripts/guard.sh (Antigravity PreToolUse protojson contract).
set -uo pipefail

guard=$(cd "$(dirname "$0")/../.." && pwd -P)/dev-agents/scripts/guard.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
work=$(cd "$work" && pwd -P)
status=0

mkdir -p "$work/bin" "$work/config" "$work/repo/src" "$work/repo/.local" "$work/repo/tests" "$work/home" "$work/tmp"
git -C "$work/repo" init -q
touch "$work/repo/src/a.rs" "$work/repo/tests/t.rs"
printf 'tests/t.rs\ntests/future.rs\n' >"$work/repo/.local/protected-tests"

ago() {
  date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-"$1"d +%Y-%m-%dT%H:%M:%S
}
export STUB_YOUNG_TS
STUB_YOUNG_TS=$(ago 1)

cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -q ]] || exit 7
url=${*: -1}
args=("$@")
out="" wfmt=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    -o) out=${args[i + 1]} ;;
    -w) wfmt=${args[i + 1]} ;;
  esac
done
old='2020-01-01T00:00:00'
code=200
body='{}'
case $url in
  *zzz-neterr*) exit 6 ;;
  *zzz-missing* | */crates/2 | */2) body='' code=404 ;;
  *crates.io*zzz-young*) body="{\"crate\":{\"created_at\":\"$STUB_YOUNG_TS.123456+00:00\",\"recent_downloads\":50000}}" ;;
  *crates.io*zzz-lowdl*) body="{\"crate\":{\"created_at\":\"$old.123456+00:00\",\"recent_downloads\":3}}" ;;
  *crates.io*zzz-oldpop*) body="{\"crate\":{\"created_at\":\"$old.123456+00:00\",\"recent_downloads\":500000}}" ;;
  *api.npmjs.org*zzz-npmyoung*) body='{"downloads":99999}' ;;
  *api.npmjs.org*zzz-npmlow*) body='{"downloads":3}' ;;
  *api.npmjs.org*zzz-npmpop*) body='{"downloads":500000}' ;;
  *api.npmjs.org*zzz-dlerr*) body='' code=500 ;;
  *registry.npmjs.org*zzz-npmyoung*) body="{\"time\":{\"created\":\"$STUB_YOUNG_TS.000Z\"}}" ;;
  *registry.npmjs.org*zzz-npmlow* | *registry.npmjs.org*zzz-npmpop* | *registry.npmjs.org*zzz-dlerr*) body="{\"time\":{\"created\":\"$old.000Z\"}}" ;;
esac
if [[ -n $out ]]; then
  printf '%s' "$body" >"$out"
  printf '%s' "${wfmt//%\{http_code\}/$code}"
else
  printf '%s%s' "$body" "${wfmt//%\{http_code\}/$code}"
fi
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
  jq -nc --arg tool "$1" --arg args "$2" --arg cwd "$3" --arg at "${4:-}" --arg cid "${5:-conv-1}" '
    {toolCall: {name: $tool, args: ($args | fromjson)}, cwd: $cwd, workspacePaths: [$cwd]}
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

expect_ask() {
  local name=$1 needle=$2 out dec msg
  out=$(run "$3")
  dec=$(decision "$out")
  msg=$(jq -r '.reason // empty' <<<"$out" 2>/dev/null)
  if [[ $dec == ask && $msg == *"$needle"* ]]; then echo "ok   $name"; else
    echo "FAIL $name: expected ask containing '$needle', got $dec: $out" >&2
    status=1
  fi
}

cmd_in() { jq -nc --arg c "$1" '{CommandLine: $c}'; }
file_in() { jq -nc --arg p "$1" '{Path: $p}'; }
bash_as() { payload run_command "$(cmd_in "$2")" "$repo" "$1" "${3:-conv-1}"; }
dev="developer"
nl=$'\n'

# Bypass shapes (deny)
expect deny "git -C with quoted dir" "$(bash_as $dev 'git -C "dir with space" commit -m x')"
expect deny "command git" "$(bash_as $dev 'command git commit -m x')"
expect deny "xargs git" "$(bash_as $dev 'xargs git commit')"
expect deny "exec git" "$(bash_as $dev 'exec git push')"
expect deny "if/then" "$(bash_as $dev 'if true; then git commit -m x; fi')"
expect deny "brace group" "$(bash_as $dev '{ git commit -m x; }')"
expect deny "sudo git" "$(bash_as $dev 'sudo git commit -m x')"
expect deny "absolute path git" "$(bash_as $dev '/usr/bin/git commit -m x')"
expect deny "quoted git" "$(bash_as $dev '"git" commit -m x')"
expect deny "backslash continuation" "$(bash_as $dev "git \\${nl} commit -m x")"
expect deny "time git" "$(bash_as $dev 'time git commit -m x')"
expect deny "nice git" "$(bash_as $dev 'nice git push')"
expect deny "env -i git" "$(bash_as $dev 'env -i git commit -m x')"
expect deny "eval git" "$(bash_as $dev 'eval git commit -m x')"
expect deny "timeout + options" "$(bash_as $dev 'timeout -s KILL -k 5 30s git commit -m x')"
expect deny "wrapper chain" "$(bash_as $dev 'nohup nice -n 5 timeout 60 git push')"
expect deny "nested bash -c" "$(bash_as $dev "bash -c \"bash -c 'git commit -m x'\"")"
expect deny "env -S split string" "$(bash_as $dev "env -S 'git commit -m x'")"

# False positives (allow)
expect allow "FP quoted body line starts with git commit" "$(bash_as $dev "gh issue create --body \"notes${nl}git commit is banned\"")"
expect allow "FP heredoc body inert" "$(bash_as $dev "gh issue create --body-file - <<'EOF'${nl}notes${nl}git push origin${nl}EOF")"
expect allow "FP git log --grep commit" "$(bash_as $dev 'git log --grep commit')"
expect allow "FP main session sudo git commit" "$(bash_as '' 'sudo git commit -m x')"

# Shell-interpreter heredocs & expansions
expect deny "bash heredoc git commit" "$(bash_as $dev "bash <<'EOF'${nl}git commit -m x${nl}EOF")"
expect deny "sh heredoc missing npm pkg" "$(bash_as '' "sh <<'EOF'${nl}npm install zzz-missing-pkg${nl}EOF")"
expect deny "unquoted heredoc \$(git push)" "$(bash_as $dev "gh issue create --body-file - <<EOF${nl}status: \$(git push origin HEAD)${nl}EOF")"
expect deny "herestring bash <<< git push" "$(bash_as $dev "bash <<< 'git push'")"
expect allow "herestring gh inert" "$(bash_as $dev 'gh issue create --body-file - <<< "git push"')"

# Arithmetic & io-number redirects
expect deny "arith shift not a heredoc" "$(bash_as $dev "x=1; (( x = x<<2 ))${nl}git commit -m x")"
expect deny "\$((git push) ) subshell" "$(bash_as $dev 'echo $((git push) )')"
expect allow "\$((1<<3)) allowed" "$(bash_as $dev 'echo $((1<<3))')"
expect allow "cargo add serde 2>&1" "$(bash_as '' 'cargo add serde 2>&1')"
expect deny "2>&1 git commit" "$(bash_as $dev '2>&1 git commit -m x')"

# Maturity warnings -> decision: ask
expect_ask "young crate asks" "zzz-young" "$(bash_as '' 'cargo add zzz-young')"
expect_ask "low-download crate asks with 90 days" "90 days" "$(bash_as '' 'cargo add zzz-lowdl')"
expect allow "old popular crate allowed" "$(bash_as '' 'cargo add zzz-oldpop')"
expect_ask "young npm package asks" "zzz-npmyoung" "$(bash_as '' 'npm install zzz-npmyoung')"
expect_ask "low-download npm asks with last month" "last month" "$(bash_as '' 'npm install zzz-npmlow')"
expect allow "old popular npm allowed" "$(bash_as '' 'npm install zzz-npmpop')"
expect_ask "npm downloads API error asks" "not verified" "$(bash_as '' 'npm install zzz-dlerr')"

extra_env=(DEV_AGENTS_DEP_MIN_AGE_DAYS=0)
expect allow "configurable min-age threshold" "$(bash_as '' 'cargo add zzz-young')"
extra_env=(DEV_AGENTS_DEP_MIN_DOWNLOADS=1)
expect allow "configurable min-downloads threshold" "$(bash_as '' 'cargo add zzz-lowdl')"
extra_env=()

# Read-only role own-file exemption
critic="critic"
reviewer="code-reviewer"
mk() { mkdir -p "$(dirname "$1")"; : >"$1"; }
f=$repo/src/created_by_critic.rs
expect allow "critic writes new file" "$(payload write_file "$(file_in "$f")" "$repo" $critic conv-m11)"
mk "$f"
expect allow "critic edits file it created" "$(payload edit_file "$(file_in "$f")" "$repo" $critic conv-m11)"
expect deny "reviewer cannot edit critic's file" "$(payload edit_file "$(file_in "$f")" "$repo" $reviewer conv-m11)"
expect deny "critic in another conversation cannot edit it" "$(payload edit_file "$(file_in "$f")" "$repo" $critic conv-other)"
expect deny "existing file never created by critic is denied" "$(payload edit_file "$(file_in "$repo/src/a.rs")" "$repo" $critic conv-m11)"

# Forged newline in path cannot grant access
forge="$repo/forged.txt"$'\n'"critic"$'\t'"$repo/src/a.rs"
run "$(payload write_file "$(file_in "$forge")" "$repo" $critic conv-forge)" >/dev/null
expect deny "newline forgery blocked" "$(payload edit_file "$(file_in "$repo/src/a.rs")" "$repo" $critic conv-forge)"

# Missing jq prompts once per conversationId
mkdir -p "$work/nojq" "$work/tmp-m8"
for t in bash env cat git dirname basename readlink realpath grep sed tr awk curl stat date id mkdir chmod mktemp rm head cut ls sort uniq wc find uname cp mv touch pwd sleep; do
  src=$(command -v "$t" 2>/dev/null || true)
  [[ -n $src && $src == /* ]] && ln -sf "$src" "$work/nojq/$t"
done
nojq_dec() {
  local out
  out=$(env PATH="$work/nojq" HOME="$work/home" TMPDIR="$work/tmp-m8" ANTIGRAVITY_CONFIG_DIR="$work/config" \
    "$work/nojq/bash" "$guard" <<<"$1")
  [[ $out == *'"decision":"ask"'* ]] && echo ask || echo allow
}
p_a=$(bash_as $dev 'git status' conv-A)
p_b=$(bash_as $dev 'git status' conv-B)
[[ $(nojq_dec "$p_a") == ask ]] && echo "ok   nojq first call asks" || { echo "FAIL nojq first call" >&2; status=1; }
[[ $(nojq_dec "$p_a") == allow ]] && echo "ok   nojq second call same conversation allows" || { echo "FAIL nojq second call" >&2; status=1; }
[[ $(nojq_dec "$p_b") == ask ]] && echo "ok   nojq new conversation asks again" || { echo "FAIL nojq new conv" >&2; status=1; }

exit "$status"
