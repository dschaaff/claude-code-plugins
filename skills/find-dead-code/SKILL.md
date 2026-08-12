---
name: find-dead-code
description: Audit a repository for dead code and report removal candidates with evidence and a confidence rating. Reports only — never deletes.
disable-model-invocation: true
---

# Find Dead Code

Audit this repository for dead code. The deliverable is a high-confidence, evidence-backed
report.

<HARD-GATE>
Do not modify, move, or delete any file in the repository, even when a candidate looks
obviously dead and even when the user sounds impatient. Removal is a separate task they
start deliberately against the report. The one file you write is the report, and it lands
outside the repo.
</HARD-GATE>

## Process

### 1. Scope the audit — YAGNI

Reachability analysis across a whole monorepo is unbounded work, and most of it answers a
question nobody asked.

- If the user named a direction — a package, a subsystem, a suspicion — take it.
- Otherwise start where rot collects: long-lived areas that have stopped changing, and
  anything the commit history shows was migrated away from but never cleaned up.

### 2. Map the real entry points

Reachability is measured from roots you have confirmed, not from assumptions. Within your
scope, find them first:

- `main()`, binaries, and other program entry points
- CLI command registrations
- HTTP/gRPC/GraphQL route registrations
- cron and scheduled jobs, queue consumers, event handlers
- the exported library API (whatever the package manifest publishes)
- test entry points
- anything named by build, CI, container, or deploy config

### 3. Gather candidates in these categories

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
7. **Test-only code** — reachable only from tests. Not dead, but worth surfacing: the user
   decides whether the code goes or the test does.

Spawn a sub-agent per category (or per package, on a monorepo), hand it the scope and the
entry-point map, and have it return findings in the Output shape below. Running all seven
searches inline buries the report under the transcript.

### 4. Prove each candidate

**A claim of "unused" with no accompanying search is invalid.** Record the query you ran and
what it returned — e.g. the ripgrep pattern, and that it produced zero hits outside the
definition itself. Prefer structure-aware search (`ast-grep`, an LSP, the compiler) over text
patterns; text search misses call shapes and over-matches on comments.

Use language-native tooling where it exists and name what you used: `go vet` and `deadcode`,
`knip`, `vulture`, `cargo machete` or `cargo +nightly udeps`, compiler `-Wunused`, coverage
reports. Treat every result as a **lead** and confirm it by hand — these tools do not
understand the traps below.

History moves the confidence rating more than another grep does:

- `git log -S '<symbol>' --oneline` — whether the symbol was ever referenced, and when its
  last call site disappeared. Callers that vanished in a migration are a different finding
  from callers that never existed.
- `git log -1 --format=%ad -- <file>` — long-untouched and unreachable is strong evidence;
  added last week and unreachable is usually unfinished work, not rot.

### 5. Rule out the traps

Most false positives come from this list:

- **Dynamic or indirect references** — reflection, string-based dispatch, dependency
  injection, decorators and annotations, `getattr`/`eval`, registries, plugin loaders,
  template and HTML references, serialization by field or type name.
- **Public API surface** — an exported symbol in a library can have external consumers with
  zero in-repo callers. Rate these `EXTERNAL`, not `LOW`.
- **Framework magic** — convention-based loading: routes, migrations, fixtures, ORM hooks,
  build-time codegen.
- **Non-code references** — config files, IaC, SQL, shell scripts, Dockerfiles, CI
  workflows, generated code.
- **Monorepo cross-package usage** — search the whole workspace, even when the audit is
  scoped to a single package.
- **Dependencies used without an import** — where category 4 goes wrong. Linters, formatters,
  build plugins, and codegen run from CI or scripts and are never imported; type stubs are
  compile-time only; peer, optional, and transitive dependencies are declared for resolution
  rather than use. Check scripts, CI workflows, and tool config before calling one unused.

## Output

Write the report to `<tmpdir>/dead-code-report-<timestamp>.md`, resolving the temp dir from
`$TMPDIR` and falling back to `/tmp`, so nothing lands in the repo. Give the user the
absolute path and the per-category counts rather than replaying the report in chat.

Group it by the categories in step 3, highest confidence first. Each candidate carries:

- **Location** — file path and line range
- **What it is** and why it appears dead
- **Evidence** — the searches, tool output, and history behind the claim
- **Confidence** — one of:
  - `HIGH` — reachability is settled and no trap applies. Safe to remove.
  - `MEDIUM` — likely dead, with one assumption left for the owner to confirm. Name it.
  - `EXTERNAL` — undecidable from inside the repo, typically an exported symbol with no
    in-repo callers. A real finding, not noise; say what would settle it.
  - `LOW` — a search flagged it, but a trap probably explains it. Listed so the user sees it
    was considered, not silently dropped.
- **Downstream cleanup** removal would enable — now-unused imports, dependencies, tests
- **Verification step** before deletion — e.g. "remove, run the full test suite and build;
  grep external consumers"

State the scope you audited, the entry points you measured reachability from, and anything
you could not reach a conclusion on. A category with no findings gets one line saying so —
silence reads as "not checked."
