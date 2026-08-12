#!/usr/bin/env bash
# Fails when one skill points at another skill that does not exist.
#
# The convention these skills follow is "invoke the `name` skill" — a backticked skill name
# followed by the word "skill". Renaming or deleting a skill without updating its callers
# otherwise breaks silently: the agent simply never finds it.
#
# Usage: check-skill-refs.sh [skills-dir]

# Backticks throughout this file are literal markdown syntax being matched, not command
# substitution.
# shellcheck disable=SC2016
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${1:-$SCRIPT_DIR/../skills}"

[ -d "$SKILLS_DIR" ] || {
  printf 'check-skill-refs.sh: no such directory: %s\n' "$SKILLS_DIR" >&2
  exit 1
}

known=" $(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; |
  sort | tr '\n' ' ')"

status=0
while IFS= read -r file; do
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$known" in
    *" $name "*) ;;
    *)
      printf '%s: references the `%s` skill, which does not exist in %s\n' \
        "$file" "$name" "$SKILLS_DIR" >&2
      status=1
      ;;
    esac
  done < <(grep -oE '`[a-z0-9][a-z0-9-]*` skill' "$file" |
    sed -E 's/^`([^`]*)`.*/\1/' | sort -u)
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md)

[ "$status" -eq 0 ] && printf 'all skill cross-references resolve\n'
exit "$status"
