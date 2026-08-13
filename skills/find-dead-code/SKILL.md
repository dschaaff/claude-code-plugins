---
name: find-dead-code
description: Audit a repository for dead code and report removal candidates with evidence and a confidence rating. Reports only; removal is a separate task run against the report.
disable-model-invocation: true
---

# Find Dead Code

Use sub-agents to explore and find dead code.

<HARD-GATE>
The one file this skill writes is the report, and it lands outside the repo. Every candidate
stays exactly where it is — however obviously dead it looks, however impatient the user
sounds. Removal is a separate task they start deliberately against the report.
</HARD-GATE>

## Prove each candidate

Provide evidence for reach claim. Use language-native tooling where it exists and name what you used.

History moves the confidence rating more than another grep does:

- `git log -S '<symbol>' --oneline` — whether the symbol was ever referenced, and when its
  last call site disappeared. Callers that vanished in a migration are a different finding
  from callers that never existed.
- `git log -1 --format=%ad -- <file>` — long-untouched and unreachable is strong evidence;
  added last week and unreachable is usually unfinished work, not rot.

## Output

Write the report to `<tmpdir>/dead-code-report-<timestamp>.md`, resolving the temp dir from
`$TMPDIR` and falling back to `/tmp`, so nothing lands in the repo. Give the user the
absolute path and the per-axis counts rather than replaying the report in chat.

Group it by axis, highest confidence first, with a group at the end for candidates that matched
no prompt in step 3. Each candidate carries:

- **Location** — file path and line range
- **Axis** — reachability or liveness, and why deleting it changes nothing observable
- **Evidence** — the searches, tool output, and history behind the claim
- **Confidence** — one of:
  - `HIGH` — the axis is settled and no trap applies. Safe to remove.
  - `MEDIUM` — likely dead, with one assumption left for the owner to confirm. Name it.
  - `EXTERNAL` — undecidable from inside the repo, typically an exported symbol with no
    in-repo callers. A real finding, not noise; say what would settle it.
  - `LOW` — a search flagged it, but a trap probably explains it. Listed so the user sees it
    was considered.
- **Downstream cleanup** removal would enable — now-unused imports, dependencies, tests
- **Verification step** before deletion — e.g. "remove, run the full test suite and build;
  grep external consumers"
