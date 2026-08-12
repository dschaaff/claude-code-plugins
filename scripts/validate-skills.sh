#!/usr/bin/env bash
# Validates every skill against the Agent Skills specification using the reference
# implementation, and reports every failure rather than stopping at the first.
#
# https://agentskills.io/specification
#
# ALLOWED_EXTRA_FIELDS names frontmatter keys the spec does not define but a harness reads
# anyway. A skill carrying one is validated as a copy with those keys removed, so every
# other rule still applies to it — the allowlist exempts the field, not the skill. Values
# must be scalars: a block value would leave its indented lines behind and fail as bad YAML.
#
# Usage: validate-skills.sh [skills-dir]
set -euo pipefail

# disable-model-invocation: Claude Code only. Keeps a skill out of the model-facing list so
# the user has to start it by hand. The other harnesses ignore the key.
ALLOWED_EXTRA_FIELDS=(disable-model-invocation)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${1:-$SCRIPT_DIR/../skills}"

[ -d "$SKILLS_DIR" ] || {
  printf 'validate-skills.sh: no such directory: %s\n' "$SKILLS_DIR" >&2
  exit 1
}

command -v uvx >/dev/null || {
  printf 'validate-skills.sh: uvx not found. Install uv: https://docs.astral.sh/uv/\n' >&2
  exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Echoes SKILL.md with the allowlisted keys dropped from its frontmatter. Body lines are
# never touched, so a key name appearing in prose or a code fence stays put.
strip_allowed_fields() {
  awk -v fields="${ALLOWED_EXTRA_FIELDS[*]}" '
    BEGIN { count = split(fields, allowed, " ") }
    NR == 1 && $0 == "---" { in_frontmatter = 1; print; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; print; next }
    in_frontmatter {
      for (i = 1; i <= count; i++) if (index($0, allowed[i] ":") == 1) next
    }
    { print }
  ' "$1"
}

validate_skill() {
  local dir="$1" skill_md="$1/SKILL.md" stripped copy out st

  if [ -f "$skill_md" ]; then
    stripped="$(strip_allowed_fields "$skill_md")"
  else
    stripped=""
  fi

  # Nothing exempted: validate in place, so failures name the real path.
  if [ ! -f "$skill_md" ] || [ "$stripped" = "$(cat "$skill_md")" ]; then
    uvx --quiet --from skills-ref agentskills validate "$dir"
    return
  fi

  copy="$WORK/$(basename "$dir")"
  rm -rf "$copy"
  cp -R "$dir" "$copy"
  printf '%s\n' "$stripped" >"$copy/SKILL.md"

  st=0
  out="$(uvx --quiet --from skills-ref agentskills validate "$copy" 2>&1)" || st=1
  # The copy's path would be meaningless to whoever has to fix the skill.
  [ -n "$out" ] && printf '%s\n' "${out//$copy/$dir}"
  return "$st"
}

status=0
while IFS= read -r dir; do
  if ! validate_skill "$dir"; then
    status=1
  fi
done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort)

exit "$status"
