#!/usr/bin/env bash
# Tests for scripts/check-skill-refs.sh.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_SUITE="ref-tests"
# shellcheck source=tests/lib.sh
. "$SCRIPT_DIR/lib.sh"
CHECKER="$SCRIPT_DIR/../scripts/check-skill-refs.sh"
REPO_SKILLS="$SCRIPT_DIR/../skills"

# Writes a skills tree: each argument is "name:body".
new_skills_dir() {
  local dir="$TEST_ROOT/$1" spec name body
  shift
  mkdir -p "$dir"
  for spec in "$@"; do
    name="${spec%%:*}"
    body="${spec#*:}"
    mkdir -p "$dir/$name"
    printf -- '---\nname: %s\ndescription: Test skill %s.\n---\n\n%s\n' \
      "$name" "$name" "$body" >"$dir/$name/SKILL.md"
  done
  printf '%s' "$dir"
}

test_accepts_a_reference_to_an_existing_sibling() {
  current_test="exits 0 when a referenced skill exists"
  local dir out status
  # Backticks here are literal test data, not command substitution.
  # shellcheck disable=SC2016
  dir="$(new_skills_dir good \
    'alpha:Now invoke the `beta` skill to continue.' \
    'beta:Does the work.')"
  out="$("$CHECKER" "$dir" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_rejects_a_reference_to_a_missing_skill() {
  current_test="exits nonzero and names the file when a referenced skill is missing"
  local dir out status
  # Backticks here are literal test data, not command substitution.
  # shellcheck disable=SC2016
  dir="$(new_skills_dir rotten \
    'alpha:Now invoke the `ghost` skill to continue.' \
    'beta:Does the work.')"
  out="$("$CHECKER" "$dir" 2>&1)"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  case "$out" in
  *ghost*) ;;
  *) fail "expected the unresolved name in the message. output: $out" ;;
  esac
  case "$out" in
  *alpha/SKILL.md*) ;;
  *) fail "expected the offending file in the message. output: $out" ;;
  esac
}

test_ignores_unbackticked_prose() {
  current_test="does not flag ordinary prose that happens to end in the word skill"
  local dir out status
  dir="$(new_skills_dir prose \
    'alpha:This is a useful skill for reviewing work.' \
    'beta:Writing tests is a skill.')"
  out="$("$CHECKER" "$dir" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_this_repos_skills_resolve() {
  current_test="every cross-reference in this repo's skills resolves"
  local out status
  out="$("$CHECKER" "$REPO_SKILLS" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_accepts_a_reference_to_an_existing_sibling
test_rejects_a_reference_to_a_missing_skill
test_ignores_unbackticked_prose
test_this_repos_skills_resolve

finish
