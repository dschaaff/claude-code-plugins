---
name: implement-spec
description: REQUIRED whenever implementing work described by a spec file in docs/specs, including resuming a partially-done spec - the spec gets opened inside this skill rather than before it. Controller loop - a fresh subagent per slice, a review of each slice against the spec, and one whole-branch review at the end.
---

# Implement Spec

Implement work described by the user in the spec. The spec file is where requirements, progress markers, and parked findings all live.
Use /tdd where possible, at pre-agreed seams.

Check your work after each slice.

**Continuous execution:** work straight through the slices, only asking for human input when you can't
resolve something on your own.

Communication to and from subagents should be sparse. Communicate primarily
through context pointers: to the spec, tickets, research notes, and previous
commits. Don't duplicate information already available via pointers.

## Steps

1. **Feature branch.** Work on a feature branch — create one when HEAD is main or master.
   Worktree only if the user asks for one.
2. **Read the spec once.** Note the design decisions and testing seams that bind every
   slice.
3. **Resume check.** Slice headings marked `— DONE` are complete; start at the first slice
   without the marker.
4. **Todo per remaining slice.**
5. **Conflict scan.** Slices that contradict each other or the design decisions get raised
   with the user as one batched question before execution — not one interrupt each.

6. **Feature branch.** Work on a feature branch — create one when HEAD is main
   or master. Worktree only if the user asks for one.
7. Read the spec and understand the task graph. Determine if slices can be
   worked on in parallel.
8. (optional) Use an exploration subagent to conduct any exploration required
   by the slices - relevant codebase files or external documentation. Ensure
   the exploration subagent can save files - it should save its markdown notes
   in a directory outside the repo, accessible by all future subagents. This
   lets implementer subagents focus on implementation rather than exploration.
9. Use implementer subagents to implement each slice. For parallel slices, the
   implementers should work in their own worktree. When they are done, use a
   merge subagent to merge the slice to the feature branch.
10. If this changes the frontier of available slices, kick off more implementer
    subagents to work on the new slices. This allows for maximum concurrency.
11. Once all slices are done, do a whole-branch review. Use the skill tool with
    "verify" with the spec path and the full branch range (`git merge-base
    <main> HEAD` to `HEAD`), pointing it at any parked findings in the spec to
    triage which block merge.

## Finish

Run the full test suite fresh and report the actual results. Then ask the user: open a PR,
merge, or leave the branch as is.
