---
name: tdd
description: REQUIRED process for changing production code - invoke BEFORE the first Edit/Write to any source file, not after exploring. Red-green test-driven development - failing test first, minimal code to pass. Applies to every feature, bugfix, and behavior change no matter how small, even when the user never mentions tests - "add a flag", "fix this bug", "make X do Y", "handle this edge case" all require this skill first. Skipping it because the change looks trivial is the failure mode it exists to prevent.
---

# Test-Driven Development

Write one failing test. Watch it fail. Write the simplest code that passes. Watch it pass.
Repeat.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before its test? Delete it and reimplement test-first. Don't keep it as
"reference" — you'll adapt it, and that's testing after.

## The Loop

### RED — write one minimal failing test

- One behavior per test, with a name that describes the behavior
  (`retries failed operations 3 times`, not `test1` or `retry works`).
- Before writing it, name the production change that would make it fail.

### Watch it fail — mandatory, never skip

Run the test. Confirm it **fails** (not errors) and fails for the right reason: the feature
is missing, not a typo or import error.

- Passes immediately? You're testing existing behavior — fix the test.
- Errors? Fix the error and re-run until it fails correctly.

### GREEN — simplest code that passes

Just enough to satisfy the test. No extra options, flags, or generality the test doesn't
demand. Don't touch unrelated code.

### Watch it pass

Run the test again. Confirm it passes and everything else stays green, with pristine output
(no new warnings). Fails? Fix the code, not the test.

### Repeat

Next behavior, next failing test. There is no refactor step: quality cleanup belongs to
review. Renaming or tidying code you just wrote for this task is fine in passing — a
dedicated "now improve the code" pass is not.

## Test Quality

- **Test at the seams.** Test behavior through public boundaries — the seams the spec's
  Testing section defines, when a spec exists. If a refactor breaks your tests but not the
  behavior, the tests were wrong.
- **Assert on real behavior, never mock behavior.** `expect(mock).toHaveBeenCalled()` tests
  the mock, not the code. Mock only what is slow (network, filesystem), non-deterministic
  (time, randomness), or an external service you don't control.
- **Expected values need an independent source of truth** — a literal, a worked example, a
  spec line. A test that recomputes the expected value the same way the code does passes by
  construction and proves nothing.
- **Cover edges and errors**, not just the happy path: empty inputs, boundaries, malformed
  data. Every error path the code handles gets a test that triggers it.

## Bug Fixes

Start with a failing test that reproduces the bug. The test proves the fix and prevents the
regression. Never fix a bug without one.

## Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks too. The test takes 30 seconds. |
| "I'll test after" | Tests written after pass immediately, which proves nothing — you never saw them catch the bug. |
| "Already manually tested" | No record, no re-run, no proof. Automated tests run the same way every time. |
| "Keep it as reference, write tests first" | You'll adapt it. That's testing after. Delete means delete. |

## Exceptions

Throwaway prototypes, generated code, and pure configuration may skip TDD — ask the user
first. Exploration is fine: throw the exploration away, then start with TDD.
