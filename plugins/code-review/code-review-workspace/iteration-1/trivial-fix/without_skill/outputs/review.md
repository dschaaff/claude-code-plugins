# Code Review

## Summary

This change adds a `README.md` for a string utility library along with a `README.md.patch` file that describes a one-line comment fix.

## Scope

Trivial -- a documentation-only change correcting a misleading inline comment in a usage example.

## Findings

### 1. Fix not applied (bug) -- README.md:15

The `README.md.patch` file describes changing `// "Hello World"` to `// "Hello world"` because `capitalize()` only capitalizes the first letter of the string, not each word. This is a valid correction.

However, the staged `README.md` still contains the incorrect comment:

```js
capitalize("hello world"); // "Hello World"
```

It should read:

```js
capitalize("hello world"); // "Hello world"
```

The patch description is staged but the fix it describes was never applied to the actual file.

### 2. Patch file should not be committed -- README.md.patch

The `README.md.patch` file is metadata about the change, not part of the project. It describes the before/after state and rationale. This belongs in the commit message, not in the repository. Remove it from the staged changes.

## Recommendation

1. Apply the actual fix to `README.md` line 15: change `"Hello World"` to `"Hello world"`.
2. Unstage and remove `README.md.patch` -- put that context in the commit message instead.
3. Verify what `capitalize` actually does. If it capitalizes each word (title case), the original comment is correct and no fix is needed. If it only capitalizes the first character of the string, the fix is correct.
