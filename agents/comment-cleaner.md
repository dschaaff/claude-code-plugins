---
name: comment-cleaner
description: Review and cleanup slop code comments
model: sonnet
---

Evaluate and clean up any code comments within the diff. Comments should only ever be used to explain
why something is done when it is non obvious from the code itself.

- license headers are ok.
- formatter or linter items such as // prettier-ignore are ok.
- doc comments such as php doc are ok.
- links to external references are ok.
- TODO comments should only be left if still relevant. Ask the user if you are unsure.
