---
name: verify
description: Spec-anchored review - invoke BEFORE running any git commands when asked to review, verify, or check a diff, branch, slice, or commit range against a spec (docs/specs) - "verify against the spec", "does this match what we spec'd", "review slice N". Also the rubric for reviewer subagents dispatched by implement-spec. Two-axis rubric - spec compliance and code quality - reported separately with a capped report. Generic code review with no spec belongs to other review tooling, not this skill.
---

# Verify

Review a diff along two independent axes — **spec compliance** and **code quality** — and
report them separately. Code can follow every convention yet build the wrong thing, or match
the spec while being a mess; keeping the axes apart stops one from masking the other.

## Scope

Verification happens at review moments — a slice review or a whole-branch review — against a
spec. This skill is **not a completion gate**: it does not mean re-checking finished work,
re-running commands you already saw succeed, or adding self-review passes to ordinary tasks.

## Inputs

- **The diff.** Given a ref range instead of a diff, produce it yourself:
  `git log --oneline A..B`, `git diff --stat A...B`, `git diff -U10 A...B`.
- **The spec**, when one exists (typically `docs/specs/`). Reviewing a single slice: that
  slice's requirements are the primary lens, the rest of the spec is context. No spec: skip
  the spec axis and say "no spec available".
- **Repo standards** (CLAUDE.md, CONTRIBUTING.md, lint configs) when present — documented
  standards win over generic heuristics.

## Axis 1: Spec compliance

Compare the diff against the spec's requirements. Report, citing the spec line for each
finding:

- **Missing or partial requirements** — spec demands it, diff doesn't deliver it.
- **Scope creep** — behavior the spec never asked for (extra options, flags, generality).
- **Contradictions** — implementations that do something different from what the spec says,
  including exact values (numbers, formats, names) that don't match.

## Axis 2: Code quality

Judgment-call issues in the diff, citing the hunk for each finding: unclear naming,
duplication, unnecessary complexity or premature abstraction, error paths that swallow
failures or lose context, tests that assert on mocks or recompute their expected values.

These are labeled heuristics, never hard violations. A documented repo standard that
conflicts with a heuristic wins.

## Skip — do not report

- Anything a linter, formatter, or type checker already enforces — tooling's job.
- Re-running tests the implementer already ran on the same code — their report carries that
  evidence. (A whole-branch review may run the full suite once if no fresh run exists.)
- Style preferences with no documented standard behind them.
- Code outside the diff. Real problems in untouched code get one line at the end, marked
  out-of-scope — they are not findings.

## Report

Under **~400 words**, structured as:

```markdown
## Spec compliance
- [Critical|Important|Minor] <finding> — spec: "<quoted line>"

## Code quality
- [Critical|Important|Minor] <finding> — <file:line / quoted hunk>

Verdict: spec <pass|fail — one line>; quality <approve|revise — one line>
```

Rank findings by severity **within** each axis; never merge or re-rank across axes, and
never pick a single overall winner. No findings on an axis: say so in one line. Requirements
that can't be verified from the diff (they live in unchanged code or span slices) get
flagged as "cannot verify from diff" — the controller resolves those, not you.
