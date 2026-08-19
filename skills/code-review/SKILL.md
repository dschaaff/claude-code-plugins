---
name: code-review
description: Review a diff on two axes, spec compliance and code quality - invoke before any git command when asked to review, verify, or check a diff, branch, PR, slice, or commit range. Also the rubric for reviewer subagents the `implement-spec` skill dispatches. With no spec, the spec axis is skipped and the quality axis still runs.
---

# Code Review

Review a diff along two independent axes — **spec compliance** and **code quality** — and
report them separately. Code can follow every convention yet build the wrong thing, or match
the spec while being a mess; keeping the axes apart stops one from masking the other.

## Scope

Review happens at review moments — a slice review, a whole-branch review, a PR, any diff the
user points at. This skill is **not a completion gate**: finished work stays finished,
commands you already saw succeed stay succeeded, and ordinary tasks get no extra self-review
pass.

Invoked directly, give each axis its own subagent and aggregate their reports verbatim, so
neither axis's reading colors the other. Dispatched as a reviewer subagent yourself, run both
axes inline — no nesting.

## Inputs

- **The diff.** Given a ref range instead of a diff, produce it yourself:
  `git log --oneline A..B`, `git diff --stat A...B`, `git diff -U10 A...B`. Given a single
  ref, the range is `<ref>...HEAD` (three-dot, against the merge-base). Confirm the ref
  resolves (`git rev-parse <ref>`) and the diff is non-empty before anything else — a bad ref
  or an empty diff fails here, not mid-review.
- **The spec**, when one exists. Look in this order: a path the user passed; a file in
  `docs/specs/` matching the branch or feature; issue references in the commit messages
  (`#123`, `Closes #45`, `!67`). Reviewing a single slice: that slice's requirements are the
  primary lens, the rest of the spec is context. Nothing found and the user names none: skip
  the spec axis and say "no spec available".
- **Repo standards** (CLAUDE.md, CONTRIBUTING.md, lint configs) when present — documented
  standards win over the heuristics below.

## Axis 1: Spec compliance

Compare the diff against the spec's requirements. Every requirement in scope is accounted
for — delivered, missing, or flagged unverifiable. Report, citing the spec line for each
finding:

- **Missing or partial requirements** — spec demands it, diff doesn't deliver it.
- **Scope creep** — behavior the spec never asked for (extra options, flags, generality).
- **Contradictions** — implementations that do something different from what the spec says,
  including exact values (numbers, formats, names) that don't match.

## Axis 2: Code quality

Judgment-call findings, each citing its hunk. Work the catalogue below. Every entry is a
**labeled heuristic** ("possible Feature Envy"), never a hard violation, and a documented
repo standard that conflicts with one wins.

Smells, each _what it is_ → _how to fix_ (Fowler, _Refactoring_ ch. 3, by way of
[mattpocock/skills](https://github.com/mattpocock/skills) `engineering/code-review`):

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does
  or holds. → rename it; if no honest name comes, the design is murky.
- **Duplicated Code** — the same logic shape appears in more than one hunk or file. →
  extract the shared shape, call it from both.
- **Feature Envy** — a method that reaches into another object's data more than its own. →
  move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together, a type wanting to
  be born. → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that
  deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the
  diff. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files. →
  gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split
  so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs the spec
  doesn't have. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. →
  hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the
  real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it
  inherits. → drop the inheritance, use composition.

Beyond the smells:

- **Swallowed failure** — an error path that drops the error, or loses which operation failed
  on what input. → propagate it with the operation, the input, and the suggested fix.
- **Self-fulfilling test** — a test that asserts on a mock, or recomputes its expected value
  the way the code under test does. → assert a literal expected value against real behavior.

## Out of scope

These belong elsewhere, so leave them out of the report:

- Anything a linter, formatter, or type checker already enforces — tooling's job.
- Tests the implementer already ran on the same code — their report carries that evidence.
  (A whole-branch review may run the full suite once if no fresh run exists.)
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

Rank findings by severity **within** each axis; the axes stay separate — no merging, no
re-ranking across them, no single overall winner. No findings on an axis: say so in one line.
Requirements that can't be verified from the diff (they live in unchanged code or span
slices) get flagged as "cannot verify from diff" — the controller resolves those, not you.
