#!/usr/bin/env bash
# Tests for scripts/validate-skills.sh. Needs network access the first time so uvx can
# fetch skills-ref.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_SUITE="validate-tests"
# shellcheck source=tests/lib.sh
. "$SCRIPT_DIR/lib.sh"
VALIDATOR="$SCRIPT_DIR/../scripts/validate-skills.sh"
REPO_SKILLS="$SCRIPT_DIR/../skills"

# Writes a skills tree. Each argument is "name" for a valid skill, or "name:extra-yaml"
# to inject an extra frontmatter line.
new_skills_dir() {
  local dir="$TEST_ROOT/$1" spec name extra
  shift
  mkdir -p "$dir"
  for spec in "$@"; do
    name="${spec%%:*}"
    extra=""
    [ "$spec" = "$name" ] || extra="${spec#*:}"$'\n'
    mkdir -p "$dir/$name"
    printf -- '---\nname: %s\ndescription: Test skill %s.\n%s---\n\nBody.\n' \
      "$name" "$name" "$extra" >"$dir/$name/SKILL.md"
  done
  printf '%s' "$dir"
}

test_accepts_valid_skills() {
  current_test="exits 0 when every skill is spec-valid"
  local dir out status
  dir="$(new_skills_dir valid alpha beta)"
  out="$("$VALIDATOR" "$dir" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_rejects_non_spec_frontmatter() {
  current_test="exits nonzero and names the skill with a non-spec frontmatter field"
  local dir out status
  dir="$(new_skills_dir invalid alpha 'beta:vendor-only-field: true')"
  out="$("$VALIDATOR" "$dir" 2>&1)"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  case "$out" in
  *beta*) ;;
  *) fail "expected the offending skill name in the output. output: $out" ;;
  esac
}

test_accepts_an_allowlisted_field() {
  current_test="exits 0 for a skill whose only non-spec field is allowlisted"
  local dir out status
  dir="$(new_skills_dir allowlisted alpha 'beta:disable-model-invocation: true')"
  out="$("$VALIDATOR" "$dir" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_allowlisted_field_does_not_excuse_other_errors() {
  current_test="still validates the rest of a skill that carries an allowlisted field"
  local dir out status
  dir="$(new_skills_dir alongside alpha \
    "$(printf 'beta:disable-model-invocation: true\nvendor-only-field: true')")"
  out="$("$VALIDATOR" "$dir" 2>&1)"
  status=$?

  [ "$status" -ne 0 ] || fail "expected nonzero exit, got 0. output: $out"
  case "$out" in
  *vendor-only-field*) ;;
  *) fail "expected the unexempted field in the output. output: $out" ;;
  esac
  # The sanitized copy lives in a temp dir; reporting that path would send the reader
  # somewhere that no longer exists.
  case "$out" in
  *"$dir/beta"*) ;;
  *) fail "expected the real skill path, not the copy. output: $out" ;;
  esac
}

test_reports_every_failure_not_just_the_first() {
  current_test="reports all invalid skills rather than stopping at the first"
  local dir out
  dir="$(new_skills_dir multi 'alpha:vendor-only-field: true' \
    'beta:triggerAutomatically: false')"
  out="$("$VALIDATOR" "$dir" 2>&1)"

  case "$out" in
  *alpha*) ;;
  *) fail "expected alpha in the output. output: $out" ;;
  esac
  case "$out" in
  *beta*) ;;
  *) fail "expected beta in the output. output: $out" ;;
  esac
}

test_ignores_hidden_directories() {
  current_test="ignores hidden directories, which are tooling artifacts and not skills"
  local dir out status
  dir="$(new_skills_dir hidden alpha)"
  mkdir -p "$dir/.claude/.cc-writes"

  out="$("$VALIDATOR" "$dir" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_this_repos_skills_are_valid() {
  current_test="every skill in this repo is spec-valid"
  local out status
  out="$("$VALIDATOR" "$REPO_SKILLS" 2>&1)"
  status=$?
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status. output: $out"
}

test_accepts_valid_skills
test_rejects_non_spec_frontmatter
test_accepts_an_allowlisted_field
test_allowlisted_field_does_not_excuse_other_errors
test_reports_every_failure_not_just_the_first
test_ignores_hidden_directories
test_this_repos_skills_are_valid

finish
