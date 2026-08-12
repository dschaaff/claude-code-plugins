---
name: implement-spec
description: REQUIRED whenever implementing work described by a spec file in docs/specs - "implement the spec", "execute the spec", "build it" after a spec was written, "work through the slices", or resuming a partially-done spec. Never read a spec and start coding directly; invoke this skill FIRST, before opening the spec. Controller loop that implements the spec slice-by-slice with fresh subagents, reviews each slice against the spec, and finishes with a whole-branch review.
---

# Implement Spec

Execute a spec by dispatching a fresh implementer subagent per slice, reviewing each slice
against the spec, and running one whole-branch review at the end. The spec file is the
single artifact: requirements, progress markers, and parked findings all live there — no
ledgers, no report files, no scratch directories.

**Continuous execution:** don't check in with the user between slices. Stop only for a
BLOCKED you can't resolve, genuine ambiguity in the spec, or completion.

**Context discipline:** your context is for coordination. Hand subagents paths, not pasted
content; let them read the spec and run git themselves. Never paste prior-slice history
into a dispatch — a fresh subagent needs its slice, the interfaces it touches, nothing else.

## Model policy

Always pass `model` explicitly when dispatching — an omitted model inherits the session's
(usually the most capable and expensive), silently defeating this section.

- **Implementer:** scale to the slice. `sonnet` for well-specified slices touching 1–2
  files. `opus` for multi-file integration, design judgment, or subtle logic (concurrency,
  parsers, migrations).
- **Slice reviewer:** `opus` by default — review is a judgment task, and a weak reviewer is
  worse than none. `sonnet` only for genuinely mechanical diffs.
- **Whole-branch reviewer:** `opus`, always.

## Setup

1. **Feature branch.** Never implement on main/master — create a branch if needed. Worktree
   only if the user asks for one.
2. **Read the spec once.** Note the design decisions and testing seams that bind every
   slice.
3. **Resume check.** Slice headings marked `— DONE` are complete — never re-dispatch them.
   Start at the first slice without the marker.
4. **Todo per remaining slice.**
5. **Conflict scan.** Slices that contradict each other or the design decisions get raised
   with the user as one batched question before execution — not one interrupt each.

## The Slice Loop

Slices run sequentially — one implementer at a time, never in parallel.

### 1. Dispatch the implementer

Record BASE (`git rev-parse HEAD`). Dispatch a fresh subagent whose prompt contains:

- One line on where this slice fits in the project.
- The spec path and slice number: "Read the spec first. Your slice's requirements are
  verbatim and binding — exact values, names, and formats are not suggestions."
- Interfaces or decisions from earlier slices that the spec doesn't capture.
- This directive, verbatim: "Invoke the `tdd` skill with the Skill tool before your first
  Edit or Write, and follow it for every change in this slice. Prose acknowledgement is not
  invocation — the skill must be loaded."
- The report contract: implement, test, commit; reply with status, commits, the test
  command and its results, and any concerns. Statuses:
  - `DONE` — with test evidence: for each behavior, the failing-test output you saw before
    writing the code and the passing output after. Concerns welcome alongside.
  - `BLOCKED` — can't proceed; states exactly what it needs.

### 2. Handle the report

- **DONE:** requires a named test command, its results, and red-phase output per behavior.
  Missing evidence → ask the implementer for it before anything else. Green-only evidence
  means the tests were written after the code: send the slice back to be reimplemented
  test-first, don't accept it and don't review it. Read any concerns; correctness or scope
  concerns get resolved before review.
- **BLOCKED:** missing context → supply it and re-dispatch. Reasoning gap → re-dispatch on
  a more capable model. Slice too large → split it (update the spec) and dispatch the
  pieces. Spec itself wrong → ask the user. Never re-send the same dispatch unchanged.

### 3. Review the slice

Dispatch a reviewer subagent (`opus` default) with: the spec path, the slice number, the
ref range `BASE..HEAD`, and the instruction to apply the `verify` skill. Never skip this —
the implementer's self-assessment is not a review.

Findings the reviewer marks "cannot verify from diff" are yours to resolve — you hold the
cross-slice context. A confirmed gap joins the findings.

### 4. Fix rounds — max 2

Critical or Important findings go back to the implementer verbatim (resume it, or dispatch
fresh with the findings and slice number). The implementer fixes, re-runs the covering
tests, reports. After each round, re-review scoped to the fix: `FIX_BASE..HEAD`, where
FIX_BASE is the head the previous review saw.

After round 2, stop dispatching and adjudicate each leftover yourself:

- **Trivial** (rename, one-liner) — fix it directly, run the covering tests.
- **Real but deferrable** — park it: note it in the spec under the slice with a one-line
  ruling. The whole-branch review triages parked items.
- **Load-bearing** (later slices build on it, or it reveals a spec defect) — stop and ask
  the user.

Minor findings never enter fix rounds — park them in the spec for the whole-branch review.

### 5. Complete the slice

Append `— DONE` to the slice heading in the spec. Record in the spec anything durable that
later slices need: changed interfaces, parked findings with rulings. Mark the todo complete
and move on.

## Whole-Branch Review

After all slices: dispatch one reviewer (`opus`, `verify` skill) with the spec path and the
full branch range (`git merge-base <main> HEAD` to `HEAD`), pointing it at any parked
findings in the spec to triage which block merge.

Findings → **at most one fix dispatch** carrying the complete list — never one fixer per
finding. Re-review the fix range once, then adjudicate residuals as in the slice loop:
trivial → fix, deferrable → park with ruling, load-bearing → user.

## Finish

Run the full test suite fresh and report the actual results. Then ask the user: open a PR,
merge, or leave the branch as is.
