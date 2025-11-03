# Code Review Plugin

Comprehensive code review plugin for Claude Code that provides security analysis, language-specific best practices, and structured feedback.

## Features

### 🔍 Comprehensive Review Framework
- **Plan Alignment**: Compares implementation against planning documents
- **Code Quality**: Checks patterns, conventions, error handling, and maintainability
- **Security Analysis**: 12-point security checklist covering OWASP Top 10
- **Architecture Review**: SOLID principles, design patterns, and scalability
- **Performance**: N+1 queries, algorithm complexity, memory leaks
- **Testing Quality**: Coverage, edge cases, and test isolation
- **Documentation**: Comments, API docs, and standards compliance

### 🌐 Language-Specific Best Practices
Automatically detects and applies appropriate standards for:
- **TypeScript/JavaScript**: Type safety, async/await, React hooks
- **Python**: Type hints, PEP 8, context managers
- **Go**: Error handling, goroutines, context usage
- **Rust**: Result types, ownership, lifetimes
- **Java**: (extendable for additional languages)

### 📊 Structured Output
- Clear categorization: Critical / Important / Suggestions
- Specific file and line references
- Code examples for fixes
- Actionable next steps
- Quality metrics dashboard

## Usage

### Via Slash Command
```
/code-review
```
Triggers a comprehensive review of all uncommitted changes.

### Agent Usage
The `code-reviewer` agent is automatically invoked when:
- A major project step is completed
- Explicitly mentioned in conversation
- Before creating pull requests

## What Gets Reviewed

The agent reviews:
- ✅ All staged and unstaged changes
- ✅ Changed file contents (not just diffs)
- ✅ Corresponding test files
- ✅ Related documentation
- ✅ TODO/FIXME comments

## Review Output Structure

```markdown
# Code Review Summary
**Branch**: [name]
**Files Changed**: [list]

## 🎯 Overall Assessment
[High-level summary]

## ✅ Strengths
[What was done well]

## 🔴 Critical Issues (Must Fix)
[Security, data loss, blocking issues]

## 🟡 Important Issues (Should Fix)
[Quality, maintainability, performance]

## 💡 Suggestions (Nice to Have)
[Optimizations and enhancements]

## 📊 Quality Metrics
- Test Coverage
- Security Status
- Performance Assessment
- Documentation Quality

## 📋 Review Checklist
[Status of key quality gates]

## 🎬 Next Steps
[Ordered action items]
```

## Security Checks

The plugin checks for:
- Hardcoded secrets and API keys
- SQL injection vulnerabilities
- Command injection risks
- Input validation and sanitization
- Authentication/authorization
- Encryption practices
- CORS/CSP configuration
- Dependency vulnerabilities
- File upload security
- Rate limiting
- Directory traversal
- Session management

## Configuration

### Git Context
The agent automatically captures:
- Current git status
- Changed files list
- Staged and unstaged changes
- Current branch
- Recent commits

### Planning Context
Searches for:
- TODO.md, PLAN.md, ROADMAP.md
- ADR documents in docs/adr/
- Issue/ticket references in commits
- Inline TODO/FIXME comments

## Best Practices

### When to Use
✅ After completing a logical feature or step
✅ Before creating a pull request
✅ After fixing complex bugs
✅ When explicitly requested

### When NOT to Use
❌ For small typo fixes
❌ During active development (wait for completion)
❌ For documentation-only changes

## Example Interaction

```
User: I've finished implementing the user authentication system as outlined in step 3 of our plan

Claude: Great work! Now let me use the code-reviewer agent to review the implementation
        against our plan and coding standards.

[Agent performs comprehensive review]

Agent Output:
# Code Review Summary
**Branch**: feature/auth-system
**Files Changed**: 5 (auth.ts, auth.test.ts, middleware.ts, ...)

## 🎯 Overall Assessment
The authentication implementation is well-structured and follows modern best practices...

[Detailed categorized feedback with specific file:line references]
```

## Version History

### v2.0.0
- Enhanced git context gathering (staged/unstaged separation)
- Added language-specific best practices (TS/JS, Python, Go, Rust)
- Comprehensive 12-point security checklist
- Performance analysis framework
- Structured output format with emojis
- Planning context integration
- Testing quality assessment
- Reduced duplication between agent and command

### v1.0.0
- Initial release with basic code review functionality

## Contributing

This plugin is part of a personal marketplace. Feel free to fork and customize for your needs.

## License

MIT
