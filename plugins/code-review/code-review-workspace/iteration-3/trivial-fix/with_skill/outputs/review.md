**Lightweight review** — single-line comment fix in README.

The staged change adds a README.md with a corrected inline comment: `capitalize("hello world")` returns `"Hello world"`, not `"Hello World"`. The fix accurately reflects that `capitalize` uppercases only the first letter of the string, not each word. Looks correct, no issues.

Note: a `README.md.patch` file describing the before/after is also staged. This appears to be scaffolding for the change description and probably should not be committed alongside the README itself.
