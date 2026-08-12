#!/usr/bin/env bash
# Tests for install.sh. Every case runs against a throwaway HOME so nothing in the
# real $HOME is touched.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_SUITE="install-tests"
# shellcheck source=tests/lib.sh
. "$SCRIPT_DIR/lib.sh"
INSTALL_SH="$SCRIPT_DIR/../install.sh"

# Builds an isolated fixture: $HOME plus a repo checkout holding install.sh and one skill.
# Echoes the fixture root. Callers use "$root/home" and "$root/repo".
# Runs inside a command substitution, so it must not rely on parent-shell state for
# uniqueness — the caller passes its own name.
new_fixture() {
  local root="$TEST_ROOT/$1"
  mkdir -p "$root/home" "$root/repo/skills/demo"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n' \
    >"$root/repo/skills/demo/SKILL.md"
  cp "$INSTALL_SH" "$root/repo/install.sh"
  chmod +x "$root/repo/install.sh"
  printf '%s' "$root"
}

run_install() {
  local root="$1"
  HOME="$root/home" "$root/repo/install.sh" 2>&1
}

test_fresh_install_links_both_paths() {
  current_test="fresh install links ~/.agents/skills and ~/.claude/skills to the repo"
  local root out status
  root="$(new_fixture fresh)"
  out="$(run_install "$root")"
  status=$?

  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
  assert_symlink_to "$root/home/.agents/skills" "$root/repo/skills"
  assert_symlink_to "$root/home/.claude/skills" "$root/repo/skills"

  if [ -L "$root/home/.agents" ]; then
    fail "expected ~/.agents to be a real directory, not a symlink"
  fi
  [ -f "$root/home/.agents/skills/demo/SKILL.md" ] ||
    fail "expected demo skill reachable through ~/.agents/skills"
}

test_second_run_is_a_noop() {
  current_test="running twice succeeds and leaves both links pointing at the repo"
  local root out status
  root="$(new_fixture noop)"
  run_install "$root" >/dev/null
  out="$(run_install "$root")"
  status=$?

  [ "$status" -eq 0 ] || fail "expected exit 0 on second run, got $status. output: $out"
  assert_symlink_to "$root/home/.agents/skills" "$root/repo/skills"
  assert_symlink_to "$root/home/.claude/skills" "$root/repo/skills"
  [ ! -e "$root/home/.agents/skills/skills" ] ||
    fail "second run nested a link inside the existing one"
}

test_aborts_on_unknown_symlink() {
  current_test="aborts without touching a symlink owned by something else"
  local root out status
  root="$(new_fixture unknown-link)"
  mkdir -p "$root/home/.agents" "$root/other-skills"
  ln -s "$root/other-skills" "$root/home/.agents/skills"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  assert_symlink_to "$root/home/.agents/skills" "$root/other-skills"
  case "$out" in
  *"$root/home/.agents/skills"*) ;;
  *) fail "expected the offending path in the message. output: $out" ;;
  esac
  [ ! -e "$root/home/.claude/skills" ] ||
    fail "expected abort before linking ~/.claude/skills"
}

test_replaces_known_legacy_dotfiles_links() {
  current_test="replaces the two known legacy dotfiles symlinks"
  local root out status
  root="$(new_fixture legacy)"
  mkdir -p "$root/home/.agents" "$root/home/.claude" \
    "$root/home/.dotfiles/agents/.agents/skills" \
    "$root/home/.dotfiles/claude/.claude"
  ln -s "$root/home/.dotfiles/agents/.agents/skills" "$root/home/.agents/skills"
  ln -s "$root/home/.dotfiles/claude/.claude/skills" "$root/home/.claude/skills"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
  assert_symlink_to "$root/home/.agents/skills" "$root/repo/skills"
  assert_symlink_to "$root/home/.claude/skills" "$root/repo/skills"
}

test_aborts_when_parent_is_a_symlink() {
  current_test="aborts when ~/.agents is itself a symlink (stale stow fold)"
  local root out status
  root="$(new_fixture stow-fold)"
  mkdir -p "$root/home/.dotfiles/agents/.agents/skills"
  ln -s "$root/home/.dotfiles/agents/.agents" "$root/home/.agents"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  [ ! -e "$root/home/.dotfiles/agents/.agents/skills/skills" ] ||
    fail "wrote through the symlinked parent into dotfiles"
  assert_symlink_to "$root/home/.agents" "$root/home/.dotfiles/agents/.agents"
}

test_aborts_when_path_is_a_real_directory() {
  current_test="aborts when the link path is a real directory"
  local root out status
  root="$(new_fixture real-dir)"
  mkdir -p "$root/home/.agents/skills/pre-existing"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  [ -d "$root/home/.agents/skills/pre-existing" ] ||
    fail "clobbered the existing directory"
  [ ! -e "$root/home/.agents/skills/skills" ] ||
    fail "nested a link inside the existing directory"
}

test_aborts_when_skills_dir_is_missing() {
  current_test="aborts when the repo has no skills directory"
  local root out status
  root="$(new_fixture no-skills)"
  rm -r "$root/repo/skills"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  [ ! -e "$root/home/.agents/skills" ] || fail "linked a missing skills directory"
}

test_aborts_when_skills_dir_holds_no_skill_files() {
  current_test="aborts when skills/ contains no SKILL.md"
  local root out status
  root="$(new_fixture empty-skills)"
  rm "$root/repo/skills/demo/SKILL.md"

  out="$(run_install "$root")"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  [ ! -e "$root/home/.agents/skills" ] || fail "linked an empty skills directory"
}

test_fresh_install_links_both_paths
test_second_run_is_a_noop
test_aborts_on_unknown_symlink
test_replaces_known_legacy_dotfiles_links
test_aborts_when_parent_is_a_symlink
test_aborts_when_path_is_a_real_directory
test_aborts_when_skills_dir_is_missing
test_aborts_when_skills_dir_holds_no_skill_files

finish
