---
name: find-dead-code
description: Audit a repository for dead code and report removal candidates with evidence and a confidence rating. Reports only — never deletes.
disable-model-invocation: true
---

# Find Dead Code

Audit this repository for dead code that is a candidate for removal. The deliverable is a
high-confidence, evidence-backed report.

<HARD-GATE>
Do not modify, move, or delete any file. This skill produces a report and nothing else,
even when a candidate looks obviously dead and even when the user sounds impatient. Removal
is a separate task the user starts deliberately.
</HARD-GATE>

Where you are uncertain, say so rather than guessing. An unranked pile of maybes is worth
less than a short list the user can act on without re-checking your work.

## Process

### 1. Map the real entry points

Reachability is measured from roots you have confirmed, not from assumptions. Find them
first:

- `main()`, binaries, and other program entry points
- CLI command registrations
- HTTP/gRPC/GraphQL route registrations
- cron and scheduled jobs, queue consumers, event handlers
- the exported library API (whatever the package manifest publishes)
- test entry points
- anything named by build, CI, container, or deploy config

Nothing downstream is trustworthy until this map exists.

### 2. Gather candidates in these categories

Keep the categories separate — they carry different risk and different cleanup work.

1. **Unreferenced symbols** — functions, methods, classes, constants, types, and exported
   members never called or imported anywhere.
2. **Unreachable code** — branches that cannot execute, statements after an unconditional
   return/exit/raise, conditions provably always true or false.
3. **Orphaned files and modules** — files no entry point, build config, or asset pipeline
   imports, requires, or references.
4. **Unused dependencies** — packages in the manifest (`package.json`, `go.mod`,
   `Cargo.toml`, `pyproject.toml`, `requirements.txt`, …) with no import in the codebase.
5. **Dead feature flags and config** — flags, env vars, or config keys defined but never
   read, or whose gated code is now permanently on or off.
6. **Commented-out code and abandoned scaffolding** — commented blocks, and TODO-marked
   structure that was never finished or wired up.

### 3. Prove each candidate

**A claim of "unused" with no accompanying search is invalid.** For every candidate, record
the search you ran and what it returned — e.g. the ripgrep query, and that it produced zero
hits outside the definition itself. Prefer structure-aware search (`ast-grep`, an LSP, the
compiler) over text patterns for call sites and imports; text search misses call shapes and
over-matches on comments.

Use language-native tooling where it exists and name what you used: `go vet` and
`deadcode`, `knip` or `ts-prune`, `vulture`, `cargo +nightly udeps`, compiler `-Wunused`,
coverage reports. Treat every tool result as a **lead**, then confirm it by hand. These
tools do not understand the traps below.

### 4. Rule out the traps

Check each of these before flagging anything. Most false positives come from this list:

- **Dynamic or indirect references** — reflection, string-based dispatch, dependency
  injection, decorators and annotations, `getattr`/`eval`, registries, plugin loaders,
  template and HTML references, serialization by field or type name.
- **Public API surface** — an exported symbol in a library can have external consumers with
  zero in-repo callers. Flag these LOW confidence and say why explicitly.
- **Test-only usage** — code used only by tests is not dead. Give it its own category and
  let the user decide whether the code or the test goes.
- **Framework magic** — convention-based loading: routes, migrations, fixtures, ORM hooks,
  build-time codegen.
- **Non-code references** — config files, IaC, SQL, shell scripts, Dockerfiles, CI
  workflows, generated code.
- **Monorepo cross-package usage** — search the whole workspace, never a single package.

## Output

A Markdown report grouped by the categories in step 2, ranked by confidence with the
highest first. Each candidate carries:

- **Location** — file path and line range
- **What it is** and why it appears dead
- **Evidence** — the exact search performed and its result, plus any tool output
- **Confidence** — `HIGH` (safe to remove), `MEDIUM` (verify with the owner), `LOW` (likely
  a false positive, listed for completeness)
- **Downstream cleanup** removal would enable — now-unused imports, dependencies, tests
- **Verification step** before deletion — e.g. "remove, run the full test suite and build;
  grep external consumers"

State the entry points you measured reachability from, and name anything you could not
reach a conclusion on. A category with no findings gets one line saying so — silence reads
as "not checked."
