#!/usr/bin/env bash
# Free guard tests for bench/run.sh and bench/score.sh: never calls paid agy -p.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAILS=0

expect_fail() { # <name> <must-not-vanish-path|-> <command...>
  local name=$1 keep=$2 out
  shift 2
  if out=$("$@" 2>&1); then echo "FAIL  $name (command succeeded)"; FAILS=1; return; fi
  if [[ $keep != - && ! -e $keep ]]; then echo "FAIL  $name ($keep was deleted)"; FAILS=1; return; fi
  echo "PASS  $name"
  LAST_OUT=$out
}

expect_ok() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $name"; else echo "FAIL  $name"; FAILS=1; fi
}

# Provide a stub `agy` when running on a host/CI without Antigravity CLI installed.
BIN_PATH=$PATH
if ! command -v agy >/dev/null 2>&1; then
  mkdir -p "$T/bin"
  cat >"$T/bin/agy" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$T/bin/agy"
  BIN_PATH="$T/bin:$PATH"
fi

real=$T/real-looking
mkdir -p "$real/sub"
echo data >"$real/sub/data.txt"
PATH=$BIN_PATH BENCH_STATE_DIR=$real expect_fail "check refuses a dir without the marker" "$real/sub/data.txt" "$HERE/run.sh" --check
PATH=$BIN_PATH BENCH_STATE_DIR=$real expect_fail "init refuses a non-empty dir" "$real/sub/data.txt" "$HERE/run.sh" --init

fresh=$T/fresh
PATH=$BIN_PATH BENCH_STATE_DIR=$fresh expect_ok "init creates a fresh dir with the marker" "$HERE/run.sh" --init
[[ -f $fresh/.dev-agents-bench ]] || { echo "FAIL  marker missing after init"; FAILS=1; }
PATH=$BIN_PATH BENCH_STATE_DIR=$fresh expect_ok "check passes on a bench-created dir" "$HERE/run.sh" --check

PATH=$BIN_PATH BENCH_STATE_DIR=$fresh expect_fail "a paid run needs --yes-spend" - "$HERE/run.sh" rust-bug
[[ $LAST_OUT == *"--yes-spend"* ]] || { echo "FAIL  the refusal does not mention --yes-spend"; FAILS=1; }
PATH=$BIN_PATH BENCH_STATE_DIR=$fresh expect_fail "the probe needs --yes-spend" - "$HERE/run.sh" --probe
[[ $LAST_OUT == *"--yes-spend"* ]] || { echo "FAIL  the probe refusal does not mention --yes-spend"; FAILS=1; }
if [[ -z $(find "$HERE/results" -newer "$T" 2>/dev/null) ]]; then echo "PASS  no results were created"; else echo "FAIL  results were created"; FAILS=1; fi

hidden_case() { # <name> <expected> <line appended to the fixed source, or empty>
  local label=$1 expected=$2 hook=$3
  if (
    source "$HERE/score.sh"
    work=$(mktemp -d "$T/work.XXXXXX")
    cp -R "$HERE/tasks/ts-second-bug/fixture/." "$work/"
    (cd "$work" && patch -s -p1 <"$HERE/tasks/ts-second-bug/reference.diff")
    [[ -z $hook ]] || printf '%s\n' "$hook" >>"$work/src/chunk.ts"
    [[ $(hidden_pass ts-second-bug "$work") == "$expected" ]]
  ); then echo "PASS  $label"; else echo "FAIL  $label"; FAILS=1; fi
}
hidden_case "hidden test passes for a correct fix" pass ""
hidden_case "correct pass count with a non-zero runner exit still fails" fail 'process.on("exit", () => { process.exitCode = 1; });'

expect_case() { # <name> <0|1 expected validity> <expect file content, or - for none>
  local label=$1 want=$2 content=$3 dir
  dir=$(mktemp -d "$T/tasks.XXXXXX")
  mkdir -p "$dir/tasks/x"
  [[ $content == - ]] || printf '%s\n' "$content" >"$dir/tasks/x/expect"
  if (
    source "$HERE/score.sh"
    # shellcheck disable=SC2034
    BENCH_DIR=$dir
    got=0
    validate_expect x >/dev/null || got=1
    [[ $got == "$want" ]]
  ); then echo "PASS  $label"; else echo "FAIL  $label"; FAILS=1; fi
}
expect_case "blocked task with an empty protect list is rejected" 1 $'lang=ts\noutcome=blocked\nprotect='
expect_case "blocked task without a protect key is rejected" 1 $'lang=ts\noutcome=blocked'
expect_case "missing expect file is rejected" 1 -
expect_case "blocked task with a protect list is accepted" 0 $'lang=ts\noutcome=blocked\nprotect=src/a.ts'

all_valid=1
for task_dir in "$HERE"/tasks/*/; do
  shipped=$(basename "$task_dir")
  (source "$HERE/score.sh"; validate_expect "$shipped" >/dev/null) || { echo "FAIL  expect of $shipped is invalid"; all_valid=0; FAILS=1; }
done
((all_valid == 0)) || echo "PASS  every shipped task has a valid expect file"

sed -n '/^tool_inputs_leaking()/,/^}/p' "$HERE/run.sh" >"$T/leaking.sh"
echo '{"text":"// BENCH-HIDDEN-CANARY"}' >"$T/canary.jsonl"
echo '{"text":"ok"}' >"$T/plain.jsonl"
if (
  # shellcheck source=/dev/null
  source "$T/leaking.sh"
  export REPO_DIR=/nonexistent-repo
  [[ -n $(tool_inputs_leaking "$T/canary.jsonl") && -z $(tool_inputs_leaking "$T/plain.jsonl") ]]
); then echo "PASS  a canary in a stream is a leak, a plain stream is not"; else echo "FAIL  canary scan"; FAILS=1; fi

exit "$FAILS"
