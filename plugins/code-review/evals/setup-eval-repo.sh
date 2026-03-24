#!/usr/bin/env bash
set -euo pipefail

# Sets up a temporary git repo with fixture files staged as new changes.
# Usage: ./setup-eval-repo.sh <fixture-dir> [dest-dir]
#
# If dest-dir is omitted, creates a temp directory under $TMPDIR.
# Prints the path to the created repo on stdout.

FIXTURE_DIR="${1:?Usage: setup-eval-repo.sh <fixture-dir> [dest-dir]}"
DEST_DIR="${2:-$(mktemp -d "${TMPDIR:-/tmp}/eval-repo-XXXXXX")}"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "Error: fixture directory '$FIXTURE_DIR' does not exist" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

git init -q
git commit -q --allow-empty -m "initial commit"

cp -R "$FIXTURE_DIR"/. .
git add -A
# Don't commit — leave files staged so the code-review agent sees them as changes

echo "$DEST_DIR"
