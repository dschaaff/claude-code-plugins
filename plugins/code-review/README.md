# Code Review Plugin

Comprehensive code review agent for Claude Code that analyzes code quality, security, architecture, and testing.

## Usage

```
/code-review
```

Reviews recent uncommitted or committed changes on the current branch.

## What It Does

The agent performs:
- Code quality and maintainability analysis
- Security vulnerability checks
- Architecture and design review
- Performance assessment
- Test coverage evaluation
- Language-specific best practices

Output is categorized as **Critical** / **Important** / **Suggestions** with specific file references and actionable fixes.

## When to Use

✅ After completing a feature or logical step
✅ Before creating a pull request
✅ After fixing complex bugs

❌ Skip for trivial changes, typos, or work in progress

## Example

```
User: I've finished the authentication system from step 3

Claude: Let me review that with the code-reviewer agent.

[Performs review with categorized issues and specific fixes]
```

## Version

**v2.1.0** - Simplified agent design to trust Claude's intelligence, added scope validation and review completion criteria.

## License

MIT
