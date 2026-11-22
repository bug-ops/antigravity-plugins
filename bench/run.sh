#!/usr/bin/env bash
# Runs bench tasks through the team-develop chain and a single developer agent on `agy -p`.
# See bench/README.md. Free self-check: --check. Quick paid check: --probe --yes-spend.
set -euo pipefail

BENCH_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(dirname "$BENCH_DIR")
STATE_DIR=${BENCH_STATE_DIR:-$HOME/.cache/dev-agents-bench/antigravity}
SENTINEL=.dev-agents-bench
PLUGIN_SRC=$REPO_DIR/dev-agents
PROBE_TOKEN=BENCH-PROBE-7f3a91c2
PRINT_TIMEOUT=${BENCH_PRINT_TIMEOUT:-30m}
SINGLE_NOTE='Work autonomously and never ask a question. Do not spawn subagents, commit, push, open a PR, or edit CHANGELOG.md.'

MODE=run
ARM=both
YES_SPEND=0
TASKS=()
ARGS=()
RC=0
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

die() { echo "bench: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage: bench/run.sh [--init | --check | --probe] [--yes-spend] [--plugin-dir PATH] [--arm chain|single|both] [task...]
  --init        free: create the bench state dir (must not exist or be empty) and its marker file
  --check       free: verify the bench state dir and plugin manifest are valid, then exit
  --probe       quick paid run that checks the harness assumptions; needs --yes-spend
  --yes-spend   confirm that this invocation calls the paid API / model quota (never implied)
  --plugin-dir  plugin under test (default: <repo>/dev-agents); staged into each workspace
  --arm         which arm to run (default both)
env: BENCH_STATE_DIR (bench state dir), BENCH_PRINT_TIMEOUT (default 30m), BENCH_MODEL (optional --model)
EOF
}

require_tools() {
  local t
  for t in agy jq git; do command -v "$t" >/dev/null || die "missing required tool: $t"; done
}

