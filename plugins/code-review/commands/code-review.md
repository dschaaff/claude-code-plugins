---
description: Perform comprehensive code review of recent changes
---

# Code Review Request

Use the **code-reviewer** agent to review recent changes.

Determine review scope based on what the user provides:
- **PR number or URL**: Review the diff for that specific pull request.
- **Specific file names**: Focus the review on those files only.
- **Nothing specified**: Review all uncommitted or recently committed changes on the current branch.
- **On the default branch with no uncommitted changes**: Review the most recent commit.
