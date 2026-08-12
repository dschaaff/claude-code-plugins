---
name: to-spec
description: Invoke whenever the user wants the current discussion captured as a spec - "write this up as a spec", "turn this into a spec", "create the spec", "spec it out", or a design conversation has just wrapped up and the next step is a written spec. Do not write a spec file by hand from memory of the template; this skill defines the format. Synthesizes the conversation into docs/specs with vertical slices - no interview, just synthesis.
---

# To Spec

Convert the current conversation into a spec file. No interview — the thinking already
happened (in a brainstorm or an ad-hoc discussion); this skill synthesizes it. If the
conversation leaves a real gap — a decision never made, a requirement never pinned down —
ask the user explicitly before writing. Never invent requirements to fill silence.

## Ground the spec in the repo

Before writing, look at what exists: project structure, prior specs in `docs/specs/`, test
conventions and where tests live, relevant standards docs. The spec's Testing and Design
decisions sections must fit the actual repo, not a hypothetical one.

## Write the spec

Path: `docs/specs/YYYY-MM-DD-<topic>.md`. If a spec for this topic already exists in
`docs/specs/`, update it in place instead of creating a new file — the spec is a living
document. Sections, in order:

```markdown
# <topic>

## Problem
What's broken or missing, from the user's perspective.

## Solution
The intended end state, from the user's perspective.

## Design decisions
Architecture, interfaces, schemas, the chosen approach and why — the decisions made in
conversation, including rejected alternatives when the "why not" matters. Code snippets
only when a prototype (schema, type shape, state machine) captures a decision better than
prose. Avoid file paths that go stale.

## Testing
The seams: where tests live, what behavior they verify, prior art in the repo. Behavior
through public boundaries — the fewer seams the better.

## Slices
Numbered vertical slices, completable independently in order. Each slice:
### Slice N: <name>
**Goal:** one sentence.
Requirements: exact values and behaviors — numbers, names, formats, verbatim where it
matters.
Done when: an observable check.

## Out of scope
What this spec deliberately excludes.
```

**The Slices section is load-bearing.** Each slice must be self-contained enough that an
implementer given only the spec and a slice number can execute it — requirements live in
the slice, not in the reader's memory of the conversation. Slice progress is later tracked
by appending `— DONE` to slice headings, so keep headings stable.

## Self-review

Reread the draft with fresh eyes and fix inline — no re-review loop:

1. **Placeholders** — any TBD, TODO, or vague requirement? Pin it down.
2. **Contradictions** — do sections disagree with each other?
3. **Ambiguity** — could a requirement be read two ways? Pick one and make it explicit.
4. **Slice independence** — can each slice be executed from the spec alone, in order?

## Hand over

Commit the spec. Then ask the user to review the file before anything gets built:

> Spec written and committed to `<path>`. Review it and tell me what to change — when it's
> approved, invoke the `implement-spec` skill to execute it.
