#!/usr/bin/env bash
# Validates every skill against the Agent Skills specification using the reference
# implementation, and reports every failure rather than stopping at the first.
#
# https://agentskills.io/specification
#
# Usage: validate-skills.sh [skills-dir]
set -euo pipefail

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

status=0
while IFS= read -r dir; do
  if ! uvx --quiet --from skills-ref agentskills validate "$dir"; then
    status=1
  fi
done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort)

exit "$status"
