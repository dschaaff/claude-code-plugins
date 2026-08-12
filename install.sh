#!/usr/bin/env bash
# Links this repo's skills/ into the global paths the supported agents read.
#
#   ~/.agents/skills -> <repo>/skills   (Codex, pi, opencode)
#   ~/.claude/skills -> <repo>/skills   (Claude Code)
#
# Idempotent. Replaces only the two symlinks the old stow-based dotfiles setup created;
# anything else already occupying a path is reported and left alone.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

# Symlink targets install.sh is allowed to replace without asking.
LEGACY_TARGETS=(
  "$HOME/.dotfiles/agents/.agents/skills"
  "$HOME/.dotfiles/claude/.claude/skills"
)

# First argument is the problem, any further arguments are indented follow-up lines.
die() {
  printf 'install.sh: %s\n' "$1" >&2
  shift
  local line
  for line in "$@"; do
    printf '            %s\n' "$line" >&2
  done
  exit 1
}

is_legacy_target() {
  local candidate="$1" legacy
  for legacy in "${LEGACY_TARGETS[@]}"; do
    [ "$candidate" = "$legacy" ] && return 0
  done
  return 1
}

link() {
  local target="$1" link_path="$2" parent current
  parent="$(dirname "$link_path")"

  if [ -L "$parent" ]; then
    die "$parent is a symlink to $(readlink "$parent")." \
      "Writing through it would modify whatever owns that directory. Remove it and re-run."
  fi

  if [ -L "$link_path" ]; then
    current="$(readlink "$link_path")"
    if [ "$current" = "$target" ]; then
      printf 'ok        %s\n' "$link_path"
      return
    fi
    is_legacy_target "$current" ||
      die "$link_path already points to $current, which install.sh does not manage." \
        "Remove it by hand if you want $target there instead."
    rm -- "$link_path"
    printf 'replaced  %s (was -> %s)\n' "$link_path" "$current"
  elif [ -e "$link_path" ]; then
    die "$link_path exists and is not a symlink. Move it aside and re-run."
  fi

  mkdir -p "$parent"
  ln -s "$target" "$link_path"
  printf 'linked    %s -> %s\n' "$link_path" "$target"
}

[ -d "$SKILLS_DIR" ] || die "no skills directory at $SKILLS_DIR"

# A checkout that resolves but holds nothing would link four agents to an empty set,
# which fails silently — every skill just disappears.
if [ -z "$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md -print -quit)" ]; then
  die "$SKILLS_DIR contains no <name>/SKILL.md files"
fi

link "$SKILLS_DIR" "$HOME/.agents/skills"
link "$SKILLS_DIR" "$HOME/.claude/skills"
