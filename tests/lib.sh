#!/usr/bin/env bash
# Shared harness for the shell tests. Sourced, never executed directly.
#
# Provides: TEST_ROOT, fail, assert_symlink_to, finish, and $current_test for messages.
# Each suite sets TEST_SUITE before sourcing so its temp dirs are distinguishable.

# Trailing slash stripped: some callers (prek) export TMPDIR with one, and the resulting
# double slash breaks string comparisons against pwd-normalised paths.
_tmp="${TMPDIR:-/tmp}"
TEST_ROOT="${_tmp%/}/agent-skills-${TEST_SUITE:-tests}.$$"
mkdir -p "$TEST_ROOT"

failures=0
current_test=""

_cleanup() {
  # Guarded: only ever removes the temp root this run created.
  case "$TEST_ROOT" in
  /tmp/* | /var/folders/* | "${_tmp%/}"/*) rm -rf "$TEST_ROOT" ;;
  esac
}
trap _cleanup EXIT

fail() {
  printf 'FAIL %s\n     %s\n' "$current_test" "$1" >&2
  failures=$((failures + 1))
}

assert_symlink_to() {
  local link="$1" want="$2"
  if [ ! -L "$link" ]; then
    fail "expected $link to be a symlink"
    return
  fi
  local got
  got="$(readlink "$link")"
  [ "$got" = "$want" ] || fail "expected $link -> $want, got -> $got"
}

finish() {
  if [ "$failures" -gt 0 ]; then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
  fi
  printf 'all tests passed\n'
}