refuse_real_config_dir() {
  local canonical home_gemini
  canonical=$(cd "$STATE_DIR" && pwd -P)
  home_gemini=$(cd "$HOME" && pwd -P)/.gemini
  [[ $canonical != "$home_gemini" && $canonical != "$home_gemini"/* ]] ||
    die "BENCH_STATE_DIR must not be inside ~/.gemini"
}

init_state() {
  mkdir -p "$STATE_DIR"
  refuse_real_config_dir
  [[ -z $(ls -A "$STATE_DIR") ]] || die "$STATE_DIR is not empty; --init only creates a fresh bench state dir"
  : >"$STATE_DIR/$SENTINEL"
  echo "bench: created $STATE_DIR"
}

check_state() {
  [[ -d $STATE_DIR ]] || die "no bench state dir at $STATE_DIR; run: bench/run.sh --init"
  refuse_real_config_dir
  [[ -f $STATE_DIR/$SENTINEL ]] || die "$STATE_DIR has no $SENTINEL marker; refusing to touch it. Use --init on a fresh path"
  agy plugin validate --strict "$PLUGIN_SRC" >/dev/null || die "plugin validation failed for $PLUGIN_SRC"
}

confirm_spend() {
  local label=$1
  echo "bench: this invocation runs agy -p ($label) and consumes model quota/credits" >&2
  ((YES_SPEND == 1)) || die "not started: add --yes-spend to confirm"
}

scaffold() {
  local fixture=$1 name=$2 ws
  ws=$(mktemp -d)
  cp -R "$fixture/." "$ws/"
  mkdir -p "$ws/.agents/plugins/dev-agents"
  cp -R "$PLUGIN_SRC/." "$ws/.agents/plugins/dev-agents/"
  # Exclude workspace plugin staging from git status/diff
  mkdir -p "$ws/.git"
  git -C "$ws" init -q
  printf '.agents/\n' >>"$ws/.git/info/exclude"
  git -C "$ws" config user.name bench
  git -C "$ws" config user.email bench@example.invalid
  git -C "$ws" config commit.gpgsign false
  git -C "$ws" add -A
  git -C "$ws" commit -q -m scaffold
  git -C "$ws" tag bench-scaffold
  git -C "$ws" checkout -q -b "bench/$name"
  echo "$ws"
}

build_args() {
  ARGS=(-p --output-format stream-json --sandbox --mode accept-edits --print-timeout "$PRINT_TIMEOUT")
  if [[ -n ${BENCH_MODEL:-} ]]; then
    ARGS+=(--model "$BENCH_MODEL")
  fi
}

run_agy() {
  local ws=$1 prompt=$2 dir=$3
  : >"$dir/stream.jsonl"
  RC=0
  (cd "$ws" && exec agy "${ARGS[@]}" "$(cat "$prompt")" >"$dir/stream.jsonl" 2>"$dir/stderr.log") || RC=$?
  ((RC == 0)) || echo "bench: warning: agy exited with $RC (see $dir/stderr.log)" >&2
}

tool_inputs_leaking() {
  local f=$1
  {
    grep -F 'BENCH-HIDDEN-CANARY' "$f" || true
    grep -F -e "$REPO_DIR" -e '/hidden/' "$f" || true
    grep -E '(\.ssh|\.aws|\.gnupg)([/" ,}\\]|$)' "$f" || true
  }
}

post_checks() {
  local dir=$1 leaks
  leaks=$(tool_inputs_leaking "$dir/stream.jsonl")
  [[ -z $leaks ]] || die "run invalid: stream references the repo path, /hidden/, or hidden-test canary (see $dir/stream.jsonl)"
}

run_arm() {
  local task=$1 arm=$2 dir ws
  dir=$RESULTS/$task-$arm
  mkdir -p "$dir"
  ws=$(scaffold "$BENCH_DIR/tasks/$task/fixture" "$task")
  printf '%s\n' "$ws" >"$dir/workspace.path"
  build_args
  case $arm in
    chain)
      printf '%s\n\n/team-develop %s\n' "$(cat "$BENCH_DIR/chain-preamble.md")" "$(cat "$BENCH_DIR/tasks/$task/task.md")" >"$dir/prompt.txt"
      ;;
    single)
      ARGS+=(--agent developer)
      printf '%s\n\n%s\n' "$(cat "$BENCH_DIR/tasks/$task/task.md")" "$SINGLE_NOTE" >"$dir/prompt.txt"
      ;;
    *) die "unknown arm: $arm" ;;
  esac
  echo "bench: $task / $arm" >&2
  run_agy "$ws" "$dir/prompt.txt" "$dir"
  post_checks "$dir"
}

record_toolchains() {
  { command -v agy cargo node git || true; } >"$RESULTS/toolchains.txt"
}

run_bench() {
  local task
  [[ ${#TASKS[@]} -gt 0 ]] || while IFS= read -r task; do TASKS+=("$task"); done < <(ls "$BENCH_DIR/tasks")
  for task in "${TASKS[@]}"; do [[ -d $BENCH_DIR/tasks/$task ]] || die "unknown task: $task"; done
  confirm_spend "${#TASKS[@]} task(s), arm=$ARM"
  mkdir -p "$RESULTS"
  record_toolchains
  for task in "${TASKS[@]}"; do
    if [[ $ARM != single ]]; then
      run_arm "$task" chain
    fi
    if [[ $ARM != chain ]]; then
      run_arm "$task" single
    fi
  done
  "$BENCH_DIR/score.sh" "$RESULTS"
}

probe() {
  local fx hidden ws dir res failed=0
  confirm_spend "probe"
  mkdir -p "$RESULTS"
  record_toolchains
  fx=$(mktemp -d "$SCRATCH/fixture.XXXXXX")
  mkdir -p "$fx/src"
  printf '[package]\nname = "probe"\nversion = "0.1.0"\nedition = "2021"\n' >"$fx/Cargo.toml"
  printf '#[test]\nfn works() {}\n' >"$fx/src/lib.rs"
  printf 'import { test } from "node:test";\ntest("works", () => {});\n' >"$fx/probe.test.mjs"
  hidden=$(mktemp -d)
  echo "$PROBE_TOKEN" >"$hidden/secret.txt"
  ws=$(scaffold "$fx" probe)
  dir=$RESULTS/probe-tools
  mkdir -p "$dir"
  printf '%s\n' "Run 'cargo --version', 'node --version', 'cargo test --quiet', and 'node --test'. Create probe.txt containing ok, commit it locally, and end with: OUTCOME: no_change" >"$dir/prompt.txt"
  build_args
  run_agy "$ws" "$dir/prompt.txt" "$dir"
  [[ -z $(tool_inputs_leaking "$dir/stream.jsonl") ]] && res=ok || { res="leak detected"; failed=1; }
  echo "CHECK no repo/canary leak: $res"
  [[ $(git -C "$ws" rev-list --count HEAD) -ge 2 ]] && res=ok || { res="no commit"; failed=1; }
  echo "CHECK git commit in sandbox: $res"
  ! grep -q "$PROBE_TOKEN" "$dir/stream.jsonl" && res=ok || { res="secret leaked"; failed=1; }
  echo "CHECK hidden outside-workspace file unread: $res"
  rm -rf "$hidden"
  return "$failed"
}

while (($#)); do
  case $1 in
    --init) MODE=init ;;
    --check) MODE=check ;;
    --probe) MODE=probe ;;
    --yes-spend) YES_SPEND=1 ;;
    --plugin-dir) PLUGIN_SRC=$(cd "${2:?--plugin-dir needs a path}" && pwd -P); shift ;;
    --arm) ARM=${2:?--arm needs a value}; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) TASKS+=("$1") ;;
  esac
  shift
done
case $ARM in chain | single | both) ;; *) die "--arm must be chain, single, or both" ;; esac
[[ -f $PLUGIN_SRC/plugin.json ]] || die "not an Antigravity plugin directory: $PLUGIN_SRC"

RESULTS=$BENCH_DIR/results/$(date +%Y-%m-%dT%H-%M-%S)
require_tools
if [[ $MODE == init ]]; then init_state; exit 0; fi
check_state
case $MODE in
  check) echo "bench: state dir $STATE_DIR and plugin $PLUGIN_SRC are ready"; command -v agy cargo node git || true ;;
  probe) probe ;;
  run) run_bench ;;
esac
