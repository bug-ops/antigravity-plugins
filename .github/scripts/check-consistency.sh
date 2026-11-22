#!/usr/bin/env bash
# Checks cross-file consistency and Antigravity plugin specification compliance for dev-agents.
set -euo pipefail

cd "$(dirname "$0")/../.."
plugin=dev-agents
status=0

fail() {
  echo "ERROR: $*" >&2
  status=1
}

# 1. Verify plugin.json required fields and logo existence
name=$(jq -r '.name // empty' "$plugin/plugin.json")
logo=$(jq -r '.logo // empty' "$plugin/plugin.json")
[[ $name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail "plugin.json name '$name' is not lowercase kebab-case"
[[ -n $logo && -f "$plugin/$logo" ]] || fail "plugin.json logo '$logo' does not exist"
prompt_count=$(jq -r '(.suggestedPrompts // []) | length' "$plugin/plugin.json")
((prompt_count <= 3)) || fail "plugin.json suggestedPrompts has $prompt_count entries (max 3)"

# 2. Verify every skill directory name matches SKILL.md frontmatter `name` and body <= 24000 bytes
for skill_dir in "$plugin"/skills/*/; do
  dir_name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [[ -f $skill_md ]] || { fail "missing $skill_md"; continue; }
  fm_name=$(awk 'BEGIN{n=0}/^---/{n++;if(n==2)exit;next}n==1&&/^name:/{sub(/^name:[[:space:]]*/,"");print;exit}' "$skill_md")
  [[ $fm_name == "$dir_name" ]] || fail "$skill_md frontmatter name '$fm_name' != directory '$dir_name'"
  body_bytes=$(awk 'BEGIN{n=0}/^---/{n++;next}n>=2{print}' "$skill_md" | wc -c | tr -d ' ')
  ((body_bytes <= 24000)) || fail "$skill_md body is $body_bytes bytes (>24000 byte limit)"
done

# 3. Verify every agent filename matches frontmatter `name` and referenced skills exist
for agent_md in "$plugin"/agents/*.md; do
  base=$(basename "$agent_md" .md)
  fm_name=$(awk 'BEGIN{n=0}/^---/{n++;if(n==2)exit;next}n==1&&/^name:/{sub(/^name:[[:space:]]*/,"");print;exit}' "$agent_md")
  [[ $fm_name == "$base" ]] || fail "$agent_md frontmatter name '$fm_name' != filename '$base'"
  while IFS= read -r sp; do
    [[ -z $sp ]] && continue
    [[ -f "$plugin/$sp/SKILL.md" ]] || fail "$agent_md references missing skill '$sp'"
  done < <(awk 'BEGIN{n=0;in_s=0}/^---/{n++;if(n==2)exit;next}n==1&&/^skills:/{in_s=1;next}n==1&&in_s&&/^[A-Za-z]/{in_s=0}n==1&&in_s&&/^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,"");print}' "$agent_md")
done

# 4. Verify no orphaned reference files (stack and agent-handoff load references by computed name)
while IFS= read -r ref; do
  skill=${ref#"$plugin/skills/"}
  skill=${skill%%/*}
  [[ $skill != stack && $skill != agent-handoff ]] || continue
  grep -rqF --include='*.md' --exclude=CHANGELOG.md --exclude="$(basename "$ref")" \
    "$(basename "$ref")" "$plugin" || fail "orphaned reference ${ref#"$plugin/"}"
done < <(find "$plugin/skills" -path '*/references/*' -name '*.md')

# 5. Verify handoff suffixes declared in agents exist in agent-handoff
for file in "$plugin"/agents/*.md; do
  suffix=$(grep -oE 'your suffix: `[a-z-]+`' "$file" | grep -oE '`[a-z-]+`' | tr -d '`' || true)
  case $suffix in
    '' | arch-analyst | security-analyst) continue ;;
  esac
  [[ -f "$plugin/skills/agent-handoff/references/$suffix.md" ]] ||
    fail "$file declares handoff suffix '$suffix' without agent-handoff/references/$suffix.md"
  grep -qF "\`$suffix\`" "$plugin/skills/agent-handoff/SKILL.md" ||
    fail "agent-handoff/SKILL.md does not list suffix '$suffix' from $file"
done

# 6. Verify all helper scripts are executable (0755)
for sh in "$plugin"/scripts/*.sh "$plugin"/skills/init-project/scripts/scaffold.sh; do
  [[ -x $sh ]] || fail "$sh is not executable"
done

# 7. Verify no stray Claude-only primitives remain inside agents/ or skills/
if grep -rnE 'CLAUDE_PLUGIN_ROOT|CLAUDE_SKILL_DIR|CLAUDE_CODE_|AskUserQuestion|EnterWorktree|ToolSearch|TaskCreate|TaskUpdate|SubagentHandback|\.claude/|Skill\(skill:|/dev-agents:' \
  "$plugin/agents" "$plugin/skills" >/dev/null 2>&1; then
  grep -rnE 'CLAUDE_PLUGIN_ROOT|CLAUDE_SKILL_DIR|CLAUDE_CODE_|AskUserQuestion|EnterWorktree|ToolSearch|TaskCreate|TaskUpdate|SubagentHandback|\.claude/|Skill\(skill:|/dev-agents:' \
    "$plugin/agents" "$plugin/skills" >&2
  fail "found stray Claude-specific references in $plugin/agents or $plugin/skills"
fi

if ((status == 0)); then
  echo "ok   consistency checks passed"
fi
exit "$status"
