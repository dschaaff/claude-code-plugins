---
name: brainstorm
description: REQUIRED first step for any new feature, tool, service, or design work - invoke before exploring files or writing anything, including requests that sound simple enough to just do. A relentless one-question-at-a-time interview ending in shared understanding, then the `to-spec` skill. Executing an existing spec is the `implement-spec` skill; stress-testing a non-build idea is the `grilling` skill.
---

# Brainstorm

Turn an idea into shared understanding through a relentless collaborative interview.

<HARD-GATE>
Everything this skill produces is chat: questions, then a design summary. Implementation,
scaffolding, files, and code all wait until the user confirms shared understanding. This
holds for every project regardless of perceived simplicity — "simple" projects are where
unexamined assumptions waste the most work.
</HARD-GATE>

## Process

### 1. Explore context first

Before asking anything, look at the project: files, docs, recent commits, existing specs and
conventions. **Facts** come from the environment — look up every one you need. The
**decisions** are the user's: put each one to them and wait for the answer.

Read `CONTEXT.md` (or the contexts listed in `CONTEXT-MAP.md`) if the repo has one, and use
its terms for the rest of the interview. Where the user's wording conflicts with a defined
term, or the idea needs a term the glossary lacks, that becomes a question rather than a
silent choice. Writing the term down belongs to the `domain-modeling` skill, after the gate
above lifts.

Done when: every fact the interview depends on is looked up, and the glossary terms in play
are in hand.

### 2. Check scope early

If the request spans multiple independent subsystems, say so immediately and help decompose
into sub-projects before refining details. Questions spent polishing a project that needs
splitting are wasted. Each sub-project then gets its own brainstorm → spec cycle.

### 3. Interview — one question at a time

Walk down each branch of the decision tree, resolving dependencies between decisions in
order — settle the decisions later questions depend on first.

- **One question per message.** Multiple questions at once are bewildering. A topic that
  needs more exploration becomes multiple questions.
- **Recommend an answer for every question**, with your reasoning, leading with the
  recommendation. Multiple choice where possible; open-ended is fine too.
- Focus on purpose, constraints, and success criteria — implementation trivia you can decide
  yourself stays out.

Done when: every branch of the tree has an answer from the user, and no answer has opened a
branch you haven't walked.

### 4. Propose approaches when the solution space is open

When there are genuinely different ways to build it, present 2–3 approaches with trade-offs,
leading with your recommendation and why. Apply YAGNI ruthlessly to every approach — strip
features nobody asked for.

### 5. Present the design and confirm

Present a design summary in chat, scaled to the project (a few sentences for simple things;
sections for architecture, components, data flow, error handling, and testing for nuanced
ones). Ask whether it matches their intent. Revise until they confirm.

## Terminal state

The user has approved the design summary. Point them to the `to-spec` skill to turn the
conversation into a spec file — that skill writes the spec; this one ends at shared
understanding.
