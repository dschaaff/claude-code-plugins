---
name: implement-spec
description: REQUIRED whenever implementing work described by a spec file in docs/specs, including resuming a partially-done spec - the spec gets opened inside this skill rather than before it. Controller loop - a fresh subagent per slice, a review of each slice against the spec, and one whole-branch review at the end.
---

# Implement Spec

Execute a spec by dispatching a fresh implementer subagent per slice, reviewing each slice
against the spec, and running one whole-branch review at the end. The spec file is the single
artifact: requirements, progress markers, and parked findings all live there. Use /tdd where possible, at pre-agreed seams.

**Continuous execution:** work straight through the slices, only asking for human input when you can't
resolve something on your own.

**Context discipline:** Preserve your context window. Delegate each slice to a fresh subagent with isolated context.

## Setup

1. **Feature branch.** Work on a feature branch — create one when HEAD is main or master.
   Worktree only if the user asks for one.
2. **Read the spec once.** Note the design decisions and testing seams that bind every
   slice.
3. **Resume check.** Slice headings marked `— DONE` are complete; start at the first slice
   without the marker.
4. **Todo per remaining slice.**
5. **Conflict scan.** Slices that contradict each other or the design decisions get raised
   with the user as one batched question before execution — not one interrupt each.

## Subagent Model Selection

Use the least powerful model that can handle each role to conserve cost and
increase speed. Always pass model explicitly when dispatching a subagent— an
omitted model inherits the session's (usually the most capable and expensive).
If a fix round is required, use a model a tier above the implementer that got stuck.
Keep turn counts to a minimum.

## The Slice Loop

Slices run sequentially: one implementer at a time.

### 1. Dispatch the implementer

Record BASE (`git rev-parse HEAD`). Dispatch a fresh subagent whose prompt contains:

- One line on where this slice fits in the project.
- The spec path and slice number: "Read the spec first. Your slice's requirements are
  verbatim and binding — exact values, names, and formats are not suggestions."
- Interfaces or decisions from earlier slices that the spec doesn't capture.
- This directive, verbatim: 'Call the Skill tool with "tdd" before your first Edit or Write,
  and follow it for every change in this slice. Prose acknowledgement is not invocation —
  the skill must be loaded.'
- The report contract: implement, test, commit; reply with status, commits, the test
  command and its results, and any concerns. Statuses:
  - `DONE` — with test evidence: for each behavior, the failing-test output you saw before
    writing the code and the passing output after. Concerns welcome alongside.
  - `BLOCKED` — can't proceed; states exactly what it needs.

### 2. Handle the report

- **DONE:** requires a named test command, its results, and red-phase output per behavior.
  Missing evidence → ask the implementer for it before anything else. Green-only evidence
  means the tests were written after the code: send the slice back to be reimplemented
  test-first, ahead of any review. Read any concerns; correctness or scope concerns get
  resolved before review.
- **BLOCKED:** missing context → supply it and re-dispatch. Reasoning gap → re-dispatch on
  a more capable model. Slice too large → split it (update the spec) and dispatch the
  pieces. Spec itself wrong → ask the user. Every re-dispatch changes something: added
  context, a stronger model, or a smaller slice.

### 3. Review the slice

Dispatch a reviewer subagent with: the spec path, the slice number, the
ref range `BASE..HEAD`, and the instruction to call the Skill tool with "verify". Every
slice gets this review — the implementer's self-assessment doesn't substitute for it.

Findings the reviewer marks "cannot verify from diff" are yours to resolve — you hold the
cross-slice context. A confirmed gap joins the findings.

### 4. Fix rounds — max 2

Critical or Important findings go back to the implementer verbatim (resume it, or dispatch
fresh with the findings and slice number). The implementer fixes, re-runs the covering
tests, reports. After each round, re-review scoped to the fix: `FIX_BASE..HEAD`, where
FIX_BASE is the head the previous review saw.

After round 2, adjudicate each leftover yourself:

- **Trivial** (rename, one-liner) — fix it directly, run the covering tests.
- **Real but deferrable** — park it: note it in the spec under the slice with a one-line
  ruling. The whole-branch review triages parked items.
- **Foundational** (later slices build on it, or it reveals a spec defect) — stop and ask
  the user.

Minor findings skip fix rounds entirely — park them in the spec for the whole-branch review.

### 5. Complete the slice

Append `— DONE` to the slice heading in the spec. Record in the spec anything durable that
later slices need: changed interfaces, parked findings with rulings. Mark the todo complete
and move on.

## Whole-Branch Review

After all slices: dispatch one reviewer told to call the Skill tool with "verify",
with the spec path and the full branch range (`git merge-base <main> HEAD` to `HEAD`),
pointing it at any parked findings in the spec to triage which block merge.

Findings → **one fix dispatch** carrying the complete list. Re-review the fix range once,
then adjudicate residuals as in the slice loop: trivial → fix, deferrable → park with
ruling, load-bearing → user.

## Finish

Run the full test suite fresh and report the actual results. Then ask the user: open a PR,
merge, or leave the branch as is.
