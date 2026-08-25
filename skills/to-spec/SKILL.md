---
name: to-spec
description: Capture the current discussion as a spec - invoke on any request to write up, create, or spec out the design just discussed, and when a design conversation wraps up. This skill defines the spec format; the shape comes from here rather than from memory. Synthesis only, no interview - writes docs/specs with vertical slices.
---

# To Spec

Convert the current conversation into a spec file. o NOT interview the user —
just synthesize what you already know. Every requirement traces to something
the conversation settled. Where it leaves a real gap — a decision never made, a
requirement never pinned down — ask the user explicitly before writing.

## Ground the spec in the repo

Before writing, look at what exists: project structure, prior specs in `docs/specs/`, test
conventions and where tests live, relevant standards docs. The spec's Testing and Design
decisions sections must fit the actual repo, not a hypothetical one.

Read `CONTEXT.md` (or the contexts in `CONTEXT-MAP.md`) if the repo has one, and name things
the way it does. Where the conversation settled a term the glossary doesn't carry yet, or
sharpened one it defines loosely, call the Skill tool with "domain-modeling" to update
`CONTEXT.md` before writing the spec — the spec then uses the term the glossary now
defines. ADRs in `docs/adr/` record decisions this spec should not re-litigate.

## Write the spec

Path: `docs/specs/YYYY-MM-DD-<topic>.md`. A spec for this topic already in `docs/specs/`
gets updated in place — the spec is a living document. Sections, in order:

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

Each slice must be self-contained enough that an
implementer given only the spec and a slice number can execute it — requirements live in
the slice, not in the reader's memory of the conversation. Slice progress is later tracked
by appending `— DONE` to slice headings, so keep headings stable.

## Self-review

Reread the draft with fresh eyes and fix inline — no re-review loop. Every item below
answered for every section:

1. **Placeholders** — any TBD, TODO, or vague requirement? Pin it down.
2. **Contradictions** — do sections disagree with each other?
3. **Ambiguity** — could a requirement be read two ways? Pick one and make it explicit.
4. **Slice independence** — can each slice be executed from the spec alone, in order?

## Hand over

Commit the spec. Then ask the user to review the file before anything gets built:

> Spec written and committed to `<path>`. Review it and tell me what to change — when it's
> approved, I'll call the Skill tool with "implement-spec" to execute it.
